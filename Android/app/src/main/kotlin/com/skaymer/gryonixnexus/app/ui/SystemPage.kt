package com.skaymer.gryonixnexus.app.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Memory
import androidx.compose.material.icons.outlined.SwapHoriz
import com.skaymer.gryonixnexus.app.shell.AppModule
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.servers.HostSystemUpdate
import com.skaymer.gryonixnexus.app.servers.SystemUpdateViewModel
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.ApplyPendingBar
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

/** One place for a machine's system-level settings */
@Composable
fun SystemDialog(
    deployment: Deployment,
    updates: SystemUpdateViewModel,
    onUpdates: () -> Unit,
    onSwap: () -> Unit,
    onClose: () -> Unit,
) {
    val application = LocalContext.current.applicationContext as GryonixApplication
    val actions = application.hostActions
    val settings = application.systemSettings
    val hostSettings by settings.hosts.collectAsState()
    val hostUpdates by updates.hosts.collectAsState()
    LaunchedEffect(deployment.id) {
        settings.load(deployment)
        updates.load(deployment)
    }
    var rebooting by remember { mutableStateOf<SSHHostID?>(null) }
    var forwarding by remember { mutableStateOf(false) }
    val serverSets by application.modules.servers.collectAsState()
    val kept by application.modules.keptOnServers.collectAsState()
    val portForwarding = remember(serverSets, kept) { application.modules.isOn(AppModule.PORT_FORWARDING, deployment.id) }
    IOSSheet(
        title = stringResource(R.string.system_page_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.close),
    ) {
        GroupedSection {
            NavRow(Icons.Outlined.Download, stringResource(R.string.general_system), onUpdates)
            NavRow(Icons.Outlined.Memory, stringResource(R.string.storage_swap), onSwap, showDivider = false)
        }
        if (portForwarding) {
            GroupedSection {
                NavRow(Icons.Outlined.SwapHoriz, stringResource(R.string.port_forwarding_title), { forwarding = true },
                    showDivider = false)
            }
        }
        deployment.nodes.forEach { node ->
            val label = if (deployment.nodes.size > 1) node.name.ifEmpty { node.endpoint.host } else null
            hostSettings[node.sshHost]?.let { state ->
                SystemSettingsSection(
                    state = state,
                    header = label,
                    onTimeZone = { settings.setTimeZone(deployment, node.sshHost, it) },
                    onHostName = { settings.setHostName(deployment, node.sshHost, it) },
                    onTimeSync = { settings.setTimeSync(deployment, node.sshHost, it) },
                )
            }
            RebootScheduleSection(hostUpdates[node.sshHost]) { updates.setRebootSchedule(deployment, node.sshHost, it) }
        }
        GroupedSection {
            deployment.nodes.forEachIndexed { index, node ->
                ActionRow(
                    text = rebootTitle(node),
                    danger = true,
                    onClick = { rebooting = node.sshHost },
                    showDivider = index != deployment.nodes.lastIndex,
                )
            }
        }
    }
    if (forwarding) PortForwardsSheet(deployment) { forwarding = false }
    rebooting?.let { host ->
        ConfirmAlert(
            title = stringResource(R.string.actions_reboot_title),
            message = stringResource(R.string.actions_reboot_message),
            confirm = stringResource(R.string.actions_reboot_confirm),
            destructive = true,
            onConfirm = { rebooting = null; actions.reboot(deployment, host) },
            onCancel = { rebooting = null },
        )
    }
}

/** The swap of each machine */
@Composable
fun SystemSwapDialog(deployment: Deployment, model: SystemUpdateViewModel, onClose: () -> Unit) {
    val hosts by model.hosts.collectAsState()
    val drafts = remember { mutableStateMapOf<SSHHostID, Int>() }
    LaunchedEffect(deployment.id) { model.load(deployment) }
    val waiting = drafts.filter { (host, size) -> size != savedSwapGB(hosts[host]?.status) }
    IOSSheet(
        title = stringResource(R.string.storage_swap),
        onClose = onClose,
        closeLabel = stringResource(R.string.close),
        bottomBar = {
            ApplyPendingBar(
                visible = waiting.isNotEmpty(),
                apply = stringResource(R.string.updates_save),
                cancel = stringResource(R.string.pending_changes_cancel),
                onApply = {
                    waiting.forEach { (host, size) -> model.setSwap(deployment, host, size.takeIf { it > 0 }) }
                    drafts.clear()
                },
                onRevert = { drafts.clear() },
            )
        },
    ) {
        deployment.nodes.forEach { node ->
            val state = hosts[node.sshHost] ?: HostSystemUpdate(busy = true)
            GroupedSection(
                header = if (deployment.nodes.size > 1) node.name.ifEmpty { node.endpoint.host } else null,
                footer = state.errorMessage,
            ) {
                SwapLine(
                    state.status,
                    enabled = state.status != null && !state.busy,
                    draft = drafts[node.sshHost],
                    onDraft = { drafts[node.sshHost] = it },
                )
            }
        }
    }
}
