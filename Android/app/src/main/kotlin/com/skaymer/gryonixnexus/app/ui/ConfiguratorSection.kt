package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import com.skaymer.gryonixnexus.app.configurator.ConfiguratorHistoryEntry
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.width
import com.skaymer.gryonixnexus.app.ui.design.CardSurface
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.ProminentButton
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.configurator.ConfiguratorViewModel
import com.skaymer.gryonixnexus.app.configurator.ScenarioOption
import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import com.skaymer.gryonixnexus.app.licensing.LicenseStatus
import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.core.DistributionProfileID
import com.skaymer.gryonixnexus.recipe.OpenPortRequirement
import com.skaymer.gryonixnexus.recipe.sortedByPort
import com.skaymer.gryonixnexus.recipe.sortedByProtocol
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

/** The configurator: the answers, and the files they produce */
@Composable
fun ConfiguratorSection(
    model: ConfiguratorViewModel,
    /** The scenario being answered, or null on the first screen */
    scenarioID: String?,
    /** The Cloudflare tokens — what the tunnel paths read */
    cloudflare: com.skaymer.gryonixnexus.app.secrets.CloudflareTokenStore,
    /** The named accounts those tokens belong to */
    dnsCredentials: com.skaymer.gryonixnexus.app.secrets.DNSCredentials,
    secrets: com.skaymer.gryonixnexus.app.secrets.SecretStore,
    store: com.skaymer.gryonixnexus.app.shell.SettingsStore,
    onPickScenario: (ScenarioOption) -> Unit,
    onInstall: () -> Unit,
    onOpenArtifact: (Artifact) -> Unit,
) {
    val form by model.form.collectAsState()
    val bundle by model.bundle.collectAsState()
    val openPorts by model.openPorts.collectAsState()
    val error by model.error.collectAsState()
    val savedDeployment by model.savedDeployment.collectAsState()

    val scenario = ScenarioOption.all.firstOrNull { it.id == scenarioID }
    when {
        scenario == null -> ConfiguratorScenariosScreen(onPick = onPickScenario)
        bundle != null -> ConfiguratorResultScreen(
            bundle = bundle!!,
            openPorts = openPorts,
            hasDeployment = savedDeployment != null,
            services = model.installedServices(),
            onInstall = onInstall,
            onOpenArtifact = onOpenArtifact,
        )
        else -> Column(Modifier.fillMaxSize()) {
            error?.let { message ->
                Text(
                    message,
                    color = Gryonix.colors.danger,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier
                        .background(Gryonix.colors.groupedBackground)
                        .fillMaxWidth()
                        .padding(horizontal = Metrics.listInset + 4.dp, vertical = 8.dp),
                )
            }
            ConfiguratorWizardScreen(
                model = model,
                scenario = scenario,
                form = form,
                cloudflare = cloudflare,
                dnsCredentials = dnsCredentials,
                secrets = secrets,
                store = store,
                onGenerate = { model.generate() },
            )
        }
    }
}

@Composable
private fun ConfiguratorResultScreen(
    bundle: com.skaymer.gryonixnexus.core.GeneratedBundle,
    openPorts: List<OpenPortRequirement>,
    hasDeployment: Boolean,
    services: Set<ServiceID>,
    onInstall: () -> Unit,
    onOpenArtifact: (Artifact) -> Unit,
) {
    var sortPortsByProtocol by remember { mutableStateOf(false) }
    LazyColumn(
        modifier = Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item { RequirementsSection(services) }
        item {
            if (hasDeployment) {
                GroupedSection {
                    ValueRow(
                        title = stringResource(R.string.install_title),
                        subtitle = stringResource(R.string.install_subtitle),
                        value = null,
                        onClick = onInstall,
                        showDivider = false,
                    )
                }
            } else {
                Text(
                    stringResource(R.string.install_needs_access),
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.secondaryLabel,
                    modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
                )
            }
        }
        if (bundle.warnings.isNotEmpty()) {
            item {
                GroupedSection(header = stringResource(R.string.warnings)) {
                    bundle.warnings.forEach { warning ->
                        GroupedRow(showDivider = warning != bundle.warnings.last()) {
                            Text(
                                warning,
                                style = MaterialTheme.typography.bodySmall,
                                color = Gryonix.colors.warning,
                            )
                        }
                    }
                }
            }
        }
        item {
            GroupedSection(header = stringResource(R.string.artifacts)) {
                bundle.artifacts.forEach { artifact ->
                    ValueRow(
                        title = artifact.fileName,
                        subtitle = artifact.summary,
                        value = null,
                        onClick = { onOpenArtifact(artifact) },
                        showDivider = artifact != bundle.artifacts.last(),
                    )
                }
            }
        }
        if (openPorts.isNotEmpty()) {
            item {
                GroupedSection(header = stringResource(R.string.configuration_ports)) {
                    GroupedRow {
                        IOSSegmentedControl(
                            segments = listOf(false, true),
                            selected = sortPortsByProtocol,
                            label = {
                                stringResource(
                                    if (it) R.string.configuration_ports_sort_protocol
                                    else R.string.configuration_ports_sort_port
                                )
                            },
                            onSelect = { sortPortsByProtocol = it },
                        )
                    }
                    val sorted = if (sortPortsByProtocol) {
                        openPorts.sortedByProtocol()
                    } else {
                        openPorts.sortedByPort()
                    }
                    sorted.forEach { requirement ->
                        GroupedRow(showDivider = requirement != sorted.last()) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                            ) {
                                Text(
                                    requirement.id,
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontFamily = FontFamily.Monospace,
                                    color = Gryonix.colors.label,
                                )
                                Text(
                                    requirement.purpose,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = Gryonix.colors.secondaryLabel,
                                )
                            }
                        }
                    }
                }
            }
        }
        if (bundle.notes.isNotEmpty()) {
            item {
                GroupedSection(header = stringResource(R.string.notes)) {
                    bundle.notes.forEach { note ->
                        GroupedRow(showDivider = note != bundle.notes.last()) {
                            Text(
                                note,
                                style = MaterialTheme.typography.bodySmall,
                                color = Gryonix.colors.secondaryLabel,
                            )
                        }
                    }
                }
            }
        }
    }
}

