package com.skaymer.gryonixnexus.app.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.WarningAmber
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.configurator.CategorySelection
import com.skaymer.gryonixnexus.app.configurator.DNSProviderKind
import com.skaymer.gryonixnexus.app.configurator.DNSProviderPublishModel
import com.skaymer.gryonixnexus.app.configurator.ConfigurationExport
import com.skaymer.gryonixnexus.app.licensing.LicensePrompt
import com.skaymer.gryonixnexus.app.configurator.ConfiguratorForm
import com.skaymer.gryonixnexus.app.configurator.ConfiguratorViewModel
import com.skaymer.gryonixnexus.app.configurator.ScenarioOption
import com.skaymer.gryonixnexus.app.configurator.ServiceQuestions
import com.skaymer.gryonixnexus.app.configurator.WizardStep
import com.skaymer.gryonixnexus.app.configurator.hasVpnProtocol
import com.skaymer.gryonixnexus.app.configurator.wizardSteps
import com.skaymer.gryonixnexus.app.secrets.DNSCredential
import com.skaymer.gryonixnexus.app.secrets.DNSCredentialTokenStore
import com.skaymer.gryonixnexus.app.secrets.DNSCredentials
import com.skaymer.gryonixnexus.app.secrets.CloudflareTokenStore
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.app.secrets.TailscaleKeyStore
import androidx.compose.ui.platform.LocalUriHandler
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.AdvancedSection
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.ProminentButton
import com.skaymer.gryonixnexus.app.ui.design.Separator
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ModelBackend
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun ConfiguratorWizardScreen(
    model: ConfiguratorViewModel,
    scenario: ScenarioOption,
    form: ConfiguratorForm,
    /** The Cloudflare tokens — what the tunnel paths read */
    cloudflare: CloudflareTokenStore,
    dnsCredentials: DNSCredentials,
    /** Where those tokens live — see `DNSCredentialTokenStore` */
    secrets: SecretStore,
    /** What the rest of the wizard reads its settings from */
    store: SettingsStore,
    onGenerate: () -> Unit,
) {
    var index by remember { mutableStateOf(0) }
    var standingOnVpn by remember { mutableStateOf(false) }
    var picking by remember { mutableStateOf<ServiceCategory?>(null) }
    var acknowledgedDNS by rememberSaveable { mutableStateOf(false) }
    var showCrowdSecNudge by remember { mutableStateOf(false) }

    val steps = wizardSteps(form, standingOnVpn)
    val current = steps[index.coerceIn(0, steps.lastIndex)]
    if (current == WizardStep.VPN_PROTOCOL) standingOnVpn = true
    LaunchedEffect(current) { model.useDemoAddressesIfLocked() }

    val dnsZones = remember(form) { ConfigurationExport.preview(form) }
    val hasTunnelToken = remember(current) { cloudflare.canIssueTunnelToken }
    val tailscaleKeys = remember(secrets) { TailscaleKeyStore(secrets) }
    var hasTailscaleKey by remember { mutableStateOf(tailscaleKeys.key() != null) }

    val publishModel = remember(dnsCredentials, secrets) {
        DNSProviderPublishModel(
            dnsCredentials,
            DNSCredentialTokenStore(secrets),
            initialProviderKind = dnsCredentials.selected?.kind ?: DNSProviderKind.CLOUDFLARE,
        )
    }

    val artifactContext = LocalContext.current
    val artifactScope = rememberCoroutineScope()
    var savingArtifact by remember { mutableStateOf<Artifact?>(null) }
    var artifactSaveError by remember { mutableStateOf<String?>(null) }
    val saveArtifactTo = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("*/*"),
    ) { uri ->
        val artifact = savingArtifact
        savingArtifact = null
        if (uri == null || artifact == null) return@rememberLauncherForActivityResult
        artifactScope.launch {
            val wrote = withContext(Dispatchers.IO) {
                runCatching {
                    artifactContext.contentResolver.openOutputStream(uri)
                        ?.use { it.write(artifact.contents.toByteArray()) }
                }.isSuccess
            }
            artifactSaveError = if (wrote) null else artifactContext.getString(R.string.dkim_export_failed)
        }
    }
    val onSaveArtifact: (Artifact) -> Unit = { artifact ->
        if (LicensePrompt.allow()) {
            savingArtifact = artifact
            saveArtifactTo.launch(artifact.fileName)
        }
    }

    picking?.let { category ->
        ServicePickerSheet(
            category = category,
            form = form,
            onSet = { ids -> model.update { CategorySelection.setSelection(it, category, ids) } },
            onClose = { picking = null },
        )
    }

    fun advance() {
        if (current == WizardStep.VPN_PROTOCOL) standingOnVpn = false
        if (index < steps.lastIndex) index += 1
    }

    if (showCrowdSecNudge) {
        IOSAlert(
            title = stringResource(R.string.crowdsec_nudge_title),
            message = stringResource(R.string.crowdsec_nudge_message),
            onDismiss = { showCrowdSecNudge = false },
            actions = listOf(
                AlertAction(stringResource(R.string.crowdsec_nudge_continue)) {
                    showCrowdSecNudge = false
                    advance()
                },
                AlertAction(stringResource(R.string.crowdsec_toggle), preferred = true) {
                    showCrowdSecNudge = false
                    model.update { it.copy(serviceSettings = it.serviceSettings.copy(crowdsecEnabled = true)) }
                    advance()
                },
            ),
        )
    }

    Column(Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground)) {
        LazyColumn(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            contentPadding = GroupedContentPadding,
            verticalArrangement = GroupedSpacing,
        ) {
            item {
                Text(
                    stringResource(R.string.wizard_step_of, index + 1, steps.size),
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.secondaryLabel,
                    modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
                )
            }
            when (current) {
                WizardStep.SERVICES -> servicesStep(model, form) { picking = it }
                WizardStep.VPN_PROTOCOL -> vpnStep(model, form)
                WizardStep.DOMAIN -> domainStep(model, form, hasTunnelToken)
                WizardStep.ADDRESS -> addressStep(model, form, tailscaleKeys, hasTailscaleKey) { hasTailscaleKey = it }
                WizardStep.ADMIN -> adminStep(model, form)
                WizardStep.DNS -> dnsStep(
                    form = form,
                    zones = dnsZones,
                    publish = publishModel,
                    dnsCredentials = dnsCredentials,
                    artifactSaveError = artifactSaveError,
                    onSaveArtifact = onSaveArtifact,
                    acknowledged = acknowledgedDNS,
                    onAcknowledge = { acknowledgedDNS = it },
                )
                WizardStep.REVIEW -> reviewStep(scenario, form)
            }
        }
        WizardBar(
            canGoBack = index > 0,
            isLast = current == WizardStep.REVIEW,
            canAdvance = canAdvance(current, form, acknowledgedDNS, hasTailscaleKey),
            onBack = {
                if (current == WizardStep.VPN_PROTOCOL) standingOnVpn = false
                if (index > 0) index -= 1
            },
            onNext = {
                if (current == WizardStep.SERVICES &&
                    form.includeDashboardAccess &&
                    !form.serviceSettings.crowdsecEnabled
                ) {
                    showCrowdSecNudge = true
                } else {
                    advance()
                }
            },
            onGenerate = onGenerate,
        )
    }
}

