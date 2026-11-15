package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.aiassistant.RamVerdict
import com.skaymer.gryonixnexus.aiassistant.OllamaRam
import androidx.compose.runtime.LaunchedEffect
import com.skaymer.gryonixnexus.catalog.storage.StorageArray
import com.skaymer.gryonixnexus.catalog.ServiceDataPlacement
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.size
import androidx.compose.ui.text.style.TextAlign
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.servers.MetricsFormat
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.R
import androidx.compose.material3.Icon
import com.skaymer.gryonixnexus.app.ui.design.SymbolIcons
import com.skaymer.gryonixnexus.app.servers.AddServiceViewModel
import com.skaymer.gryonixnexus.agentcontrol.InstallFinding
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** A warning when the services need more memory */
@Composable
private fun memoryWarning(deployment: Deployment, selection: Set<ServiceID>, memoryBytes: Long?): String? {
    val total = memoryBytes?.takeIf { it > 0 && selection.isNotEmpty() } ?: return null
    val need = ServiceRegistry.requirements(deployment.services + selection).memoryMB.toLong() * 1_048_576
    if (need <= total) return null
    return stringResource(R.string.add_service_memory_warning, MetricsFormat.bytes(need), MetricsFormat.bytes(total))
}

/** Picks what to add to a server that already runs */
@Composable
fun AddServiceDialog(
    deployment: Deployment,
    /** Whether this device can mint a connector credential */
    canIssueTunnelToken: Boolean,
    onCancel: () -> Unit,
    /** The services, and the array mount their data goes to */
    onInstall: (List<ServiceID>, String?) -> Unit,
    /** Arrays on the server that can hold service data */
    loadArrays: suspend () -> List<StorageArray> = { emptyList() },
    /** The server's memory, when its metrics are in */
    memoryBytes: Long? = null,
    /** Asks the machine what it lacks for the services */
    checkMachine: suspend (List<ServiceID>) -> List<InstallFinding> = { emptyList() },
) {
    var selection by remember(deployment.id) { mutableStateOf(emptySet<ServiceID>()) }
    var findings by remember(deployment.id) { mutableStateOf(emptyList<InstallFinding>()) }
    LaunchedEffect(selection) { findings = if (selection.isEmpty()) emptyList() else checkMachine(selection.toList()) }
    var arrays by remember(deployment.id) { mutableStateOf(emptyList<StorageArray>()) }
    var askingWhere by remember { mutableStateOf(false) }
    LaunchedEffect(deployment.id) { arrays = loadArrays() }
    val chosen = AddServiceViewModel.chosen(selection).map { it.id }
    if (askingWhere) {
        DataPlacementAlert(arrays, onDismiss = { askingWhere = false }) { mount ->
            askingWhere = false
            onInstall(chosen, mount)
        }
    }
    val shelves = remember(deployment.services, deployment.scope, canIssueTunnelToken, selection) {
        AddServiceViewModel.available(
            installed = deployment.services,
            localOnly = deployment.scope.usesInternalTLS,
            canIssueTunnelToken = canIssueTunnelToken,
            selected = selection,
        )
    }

    IOSSheet(
        title = stringResource(R.string.add_service_title),
        onClose = onCancel,
        closeLabel = stringResource(R.string.containers_cancel),
        action = SheetAction(
            title = stringResource(R.string.add_service_install),
            enabled = selection.isNotEmpty() && findings.none { it.isBlocking && it.service in selection },
            onSelect = {
                if (arrays.isNotEmpty() && chosen.any(ServiceDataPlacement::keepsData)) {
                    askingWhere = true
                } else {
                    onInstall(chosen, null)
                }
            },
        ),
    ) {
        memoryWarning(deployment, selection, memoryBytes)?.let { warning ->
            GroupedSection {
                GroupedRow(showDivider = false) {
                    Text(warning, style = MaterialTheme.typography.bodyMedium, color = Gryonix.colors.warning)
                }
            }
        }
        HostCompatibilitySection(findings)
        if (ServiceID.OLLAMA in selection) OllamaAdvice(memoryBytes)
        if (!deployment.usesAgent) {
            GroupedSection(footer = stringResource(R.string.add_service_agent_sudo)) {
                ValueRow(
                    title = stringResource(R.string.add_service_agent_first),
                    value = null,
                    onClick = null,
                    showDivider = false,
                )
            }
        }
        if (shelves.isEmpty()) {
            Text(
                stringResource(R.string.add_service_nothing_left),
                style = MaterialTheme.typography.bodyMedium,
                color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
            )
        }
        shelves.forEach { (category, services) ->
            GroupedSection(
                header = categoryTitle(category),
                footer = if (category == shelves.last().first) {
                    stringResource(R.string.add_service_note)
                } else {
                    null
                },
            ) {
                services.forEach { service ->
                    CheckRow(
                        title = service.displayName,
                        checked = service.id in selection,
                        onClick = {
                            selection = AddServiceViewModel.toggle(
                                selection, service, deployment.services,
                            )
                        },
                        showDivider = service != services.last(),
                        leading = {
                            Icon(SymbolIcons.of(service.systemImage), null, tint = Gryonix.colors.accent,
                                modifier = Modifier.size(22.dp))
                        },
                    )
                }
            }
        }
    }
}
/** The installs while they run */
@Composable
fun AddServiceRunDialog(adding: AddServiceViewModel) {
    val state by adding.state.collectAsState()
    val run = state.run ?: return
    val name = { id: ServiceID -> ServiceRegistry.service(id)?.displayName ?: id.rawValue }

    IOSAlert(
        title = stringResource(R.string.add_service_running),
        message = if (!run.isFinished) stringResource(R.string.add_service_detached) else null,
        onDismiss = { if (run.isFinished) adding.clear() },
        actions = listOf(
            AlertAction(
                stringResource(R.string.containers_done),
                preferred = true,
                enabled = run.isFinished,
                onSelect = { adding.clear() },
            ),
        ),
    ) {
        Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            run.current?.let {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(
                        Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = Gryonix.colors.tertiaryLabel,
                    )
                    Text(
                        stringResource(R.string.add_service_installing, name(it)),
                        style = MaterialTheme.typography.bodyMedium,
                        color = Gryonix.colors.secondaryLabel,
                    )
                }
            }
            if (run.installed.isNotEmpty()) {
                Text(
                    stringResource(
                        R.string.add_service_installed,
                        run.installed.joinToString(", ") { name(it) },
                    ),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.label,
                    textAlign = TextAlign.Center,
                )
            }
            run.errorMessage?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.danger,
                    textAlign = TextAlign.Center,
                )
            }
            if (run.log.isNotEmpty()) {
                Text(
                    run.log,
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = Gryonix.colors.secondaryLabel,
                    modifier = Modifier
                        .heightIn(max = 240.dp)
                        .verticalScroll(rememberScrollState()),
                )
            }
        }
    }
}

