package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Security
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.PowerOff
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Handyman
import androidx.compose.material.icons.filled.Sync
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.SectionHeader
import com.skaymer.gryonixnexus.app.ui.design.TileAction
import com.skaymer.gryonixnexus.app.ui.design.TileActionGroup
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSwitch
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.RefreshButton
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.HostAction
import com.skaymer.gryonixnexus.app.servers.HostActionsViewModel
import com.skaymer.gryonixnexus.app.servers.LockdownRead
import com.skaymer.gryonixnexus.app.servers.WakeOnLANViewModel
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

@Composable
fun HostActionsCard(
    deployment: Deployment,
    actions: HostActionsViewModel,
    /** Waking this machine, where that is offered — see `WakeOnLANViewModel` */
    wake: WakeOnLANViewModel,
    onRepair: (() -> Unit)? = null,
    onReinstall: (() -> Unit)? = null,
) {
    val state by actions.state.collectAsState()
    val machines = remember(deployment) { HostActionsViewModel.order(deployment) }
    val pages = remember(deployment) { HostActionsViewModel.lockdownPages(deployment) }
    val hasGuard = remember(deployment) { HostActionsViewModel.hasAdminLockdown(deployment) }
    var confirmingSSH by remember(deployment.id) { mutableStateOf(false) }
    var rebooting by remember(deployment.id) { mutableStateOf<SSHHostID?>(null) }
    var expanded by remember(deployment.id) { mutableStateOf(false) }
    val waking by wake.state.collectAsState()
    var poweringOff by remember(deployment.id) { mutableStateOf(false) }

    LaunchedEffect(deployment.id, hasGuard) {
        if (hasGuard) actions.refreshLockdownIfStale(deployment)
    }
    LaunchedEffect(deployment.id) { wake.refreshQuietly(deployment) }

    GroupedSection(header = stringResource(R.string.actions_title)) {
        TileActionGroup(
            buildList {
                add(
                    TileAction(
                        title = stringResource(R.string.actions_restart_ssh),
                        icon = Icons.Filled.Refresh,
                        onClick = { confirmingSSH = true },
                        enabled = state.running == null,
                    )
                )
                if (machines.size == 1) {
                    add(
                        TileAction(
                            title = stringResource(R.string.actions_reboot),
                            icon = Icons.Filled.PowerSettingsNew,
                            onClick = { rebooting = machines.first().sshHost },
                            enabled = state.running == null,
                            danger = true,
                        )
                    )
                } else {
                    machines.forEach { node ->
                        add(
                            TileAction(
                                title = rebootTitle(node),
                                icon = Icons.Filled.PowerSettingsNew,
                                onClick = { rebooting = node.sshHost },
                                enabled = state.running == null,
                                danger = true,
                            )
                        )
                    }
                }
                onRepair?.let {
                    add(TileAction(stringResource(R.string.repair_server), Icons.Filled.Handyman, it, state.running == null))
                }
                onReinstall?.let {
                    add(TileAction(stringResource(R.string.actions_reinstall_services), Icons.Filled.Sync, it, state.running == null))
                }
                if (WakeOnLANViewModel.isOffered(deployment)) {
                    add(
                        TileAction(
                            title = stringResource(R.string.power_off_title),
                            icon = Icons.Filled.PowerOff,
                            onClick = { poweringOff = true },
                            enabled = state.running == null,
                            danger = true,
                        )
                    )
                    add(
                        TileAction(
                            title = stringResource(R.string.wake_title),
                            icon = Icons.Filled.Bolt,
                            onClick = { wake.wake(deployment) },
                            enabled = state.running == null && !waking.isWorking,
                        )
                    )
                }
            },
            Modifier.padding(16.dp),
        )
    }

    if (confirmingSSH) {
        ConfirmDialog(
            title = stringResource(R.string.actions_restart_ssh_title),
            message = stringResource(
                R.string.actions_restart_ssh_message,
                machines.joinToString(", ") { machineName(it) }
            ),
            confirm = stringResource(R.string.actions_restart_ssh_confirm),
            onConfirm = {
                confirmingSSH = false
                actions.restartSSHD(deployment)
            },
            onCancel = { confirmingSSH = false }
        )
    }
    rebooting?.let { host ->
        ConfirmDialog(
            title = stringResource(R.string.actions_reboot_title),
            message = stringResource(R.string.actions_reboot_message),
            confirm = stringResource(R.string.actions_reboot_confirm),
            onConfirm = {
                rebooting = null
                actions.reboot(deployment, host)
            },
            onCancel = { rebooting = null }
        )
    }
    if (poweringOff) {
        ConfirmDialog(
            title = stringResource(R.string.power_off_question),
            message = stringResource(R.string.power_off_message),
            confirm = stringResource(R.string.power_off_title),
            onConfirm = {
                poweringOff = false
                actions.powerOff(deployment)
            },
            onCancel = { poweringOff = false }
        )
    }
    waking.note?.let { note -> WakeNoteAlert(note) { wake.clearNote() } }
    state.outcome?.let { outcome ->
        val machine = machines.firstOrNull { it.sshHost == outcome.host }
        IOSAlert(
            title = stringResource(
                if (outcome.isError) R.string.actions_error else R.string.actions_done
            ),
            message = when {
                outcome.action == HostAction.RESTART_SSHD && outcome.isError ->
                    stringResource(
                        R.string.actions_restart_ssh_failed,
                        machine?.let { machineName(it) }.orEmpty(),
                        outcome.errorMessage.orEmpty()
                    )
                outcome.action == HostAction.RESTART_SSHD ->
                    stringResource(R.string.actions_restart_ssh_done)
                outcome.action == HostAction.POWER_OFF && outcome.isError ->
                    stringResource(R.string.power_off_failed, outcome.errorMessage.orEmpty())
                outcome.action == HostAction.POWER_OFF -> stringResource(R.string.power_off_sent)
                outcome.isError -> stringResource(
                    R.string.actions_reboot_failed, outcome.errorMessage.orEmpty()
                )
                else -> stringResource(R.string.actions_reboot_sent)
            },
            onDismiss = { actions.clearOutcome() },
            actions = listOf(
                AlertAction(
                    stringResource(R.string.actions_ok),
                    preferred = true,
                    onSelect = { actions.clearOutcome() },
                ),
            ),
        )
    }
}