private fun canAdvance(
    step: WizardStep,
    form: ConfiguratorForm,
    acknowledgedDNS: Boolean,
    hasTailscaleKey: Boolean,
): Boolean =
    when (step) {
        WizardStep.SERVICES ->
            ServiceQuestions.unanswered(form).isEmpty()
        WizardStep.VPN_PROTOCOL -> hasVpnProtocol(form)
        WizardStep.DOMAIN -> form.domain.isNotBlank()
        WizardStep.ADDRESS ->
            form.publicIP.isNotBlank() && (form.scope != DeploymentScope.TAILSCALE_ONLY || hasTailscaleKey)
        WizardStep.ADMIN -> true
        WizardStep.DNS -> acknowledgedDNS
        WizardStep.REVIEW -> true
    }

@Composable
private fun WizardBar(
    canGoBack: Boolean,
    isLast: Boolean,
    canAdvance: Boolean,
    onBack: () -> Unit,
    onNext: () -> Unit,
    onGenerate: () -> Unit,
) {
    Column(Modifier.fillMaxWidth().background(Gryonix.colors.barBackground)) {
        Separator()
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Metrics.listInset, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (canGoBack) {
                PlainButton(text = stringResource(R.string.back), onClick = onBack)
            } else {
                Column(Modifier.width(1.dp)) {}
            }
            ProminentButton(
                text = stringResource(if (isLast) R.string.generate else R.string.wizard_next),
                onClick = if (isLast) onGenerate else onNext,
                enabled = canAdvance,
                modifier = Modifier.width(180.dp),
            )
        }
    }
}

// ─────────────────────────────────────────────────────────────── the steps