/** Asks whether the new services' data goes on the array */
@Composable
private fun DataPlacementAlert(arrays: List<StorageArray>, onDismiss: () -> Unit, onPick: (String?) -> Unit) {
    IOSAlert(
        title = stringResource(R.string.data_placement_title),
        message = stringResource(R.string.data_placement_message),
        onDismiss = onDismiss,
        actions = arrays.mapNotNull { array ->
            array.mountpoint?.let { mount ->
                AlertAction(stringResource(R.string.data_placement_array, mount), preferred = true) { onPick(mount) }
            }
        } + listOf(
            AlertAction(stringResource(R.string.data_placement_main_disk)) { onPick(null) },
            AlertAction(stringResource(R.string.containers_cancel)) { onDismiss() },
        ),
    )
}

@Composable
private fun OllamaAdvice(memoryBytes: Long?) {
    var model by remember { mutableStateOf(OllamaRam.suggestedModels.first()) }
    GroupedSection(
        header = stringResource(R.string.ai_model_plan),
        footer = stringResource(R.string.ai_ram_table),
    ) {
        OllamaRam.suggestedModels.forEachIndexed { index, name ->
            CheckRow(name, model == name, onClick = { model = name }, showDivider = index != OllamaRam.suggestedModels.lastIndex)
        }
        val verdict = OllamaRam.verdict(model, memoryBytes)
        if (verdict is RamVerdict.TooLow) {
            GroupedRow(showDivider = false) {
                Text(stringResource(R.string.ai_ram_warn, verdict.needGb.toString(), verdict.haveGb.toString()),
                    style = MaterialTheme.typography.bodyMedium, color = Gryonix.colors.warning)
            }
        }
    }
}