@Composable
private fun WakeNoteAlert(note: WakeOnLANViewModel.Note, onDismiss: () -> Unit) {
    val failed = note !is WakeOnLANViewModel.Note.Sent && note !is WakeOnLANViewModel.Note.SentFromPhone
    IOSAlert(
        title = stringResource(if (failed) R.string.actions_error else R.string.actions_done),
        message = when (note) {
            is WakeOnLANViewModel.Note.Sent -> stringResource(R.string.wake_sent_from, note.from)
            is WakeOnLANViewModel.Note.SentFromPhone -> stringResource(R.string.wake_sent_from_phone, note.broadcast)
            WakeOnLANViewModel.Note.NoMACYet -> stringResource(R.string.wake_no_mac_yet)
            WakeOnLANViewModel.Note.CardCannotWake -> stringResource(R.string.wake_card_cannot_wake)
            WakeOnLANViewModel.Note.ThePhoneCouldNotSend -> stringResource(R.string.wake_phone_failed)
        },
        onDismiss = onDismiss,
        actions = listOf(AlertAction(stringResource(R.string.actions_ok), preferred = true, onSelect = onDismiss)),
    )
}

private fun machineName(node: DeploymentNode): String =
    node.name.ifEmpty { node.endpoint.host }

/** What the reboot tile for one of several machines says */
@Composable
fun rebootTitle(node: DeploymentNode): String = when {
    node.name.isNotEmpty() -> stringResource(R.string.actions_reboot_machine, node.name)
    node.legacySlot == DeploymentNode.LegacySlot.VPS -> stringResource(R.string.actions_reboot_vps)
    node.legacySlot == DeploymentNode.LegacySlot.HOME -> stringResource(R.string.actions_reboot_home)
    else -> stringResource(R.string.actions_reboot_machine, node.endpoint.host)
}