/** What the target server must have before the install starts */
@Composable
private fun RequirementsSection(services: Set<ServiceID>) {
    val requirements = ServiceRegistry.requirements(services)
    val footer = if (ServiceID.GITLAB in services) R.string.requirements_footer_gitlab
    else R.string.requirements_footer_mail
    GroupedSection(
        header = stringResource(R.string.requirements_title),
        footer = stringResource(footer),
    ) {
        ValueRow(stringResource(R.string.requirements_os), "Debian 12+ / Ubuntu 22.04+ · 64-bit", null)
        ValueRow(
            stringResource(R.string.requirements_memory),
            stringResource(R.string.requirements_at_least, requirements.memoryGB.toString()),
            null,
        )
        ValueRow(
            stringResource(R.string.requirements_disk),
            stringResource(R.string.requirements_at_least, requirements.diskGB.toString()),
            null,
        )
        ValueRow(
            stringResource(R.string.requirements_access),
            stringResource(R.string.requirements_access_value),
            null,
            showDivider = requirements.installsDocker,
        )
        if (requirements.installsDocker) {
            ValueRow("Docker", stringResource(R.string.requirements_docker_auto), null, showDivider = false)
        }
    }
}

/** A password the model already holds */
@Composable
private fun PasswordField(
    label: String,
    initial: String,
    onChange: (String) -> Unit,
    showDivider: Boolean = true,
) {
    var value by remember { mutableStateOf(initial) }
    FieldRow(
        label = label,
        value = value,
        onValueChange = {
            value = it
            onChange(it)
        },
        showDivider = showDivider,
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
    )
}

@Composable
internal fun DistributionRow(
    label: String,
    selected: DistributionProfileID,
    showDivider: Boolean = true,
    onPick: (DistributionProfileID) -> Unit,
) {
    GroupedRow(
        showDivider = showDivider,
        trailing = {
            IOSSegmentedControl(
                segments = DistributionProfileID.entries.toList(),
                selected = selected,
                modifier = Modifier.width(180.dp),
                label = { it.wireValue },
                onSelect = onPick,
            )
        },
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodyLarge,
            color = Gryonix.colors.label,
        )
    }
}

/** One generated file, whole */
@Composable
fun ArtifactScreen(artifact: Artifact) {
    val status by LicenseGate.status.collectAsState()
    if (status !is LicenseStatus.Active) {
        LockCard()
        return
    }
    Column(
        Modifier
            .fillMaxSize()
            .background(Gryonix.colors.groupedBackground)
            .padding(Metrics.listInset)
    ) {
        Text(
            artifact.summary,
            style = MaterialTheme.typography.bodySmall,
            color = Gryonix.colors.secondaryLabel,
        )
        artifact.suggestedPath?.let {
            Text(it, style = MaterialTheme.typography.labelSmall, color = Gryonix.colors.tertiaryLabel)
        }
        CardSurface(Modifier.fillMaxSize().padding(top = 8.dp)) {
            LazyColumn(Modifier.fillMaxSize()) {
                item {
                    SelectionContainer {
                        Text(
                            artifact.contents,
                            fontFamily = FontFamily.Monospace,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier
                                .horizontalScroll(rememberScrollState())
                                .padding(12.dp)
                        )
                    }
                }
            }
        }
    }
}
