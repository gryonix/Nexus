package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.PowerOff
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Refresh
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
        if (hasGuard) actions.refreshLockdown(deployment)
    }
    LaunchedEffect(deployment.id) { wake.refreshQuietly(deployment) }

    Column(verticalArrangement = GroupedSpacing) {
        SectionHeader(stringResource(R.string.actions_title))
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
                                title = stringResource(
                                    R.string.actions_reboot_machine, machineName(node)
                                ),
                                icon = Icons.Filled.PowerSettingsNew,
                                onClick = { rebooting = node.sshHost },
                                enabled = state.running == null,
                                danger = true,
                            )
                        )
                    }
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
            Modifier.padding(horizontal = Metrics.listInset),
        )

        if (hasGuard) {
            GroupedSection(
                footer = (state.lockdown as? LockdownRead.Failed)?.message
                    ?: stringResource(R.string.actions_lockdown_explains),
            ) {
                GroupedRow(
                    showDivider = pages.isNotEmpty(),
                    trailing = {
                        RefreshButton(
                            contentDescription = stringResource(R.string.refresh_lockdown_again),
                            onClick = { actions.refreshLockdown(deployment) },
                            busy = state.lockdown is LockdownRead.Loading,
                        )
                        when (val read = state.lockdown) {
                            is LockdownRead.Idle, is LockdownRead.Loading -> Unit
                            is LockdownRead.Loaded -> IOSSwitch(
                                checked = read.state.isActive,
                                onCheckedChange = { actions.setLockdown(deployment, it) },
                            )
                            is LockdownRead.Failed -> Text(
                                stringResource(R.string.security_could_not_read),
                                style = MaterialTheme.typography.bodySmall,
                                color = Gryonix.colors.warning,
                            )
                        }
                    },
                ) {
                    RowLabel(
                        stringResource(R.string.actions_lockdown),
                        stringResource(R.string.actions_lockdown_caption),
                    )
                }
                if (pages.isNotEmpty()) {
                    ActionRow(
                        text = stringResource(R.string.actions_lockdown_pages),
                        onClick = { expanded = !expanded },
                        showDivider = expanded,
                    )
                }
                if (expanded) {
                    pages.forEach { page ->
                        val current = state.lockdown.value
                        GroupedRow(
                            showDivider = page != pages.last(),
                            trailing = {
                                IOSSwitch(
                                    checked = current?.guards(page.host) == true,
                                    enabled = current != null,
                                    onCheckedChange = {
                                        actions.setLockdown(deployment, page.host, it)
                                    },
                                )
                            },
                        ) {
                            RowLabel(page.name, page.host)
                        }
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