private fun androidx.compose.foundation.lazy.LazyListScope.servicesStep(
    model: ConfiguratorViewModel,
    form: ConfiguratorForm,
    onPick: (ServiceCategory) -> Unit,
) {
    item {
        GroupedSection(
            header = stringResource(R.string.wizard_services_header),
            note = stringResource(R.string.wizard_services_footer),
        ) {
            val categories = CategorySelection.available(form.scope)
            categories.forEach { category ->
                val chosen = CategorySelection.selection(form, category)
                val picker = CategorySelection.offersPicker(form, category)
                ToggleRow(
                    title = categoryTitle(category),
                    checked = chosen.isNotEmpty(),
                    onCheckedChange = { on ->
                        model.update { CategorySelection.toggleCategory(it, category, on) }
                    },
                    showDivider = picker || category != categories.last(),
                    infoNote = if (category == ServiceCategory.SINGLE_SIGN_ON) {
                        stringResource(R.string.authelia_note)
                    } else {
                        null
                    },
                )
                if (picker) {
                    GroupedRow(
                        onClick = { onPick(category) },
                        showDivider = category != categories.last(),
                        trailing = {
                            Text(
                                CategorySelection.chosenNames(form, category),
                                style = MaterialTheme.typography.bodyLarge,
                                color = Gryonix.colors.secondaryLabel,
                            )
                            DisclosureChevron()
                        },
                    ) {
                        Text(
                            stringResource(R.string.wizard_pick_one),
                            style = MaterialTheme.typography.bodyLarge,
                            color = Gryonix.colors.label,
                        )
                    }
                }
                val categoryNote = CategorySelection.warning(form, category)
                if (categoryNote != null) {
                    val isWarning = categoryNote == CategorySelection.WarningKey.GITLAB_MEMORY
                    GroupedRow(showDivider = category != categories.last()) {
                        Icon(
                            if (isWarning) Icons.Filled.WarningAmber else Icons.Filled.Info,
                            contentDescription = null,
                            tint = if (isWarning) Gryonix.colors.warning
                                   else Gryonix.colors.secondaryLabel,
                            modifier = Modifier.size(16.dp),
                        )
                        Text(
                            stringResource(
                                if (isWarning) R.string.wizard_gitlab_warning
                                else R.string.wizard_ollama_no_ui
                            ),
                            style = MaterialTheme.typography.bodySmall,
                            color = Gryonix.colors.secondaryLabel,
                            modifier = Modifier.padding(start = 6.dp),
                        )
                    }
                }
            }
        }
    }
    if (ServiceRegistry.selection(ServiceCategory.AI, form.services).isNotEmpty()) {
        item {
            GroupedSection(header = stringResource(R.string.wizard_model_backend_header)) {
                ModelBackendRow(
                    value = form.serviceSettings.modelBackend,
                    onChoose = { backend ->
                        model.update {
                            it.copy(serviceSettings = it.serviceSettings.copy(modelBackend = backend))
                        }
                    },
                )
                GroupedRow(showDivider = form.serviceSettings.modelBackend != ModelBackend.EXTERNAL) {
                    Text(
                        stringResource(
                            when (form.serviceSettings.modelBackend) {
                                ModelBackend.HERE -> R.string.wizard_model_backend_here_cost
                                ModelBackend.HOME -> R.string.wizard_model_backend_home_cost
                                ModelBackend.EXTERNAL -> R.string.wizard_model_backend_external_cost
                            },
                        ),
                        style = MaterialTheme.typography.bodySmall,
                        color = Gryonix.colors.secondaryLabel,
                    )
                }
                if (form.serviceSettings.modelBackend != ModelBackend.EXTERNAL) {
                    ToggleRow(
                        title = stringResource(R.string.wizard_ollama_gpu),
                        checked = form.serviceSettings.ollamaUsesGPU,
                        onCheckedChange = { uses ->
                            model.update {
                                it.copy(serviceSettings = it.serviceSettings.copy(ollamaUsesGPU = uses))
                            }
                        },
                    )
                    GroupedRow(showDivider = false) {
                        Text(
                            stringResource(
                                if (form.serviceSettings.ollamaUsesGPU) {
                                    R.string.wizard_ollama_gpu_on_cost
                                } else {
                                    R.string.wizard_ollama_gpu_off_cost
                                },
                            ),
                            style = MaterialTheme.typography.bodySmall,
                            color = Gryonix.colors.secondaryLabel,
                        )
                    }
                }
            }
        }
    }
    val questions = ServiceQuestions.raisedBy(form.services, form.topology, form.scope)
    if (questions.isNotEmpty()) {
        item { ServiceAnswersSection(model, form, questions) }
    }
    val advanced = ServiceRegistry.categories
        .filter { it != ServiceCategory.VPN }
        .flatMap { ServiceRegistry.selection(it, form.services) }
    if (advanced.isNotEmpty()) {
        item {
            AdvancedSection {
                advanced.forEachIndexed { index, id ->
                    ServiceAdvancedFields(model, form, id, showDivider = index != advanced.lastIndex)
                }
            }
        }
    }
    item {
        GroupedSection(
            header = stringResource(R.string.access_title),
            note = stringResource(R.string.access_hint),
        ) {
            ToggleRow(
                title = stringResource(R.string.access_toggle),
                checked = form.includeDashboardAccess,
                onCheckedChange = { on -> model.update { it.copy(includeDashboardAccess = on) } },
                showDivider = form.includeDashboardAccess,
            )
            if (form.includeDashboardAccess) {
                ToggleRow(
                    title = stringResource(R.string.crowdsec_toggle),
                    subtitle = stringResource(R.string.crowdsec_hint),
                    checked = form.serviceSettings.crowdsecEnabled,
                    onCheckedChange = { on ->
                        model.update { it.copy(serviceSettings = it.serviceSettings.copy(crowdsecEnabled = on)) }
                    },
                    showDivider = false,
                )
            }
        }
    }
    if (form.includeDashboardAccess) {
        item {
            AdvancedSection(footer = stringResource(R.string.access_hint)) {
                FieldRow(
                    label = stringResource(R.string.access_user_label),
                    value = form.dashboardSSHUser,
                    onValueChange = { value -> model.update { it.copy(dashboardSSHUser = value) } },
                )
                ToggleRow(
                    title = stringResource(R.string.access_existing_user),
                    subtitle = stringResource(R.string.access_existing_user_hint),
                    checked = form.useExistingUser,
                    onCheckedChange = { on -> model.update { it.copy(useExistingUser = on) } },
                    showDivider = form.useExistingUser,
                )
                if (form.useExistingUser) {
                    WizardPasswordField(
                        label = stringResource(
                            if (form.topology == Topology.SINGLE_HOST) R.string.access_password_single
                            else R.string.access_password_vps
                        ),
                        initial = model.password(SSHHostID.VPS),
                        onChange = { model.setPassword(SSHHostID.VPS, it) },
                        showDivider = form.topology == Topology.VPS_RELAY_WITH_HOME_BACKEND,
                    )
                    if (form.topology == Topology.VPS_RELAY_WITH_HOME_BACKEND) {
                        WizardPasswordField(
                            label = stringResource(R.string.access_password_home),
                            initial = model.password(SSHHostID.HOME),
                            onChange = { model.setPassword(SSHHostID.HOME, it) },
                            showDivider = false,
                        )
                    }
                }
            }
        }
    }
    item {
        val implied = model.installedServices() - form.services
        if (implied.isNotEmpty()) {
            Text(
                stringResource(
                    R.string.installs_too,
                    implied.mapNotNull { ServiceRegistry.service(it)?.displayName }.sorted().joinToString(", "),
                ),
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
            )
        }
    }
}