@Composable
private fun ConfirmDialog(
    title: String,
    message: String,
    confirm: String,
    onConfirm: () -> Unit,
    onCancel: () -> Unit,
) {
    ConfirmAlert(
        title = title,
        message = message,
        confirm = confirm,
        destructive = true,
        cancel = stringResource(R.string.actions_cancel),
        onConfirm = onConfirm,
        onCancel = onCancel,
    )
}

@Composable
fun LockdownPage(
    deployment: Deployment,
    actions: HostActionsViewModel,
    openAPI: com.skaymer.gryonixnexus.app.servers.OpenAPIViewModel? = null,
) {
    val state by actions.state.collectAsState()
    val pages = remember(deployment) { HostActionsViewModel.lockdownPages(deployment) }
    val hasGuard = remember(deployment) { HostActionsViewModel.hasAdminLockdown(deployment) }
    val apiServices = remember(deployment) {
        if (openAPI != null && offersOpenAPI(deployment)) com.skaymer.gryonixnexus.app.servers.OpenAPIViewModel.services(deployment) else emptyList()
    }
    var apiService by remember(deployment.id) { mutableStateOf<com.skaymer.gryonixnexus.catalog.ServiceID?>(null) }
    LaunchedEffect(deployment.id) { if (apiServices.isNotEmpty()) openAPI?.refresh(deployment) }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(GroupedContentPadding),
        verticalArrangement = GroupedSpacing,
    ) {
        if (hasGuard) {
            val current = state.lockdown.value
            GroupedSection(
                header = stringResource(R.string.actions_lockdown),
                note = stringResource(R.string.actions_lockdown_explains),
                onRefresh = { actions.refreshLockdown(deployment) },
                refreshDescription = stringResource(R.string.refresh_lockdown_again),
                refreshing = state.lockdown is LockdownRead.Loading,
                footer = (state.lockdown as? LockdownRead.Failed)?.message,
            ) {
                GroupedRow(
                    showDivider = false,
                    leading = {
                        Icon(Icons.Outlined.Security, contentDescription = null, modifier = Modifier.size(22.dp))
                    },
                    trailing = {
                        IOSSwitch(
                            checked = current?.isActive == true,
                            enabled = current != null,
                            onCheckedChange = { actions.setLockdown(deployment, it) },
                            onColor = Gryonix.colors.success,
                        )
                    },
                ) { RowLabel(stringResource(R.string.actions_lockdown_short)) }
            }
            if (apiServices.isNotEmpty() && openAPI != null) AllOpenAPISection(deployment, apiServices, openAPI)
            if (pages.isNotEmpty()) {
                GroupedSection(header = stringResource(R.string.lockdown_panels)) {
                    pages.forEach { page ->
                        GroupedRow(
                            showDivider = page != pages.last(),
                            trailing = {
                                IOSSwitch(
                                    checked = current?.guards(page.host) == true,
                                    enabled = current != null,
                                    onCheckedChange = { actions.setLockdown(deployment, page.host, it) },
                                    onColor = Gryonix.colors.success,
                                )
                                if (page.id in apiServices) {
                                    IconButton(onClick = { apiService = page.id }) {
                                        Icon(
                                            Icons.AutoMirrored.Filled.KeyboardArrowRight,
                                            contentDescription = stringResource(R.string.api_access_row),
                                            tint = Gryonix.colors.tertiaryLabel,
                                        )
                                    }
                                }
                            },
                        ) { RowLabel(page.name, page.host) }
                    }
                }
            }
        } else if (pages.isNotEmpty()) {
            Text(
                stringResource(R.string.actions_lockdown_needs_vpn),
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
            )
        }
    }
    val opened = apiService
    if (opened != null && openAPI != null) {
        val page = pages.firstOrNull { it.id == opened }
        ServiceOpenAPISheet(
            deployment, opened, page?.name ?: opened.rawValue, openAPI,
            siteGuarded = page?.let { state.lockdown.value?.guards(it.host) },
            onClose = { apiService = null },
        )
    }
}