/** The VPN shelf's own page: the protocols, any number together */
private fun androidx.compose.foundation.lazy.LazyListScope.vpnStep(
    model: ConfiguratorViewModel,
    form: ConfiguratorForm,
) {
    item {
        val protocols = ServiceRegistry.services(ServiceCategory.VPN, form.scope)
        val all = protocols.map { it.id }.toSet()
        GroupedSection(
            header = stringResource(R.string.wizard_vpn_header),
            note = stringResource(R.string.wizard_vpn_footer),
        ) {
            ToggleRow(
                title = stringResource(R.string.wizard_vpn_all),
                checked = all.isNotEmpty() && form.services.containsAll(all),
                onCheckedChange = { on ->
                    model.update { it.copy(services = if (on) it.services + all else it.services - all) }
                },
            )
            protocols.forEach { protocol ->
                CheckRow(
                    title = protocol.displayName,
                    checked = protocol.id in form.services,
                    onClick = { model.toggle(protocol.id) },
                    showDivider = protocol != protocols.last(),
                )
            }
        }
    }
    val chosen = protocolsIn(form)
    if (chosen.isNotEmpty()) {
        item {
            AdvancedSection {
                OwnAddressRow(
                    label = stringResource(R.string.wizard_vpn_domain),
                    value = form.serviceSettings.vpnHostname,
                    onValueChange = { name ->
                        model.update { it.copy(serviceSettings = it.serviceSettings.copy(vpnHostname = name)) }
                    },
                    placeholder = "vpn.${form.domain.ifBlank { "example.com" }}",
                )
                chosen.forEachIndexed { index, protocol ->
                    VPNProtocolAdvancedFields(
                        model, form, protocol,
                        showDivider = index != chosen.lastIndex,
                    )
                }
            }
        }
    }
}

/** The VPN protocols this form has chosen, in catalog order */
private fun protocolsIn(form: ConfiguratorForm): List<ServiceID> =
    ServiceRegistry.selection(ServiceCategory.VPN, form.services)

private fun androidx.compose.foundation.lazy.LazyListScope.domainStep(
    model: ConfiguratorViewModel,
    form: ConfiguratorForm,
    hasToken: Boolean,
) {
    item {
        GroupedSection(
            header = stringResource(R.string.wizard_domain_header),
            note = stringResource(R.string.wizard_domain_footer),
        ) {
            OwnAddressRow(
                label = stringResource(R.string.domain_label),
                value = form.domain,
                onValueChange = { value -> model.update { it.copy(domain = value) } },
            )
            form.additionalDomains.forEachIndexed { position, domain ->
                OwnAddressRow(
                    label = stringResource(R.string.wizard_domain_additional),
                    value = domain,
                    onValueChange = { value ->
                        model.update {
                            it.copy(additionalDomains = it.additionalDomains.toMutableList().apply { this[position] = value })
                        }
                    },
                )
            }
            if (form.additionalDomains.size < 9) {
                com.skaymer.gryonixnexus.app.ui.design.ActionRow(
                    text = stringResource(R.string.wizard_domain_add),
                    onClick = {
                        if (LicensePrompt.allow()) model.update { it.copy(additionalDomains = it.additionalDomains + "") }
                    },
                    showDivider = false,
                )
            }
        }
    }
    if (form.scope == DeploymentScope.CLOUDFLARE_TUNNEL) {
        item { CloudflareTunnelTokenSection(hasToken) }
    }
}

private fun addressTitle(form: ConfiguratorForm): Int = when {
    form.isLocalOnly -> R.string.wizard_local_address
    form.addressIsOnNetwork -> R.string.wizard_network_address
    form.topology == Topology.VPS_RELAY_WITH_HOME_BACKEND -> R.string.wizard_vps_address
    else -> R.string.wizard_server_address
}

private fun addressFooter(form: ConfiguratorForm): Int = when (form.scope) {
    DeploymentScope.LOCAL_ONLY -> R.string.wizard_server_footer_local
    DeploymentScope.CLOUDFLARE_TUNNEL -> R.string.wizard_server_footer_tunnel
    DeploymentScope.MESH_ONLY -> R.string.wizard_server_footer_mesh
    DeploymentScope.TAILSCALE_ONLY -> R.string.wizard_server_footer_tailscale
    DeploymentScope.DYNAMIC_DNS -> R.string.wizard_server_footer_dynamic
    DeploymentScope.PUBLIC_INTERNET ->
        if (form.topology == Topology.VPS_RELAY_WITH_HOME_BACKEND) R.string.home_network_address_note
        else R.string.wizard_server_footer_single
}

/** Whether a Cloudflare tunnel token is saved */
@Composable
private fun CloudflareTunnelTokenSection(hasToken: Boolean) {
    GroupedSection(header = "Cloudflare", note = stringResource(R.string.wizard_cloudflare_footer)) {
        GroupedRow(showDivider = false) {
            Text(
                stringResource(
                    if (hasToken) R.string.wizard_cloudflare_token_added else R.string.wizard_cloudflare_token_missing
                ),
                style = MaterialTheme.typography.bodyLarge,
                color = if (hasToken) Gryonix.colors.success else Gryonix.colors.warning,
            )
        }
    }
}

/** The Tailscale join key field */
@Composable
private fun TailscaleKeySection(
    keys: TailscaleKeyStore,
    hasKey: Boolean,
    onKey: (Boolean) -> Unit,
) {
    var draft by remember { mutableStateOf("") }
    val uri = LocalUriHandler.current
    GroupedSection(header = "Tailscale", note = stringResource(R.string.wizard_tailscale_footer)) {
        GroupedRow {
            Text(
                stringResource(R.string.wizard_tailscale_needs),
                style = MaterialTheme.typography.bodyLarge,
                color = Gryonix.colors.warning,
            )
        }
        if (hasKey) {
            GroupedRow {
                Text(
                    stringResource(R.string.wizard_tailscale_key_added),
                    style = MaterialTheme.typography.bodyLarge,
                    color = Gryonix.colors.success,
                )
            }
        }
        FieldRow(
            label = stringResource(
                if (hasKey) R.string.wizard_tailscale_key_replace else R.string.wizard_tailscale_key
            ),
            value = draft,
            onValueChange = { value ->
                draft = value
                if (value.isNotBlank()) {
                    keys.setKey(value)
                    onKey(true)
                }
            },
            placeholder = "tskey-auth-…",
            visualTransformation = PasswordVisualTransformation(),
        )
        ActionRow(
            text = stringResource(R.string.wizard_tailscale_console),
            onClick = { uri.openUri("https://login.tailscale.com/admin/settings/keys") },
            showDivider = false,
        )
    }
}

/** Where the machine is, and what it runs */
private fun androidx.compose.foundation.lazy.LazyListScope.addressStep(
    model: ConfiguratorViewModel,
    form: ConfiguratorForm,
    tailscaleKeys: TailscaleKeyStore,
    hasTailscaleKey: Boolean,
    onTailscaleKey: (Boolean) -> Unit,
) {
    val relay = form.topology == Topology.VPS_RELAY_WITH_HOME_BACKEND
    item {
        GroupedSection(
            header = stringResource(R.string.wizard_server_header),
            note = stringResource(addressFooter(form)),
        ) {
            OwnAddressRow(
                label = stringResource(addressTitle(form)),
                value = form.publicIP,
                onValueChange = { value ->
                    model.update {
                        if (it.isLocalOnly) it.copy(publicIP = value, domain = value)
                        else it.copy(publicIP = value)
                    }
                },
            )
            DistributionRow(
                label = stringResource(
                    if (relay) R.string.wizard_vps_distribution else R.string.wizard_server_distribution
                ),
                selected = form.distribution,
                showDivider = relay,
            ) { chosen -> model.update { it.copy(distribution = chosen) } }
            if (relay) {
                OwnAddressRow(
                    label = stringResource(R.string.home_network_address),
                    value = form.homeNetworkAddress,
                    onValueChange = { value -> model.update { it.copy(homeNetworkAddress = value) } },
                    placeholder = "192.168.1.50",
                )
                DistributionRow(
                    label = stringResource(R.string.wizard_home_distribution),
                    selected = form.homeDistribution,
                    showDivider = false,
                ) { chosen -> model.update { it.copy(homeDistribution = chosen) } }
            }
        }
    }
    if (form.scope == DeploymentScope.TAILSCALE_ONLY) {
        item { TailscaleKeySection(tailscaleKeys, hasTailscaleKey, onTailscaleKey) }
    }
    if (form.scope == DeploymentScope.PUBLIC_INTERNET || relay) {
        item {
            AdvancedSection(
                footer = stringResource(R.string.wizard_tunnel_addresses).takeIf { relay },
            ) {
                if (form.scope == DeploymentScope.PUBLIC_INTERNET) {
                    OwnAddressRow(
                        label = stringResource(R.string.wizard_reverse_dns),
                        value = form.reverseDNSHostname,
                        onValueChange = { value -> model.update { it.copy(reverseDNSHostname = value) } },
                        placeholder = "relay.${form.domain.ifBlank { "example.com" }}",
                        showDivider = relay,
                    )
                }
                if (relay) {
                    FieldRow(
                        label = stringResource(R.string.wizard_vps_address),
                        value = form.vpsVPNIP,
                        onValueChange = { value -> model.update { it.copy(vpsVPNIP = value) } },
                        placeholder = "10.8.0.1",
                    )
                    FieldRow(
                        label = stringResource(R.string.wizard_local_server_address),
                        value = form.homeVPNIP,
                        onValueChange = { value -> model.update { it.copy(homeVPNIP = value) } },
                        placeholder = "10.8.0.2",
                        showDivider = false,
                    )
                }
            }
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.adminStep(
    model: ConfiguratorViewModel,
    form: ConfiguratorForm,
) {
    item {
        GroupedSection(
            header = stringResource(R.string.wizard_admin_header),
            note = stringResource(R.string.wizard_admin_footer),
        ) {
            FieldRow(
                label = stringResource(R.string.wizard_admin_username),
                value = form.serviceSettings.adminUsername,
                onValueChange = { value ->
                    model.update { it.copy(serviceSettings = it.serviceSettings.copy(adminUsername = value)) }
                },
                showDivider = false,
                placeholder = "admin",
            )
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.dnsStep(
    form: ConfiguratorForm,
    zones: List<ConfigurationExport.DNSZone>,
    publish: DNSProviderPublishModel,
    dnsCredentials: DNSCredentials,
    artifactSaveError: String?,
    onSaveArtifact: (Artifact) -> Unit,
    acknowledged: Boolean,
    onAcknowledge: (Boolean) -> Unit,
) {
    item {
        GroupedSection(header = stringResource(R.string.wizard_dns_header)) {
            GroupedRow(showDivider = form.scope.maintainsItsOwnDNSRecords) {
                Text(
                    stringResource(R.string.wizard_dns_records_instruction),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.label,
                )
            }
            if (form.scope.maintainsItsOwnDNSRecords) {
                GroupedRow(showDivider = false) {
                    Text(
                        stringResource(R.string.wizard_dns_dynamic_hint),
                        style = MaterialTheme.typography.bodySmall,
                        color = Gryonix.colors.secondaryLabel,
                    )
                }
            }
        }
    }

    if (zones.isEmpty()) {
        item {
            Text(
                stringResource(R.string.wizard_dns_fill_in_first),
                style = MaterialTheme.typography.bodyMedium,
                color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
            )
        }
    } else {
        zones.forEachIndexed { index, zone ->
            item {
                DNSZoneRecordsCard(
                    zone = zone,
                    showHeading = zones.size > 1,
                    footer = if (index == zones.lastIndex) {
                        artifactSaveError ?: stringResource(R.string.wizard_dns_import_hint)
                    } else {
                        null
                    },
                    onSave = onSaveArtifact,
                )
            }
        }
        item {
            DNSProviderPublishCard(zones, publish) {
                onAcknowledge(true)
            }
        }
    }

    item {
        GroupedSection(footer = stringResource(R.string.wizard_dns_footer)) {
            ToggleRow(
                title = stringResource(R.string.wizard_dns_ack),
                checked = acknowledged,
                onCheckedChange = onAcknowledge,
                showDivider = false,
            )
        }
    }
}

@Composable
private fun DNSZoneRecordsCard(
    zone: ConfigurationExport.DNSZone,
    showHeading: Boolean,
    footer: String?,
    onSave: (Artifact) -> Unit,
) {
    val clipboard = LocalClipboardManager.current
    GroupedSection(header = if (showHeading) zone.domain else null, footer = footer) {
        GroupedRow {
            SelectionContainer {
                Text(
                    zone.copyText,
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = Gryonix.colors.label,
                )
            }
        }
        ActionRow(
            text = stringResource(R.string.service_logs_copy),
            onClick = { if (LicensePrompt.allow()) clipboard.setText(AnnotatedString(zone.copyText)) },
            showDivider = zone.zoneFile != null || zone.csvFile != null,
        )
        zone.zoneFile?.let { file ->
            ActionRow(
                text = stringResource(R.string.dkim_export_zone),
                onClick = { onSave(file) },
                showDivider = zone.csvFile != null,
            )
        }
        zone.csvFile?.let { file ->
            ActionRow(
                text = stringResource(R.string.dkim_export_csv),
                onClick = { onSave(file) },
                showDivider = false,
            )
        }
    }
}

@Composable
internal fun DNSProviderPublishCard(
    zones: List<ConfigurationExport.DNSZone>,
    model: DNSProviderPublishModel,
    onPublishSucceeded: () -> Unit,
) {
    val state by model.state.collectAsState()
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) { model.loadStoredToken() }

    GroupedSection(
        header = stringResource(R.string.wizard_publish_header),
        note = stringResource(state.providerKind.setupHintRes),
    ) {
        if (DNSProviderKind.entries.size > 1) {
            ProviderPickerRow(
                selected = state.providerKind,
                onSelect = { model.selectProvider(it) },
            )
        }
        if (state.saved.size > 1) {
            TokenPickerRow(
                saved = state.saved,
                selectedID = state.credentialID,
                onSelect = { model.loadToken(it) },
            )
        }
        FieldRow(
            label = stringResource(state.providerKind.tokenLabelRes),
            value = state.token,
            onValueChange = { model.setToken(it) },
            visualTransformation = PasswordVisualTransformation(),
        )
        ActionRow(
            text = stringResource(state.providerKind.publishButtonRes),
            onClick = {
                scope.launch {
                    model.publish(zones)
                    if (!model.state.value.failed) onPublishSucceeded()
                }
            },
            enabled = DNSProviderPublishModel.canPublish(state.token, state.isWorking, zones.isNotEmpty()),
            leading = if (state.isWorking) {
                {
                    CircularProgressIndicator(
                        Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = Gryonix.colors.tertiaryLabel,
                    )
                }
            } else {
                null
            },
            showDivider = state.lines.isNotEmpty(),
        )
        state.lines.forEachIndexed { index, line ->
            GroupedRow(showDivider = index != state.lines.lastIndex) {
                Text(
                    line,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (state.failed) Gryonix.colors.danger else Gryonix.colors.secondaryLabel,
                )
            }
        }
    }
}

@Composable
private fun TokenPickerRow(
    saved: List<DNSCredential>,
    selectedID: String?,
    onSelect: (String) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    val selectedName = saved.firstOrNull { it.id == selectedID }?.name.orEmpty()
    Box {
        GroupedRow(
            onClick = { open = true },
            trailing = {
                Text(
                    selectedName,
                    style = MaterialTheme.typography.bodyLarge,
                    color = Gryonix.colors.secondaryLabel,
                )
                DisclosureChevron()
            },
        ) {
            Text(
                stringResource(R.string.wizard_publish_account),
                style = MaterialTheme.typography.bodyLarge,
                color = Gryonix.colors.label,
            )
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            saved.forEach { credential ->
                DropdownMenuItem(
                    text = { Text(credential.name) },
                    trailingIcon = {
                        if (credential.id == selectedID) {
                            Icon(Icons.Filled.Check, contentDescription = null)
                        }
                    },
                    onClick = { onSelect(credential.id); open = false },
                )
            }
        }
    }
}

@Composable
private fun ProviderPickerRow(
    selected: DNSProviderKind,
    onSelect: (DNSProviderKind) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        GroupedRow(
            onClick = { open = true },
            trailing = {
                Text(
                    selected.displayName,
                    style = MaterialTheme.typography.bodyLarge,
                    color = Gryonix.colors.secondaryLabel,
                )
                DisclosureChevron()
            },
        ) {
            Text(
                stringResource(R.string.wizard_publish_provider),
                style = MaterialTheme.typography.bodyLarge,
                color = Gryonix.colors.label,
            )
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DNSProviderKind.entries.forEach { kind ->
                DropdownMenuItem(
                    text = { Text(kind.displayName) },
                    trailingIcon = {
                        if (kind == selected) Icon(Icons.Filled.Check, contentDescription = null)
                    },
                    onClick = { onSelect(kind); open = false },
                )
            }
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.reviewStep(
    scenario: ScenarioOption,
    form: ConfiguratorForm,
) {
    item {
        GroupedSection(
            header = stringResource(R.string.wizard_review_header),
            note = stringResource(R.string.wizard_review_footer),
        ) {
            com.skaymer.gryonixnexus.app.ui.design.ValueRow(
                title = stringResource(R.string.wizard_review_scenario),
                value = stringResource(scenario.title),
                onClick = null,
            )
            if (!form.isLocalOnly) {
                com.skaymer.gryonixnexus.app.ui.design.ValueRow(
                    title = stringResource(R.string.domain_label),
                    value = form.domain.ifBlank { "—" },
                    onClick = null,
                )
            }
            com.skaymer.gryonixnexus.app.ui.design.ValueRow(
                title = stringResource(addressTitle(form)),
                value = form.publicIP.ifBlank { "—" },
                onClick = null,
            )
            if (scenario.topology == Topology.VPS_RELAY_WITH_HOME_BACKEND) {
                com.skaymer.gryonixnexus.app.ui.design.ValueRow(
                    title = stringResource(R.string.home_network_address),
                    value = form.homeNetworkAddress.ifBlank { "—" },
                    onClick = null,
                )
            }
            com.skaymer.gryonixnexus.app.ui.design.ValueRow(
                title = stringResource(R.string.wizard_review_services),
                value = ServiceRegistry.services(form.services)
                    .joinToString(", ") { it.displayName }
                    .ifBlank { "—" },
                onClick = null,
                showDivider = false,
            )
        }
    }
}

@Composable
private fun ServicePickerSheet(
    category: ServiceCategory,
    form: ConfiguratorForm,
    onSet: (Set<ServiceID>) -> Unit,
    onClose: () -> Unit,
) {
    val offered = ServiceRegistry.services(category, form.scope, form.services)
    IOSSheet(title = categoryTitle(category), onClose = onClose, closeLabel = stringResource(R.string.close)) {
        GroupedSection {
            offered.forEach { service ->
                val note = CategorySelection.note(service.id)
                CheckRow(
                    title = service.displayName,
                    subtitle = note?.let { stringResource(it.resource) },
                    checked = service.id in form.services,
                    onClick = { onSet(setOf(service.id)) },
                    showDivider = service != offered.last(),
                )
            }
        }
    }
}

private val CategorySelection.NoteKey.resource: Int
    get() = when (this) {
        CategorySelection.NoteKey.GITLAB -> R.string.wizard_note_gitlab
        CategorySelection.NoteKey.ADGUARD -> R.string.wizard_note_adguard
        CategorySelection.NoteKey.PIHOLE -> R.string.wizard_note_pihole
        CategorySelection.NoteKey.SHAIRPORT -> R.string.wizard_note_shairport
        CategorySelection.NoteKey.UXPLAY -> R.string.wizard_note_uxplay
        CategorySelection.NoteKey.ODIO -> R.string.wizard_note_odio
        CategorySelection.NoteKey.SNAPSERVER -> R.string.wizard_note_snapserver
        CategorySelection.NoteKey.SNAPCLIENT -> R.string.wizard_note_snapclient
        CategorySelection.NoteKey.DLNA -> R.string.wizard_note_dlna
        CategorySelection.NoteKey.BLUETOOTH -> R.string.wizard_note_bluetooth
        CategorySelection.NoteKey.SPOTIFY -> R.string.wizard_note_spotify
        CategorySelection.NoteKey.MYMPD -> R.string.wizard_note_mympd
    }

/** A password the model already holds */
@Composable
private fun WizardPasswordField(
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

/** Where the models this deployment talks to actually run */
@Composable
private fun ColumnScope.ModelBackendRow(value: ModelBackend, onChoose: (ModelBackend) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val label = { backend: ModelBackend ->
        when (backend) {
            ModelBackend.HERE -> R.string.wizard_model_backend_here
            ModelBackend.HOME -> R.string.wizard_model_backend_home
            ModelBackend.EXTERNAL -> R.string.wizard_model_backend_external
        }
    }
    Box {
        ValueRow(
            title = stringResource(R.string.wizard_model_backend_title),
            value = stringResource(label(value)),
            onClick = { open = true },
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            for (backend in ModelBackend.entries) {
                DropdownMenuItem(
                    text = { Text(stringResource(label(backend))) },
                    onClick = { onChoose(backend); open = false },
                )
            }
        }
    }
}
