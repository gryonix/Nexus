package com.skaymer.gryonixnexus.app.ui

import androidx.compose.material3.Icon
import androidx.compose.material.icons.outlined.Download
import com.skaymer.gryonixnexus.app.servers.PendingRules
import com.skaymer.gryonixnexus.app.ui.design.ApplyPendingBar
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog.Backups.Schedule
import android.text.format.Formatter
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.app.ui.design.WheelRow
import com.skaymer.gryonixnexus.catalog.storage.SwapPlan
import com.skaymer.gryonixnexus.servercontrol.SystemUpdateStatus
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.HostSystemUpdate
import com.skaymer.gryonixnexus.app.servers.SystemUpdateViewModel
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.RunLog
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.SystemUpdate
import java.text.DateFormat
import java.util.Date

/** The server screen row opening system updates */
@Composable
fun SystemUpdateCard(onOpen: () -> Unit, showDivider: Boolean = true) {
    GroupedRow(showDivider = showDivider, onClick = onOpen, trailing = { DisclosureChevron() }) {
        RowLabel(stringResource(R.string.system_update_title))
    }
}

/** Each machine's packages: update now, or at every start */
@Composable
fun SystemUpdateDialog(deployment: Deployment, model: SystemUpdateViewModel, onClose: () -> Unit) {
    val hosts by model.hosts.collectAsState()
    val actions = (LocalContext.current.applicationContext as GryonixApplication).hostActions
    LaunchedEffect(deployment.id) { model.load(deployment) }
    IOSSheet(
        title = stringResource(R.string.general_system),
        onClose = onClose,
        closeLabel = stringResource(R.string.close),
    ) {
        deployment.nodes.forEachIndexed { index, node ->
            val last = index == deployment.nodes.lastIndex
            HostSystemSection(
                node = node,
                label = if (deployment.nodes.size > 1) node.name.ifEmpty { node.endpoint.host } else null,
                state = hosts[node.sshHost] ?: HostSystemUpdate(busy = true),
                footer = if (last) stringResource(R.string.system_update_switches_note) else null,
                onStart = { model.start(deployment, node.sshHost) },
                onAtStart = { part, on -> model.setAtStart(deployment, node.sshHost, part, on) },
                onAtStop = { part, on -> model.setAtStop(deployment, node.sshHost, part, on) },
                onReboot = { actions.reboot(deployment, node.sshHost) },
            )
            HostScheduleSection(hosts[node.sshHost]) { schedule ->
                model.setSchedule(deployment, node.sshHost, schedule)
            }
        }
    }
}

/** The system's own update timer on one machine */
@Composable
private fun HostScheduleSection(state: HostSystemUpdate?, onSave: (Schedule) -> Unit) {
    val status = state?.status ?: return
    val saved = status.schedule
    var draft by remember(saved) { mutableStateOf(saved) }
    GroupedSection {
        val current = draft
        if (saved == null || current == null) {
            Muted(stringResource(R.string.system_update_schedule_agent_too_old))
            return@GroupedSection
        }
        ToggleRow(
            title = stringResource(R.string.system_update_schedule),
            checked = current.isOn,
            onCheckedChange = { on -> draft = if (on) Schedule.Days(1, 4, 0) else Schedule.Off },
            enabled = !state.busy,
            showDivider = current.isOn,
        )
        if (current.isOn) ScheduleFieldRows(current, defaultHour = 4) { draft = it }
    }
    val asked = draft
    ApplyPendingBar(
        visible = saved != null && PendingRules.waits(asked, saved, busy = state.busy),
        apply = stringResource(R.string.updates_save),
        cancel = stringResource(R.string.pending_changes_cancel),
        onApply = { asked?.let(onSave) },
        onRevert = { draft = saved },
    )
}

@Composable
private fun HostSystemSection(
    node: DeploymentNode,
    label: String?,
    state: HostSystemUpdate,
    footer: String?,
    onStart: () -> Unit,
    onAtStart: (SystemUpdate.Part, Boolean) -> Unit,
    onAtStop: (SystemUpdate.Part, Boolean) -> Unit,
    onReboot: () -> Unit,
) {
    val status = state.status
    GroupedSection(header = label, footer = state.errorMessage ?: footer) {
        if (state.missing) {
            Muted(stringResource(R.string.system_update_agent_too_old))
            return@GroupedSection
        }
        Summary(state)
        ActionRow(
            text = stringResource(R.string.system_update_run),
            enabled = status != null && !status.isRunning && !state.busy,
            onClick = onStart,
            leading = {
                Icon(androidx.compose.material.icons.Icons.Outlined.Download, null, tint = Gryonix.colors.accent)
            },
        )
        if (status != null && (status.isRunning || (status.exitCode ?: 0) != 0)) {
            RunLog(status.log.takeLast(12).joinToString("\n"))
        }
        if (status?.needsRestart == true) RestartRows(onReboot)
        UpdateSwitches(state, onAtStart, onAtStop)
    }
}

/** System switches first, then the apps */
@Composable
private fun UpdateSwitches(
    state: HostSystemUpdate,
    onAtStart: (SystemUpdate.Part, Boolean) -> Unit,
    onAtStop: (SystemUpdate.Part, Boolean) -> Unit,
) {
    val status = state.status
    val enabled = status != null && !state.busy
    val offersAtStop = status?.offersAtStop == true
    ToggleRow(
        title = stringResource(R.string.system_update_at_start_system),
        checked = status?.systemAtStart ?: false,
        onCheckedChange = { onAtStart(SystemUpdate.Part.SYSTEM, it) },
        enabled = enabled,
    )
    if (offersAtStop) {
        ToggleRow(
            title = stringResource(R.string.system_update_at_stop_system),
            checked = status?.systemAtStop ?: false,
            onCheckedChange = { onAtStop(SystemUpdate.Part.SYSTEM, it) },
            enabled = enabled,
        )
    }
    ToggleRow(
        title = stringResource(R.string.system_update_at_start_apps),
        checked = status?.appsAtStart ?: false,
        onCheckedChange = { onAtStart(SystemUpdate.Part.APPS, it) },
        enabled = enabled,
        showDivider = offersAtStop,
    )
    if (offersAtStop) {
        ToggleRow(
            title = stringResource(R.string.system_update_at_stop_apps),
            checked = status?.appsAtStop ?: false,
            onCheckedChange = { onAtStop(SystemUpdate.Part.APPS, it) },
            enabled = enabled,
            showDivider = false,
        )
    }
}

/** The notice, and the switch that restarts the machine */
@Composable
private fun RestartRows(onReboot: () -> Unit) {
    var confirming by remember { mutableStateOf(false) }
    Muted(stringResource(R.string.system_update_restart))
    ToggleRow(
        title = stringResource(R.string.system_reboot_to_finish),
        checked = confirming,
        onCheckedChange = { if (it) confirming = true },
    )
    if (confirming) {
        ConfirmAlert(
            title = stringResource(R.string.actions_reboot_title),
            message = stringResource(R.string.actions_reboot_message),
            confirm = stringResource(R.string.actions_reboot_confirm),
            destructive = true,
            onConfirm = {
                confirming = false
                onReboot()
            },
            onCancel = { confirming = false },
        )
    }
}

@Composable
private fun Summary(state: HostSystemUpdate) {
    val status = state.status
    when {
        status == null -> Unit
        status.isRunning -> Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = Gryonix.colors.tertiaryLabel)
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.system_update_running), style = MaterialTheme.typography.bodyLarge)
        }
        (status.exitCode ?: 0) != 0 -> Muted(stringResource(R.string.system_update_failed))
        status.exitCode != null && status.finished != null -> Muted(
            stringResource(
                R.string.system_update_last,
                DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(status.finished!! * 1000)),
            ),
        )
        else -> Muted(stringResource(R.string.system_update_never))
    }
}

@Composable
private fun Muted(text: String) {
    Text(
        text,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
        style = MaterialTheme.typography.bodyLarge,
        color = Gryonix.colors.secondaryLabel,
    )
}

/** The machine's swap size in whole gigabytes, zero when none */
fun savedSwapGB(status: SystemUpdateStatus?): Int {
    val bytes = status?.swapBytes ?: return 0
    return if (bytes > 0) maxOf(1, Math.round(bytes / 1_073_741_824.0).toInt()) else 0
}

/** The machine's swap, picked on a wheel */
@Composable
fun SwapLine(status: SystemUpdateStatus?, enabled: Boolean, draft: Int?, onDraft: (Int) -> Unit) {
    val current = draft ?: savedSwapGB(status)
    val sizes = if (current in SwapPlan.WHEEL) SwapPlan.WHEEL else (SwapPlan.WHEEL + current).sorted()
    val none = stringResource(R.string.swap_none)
    val gigabytes = stringResource(R.string.swap_size, "%d")
    if (!enabled) {
        ValueRow(stringResource(R.string.storage_swap), if (current == 0) none else gigabytes.format(current), null)
        return
    }
    WheelRow(
        title = stringResource(R.string.storage_swap),
        choices = sizes.map { if (it == 0) none else gigabytes.format(it) },
        selected = sizes.indexOf(current),
        onSelect = { onDraft(sizes[it]) },
        showDivider = false,
    )
}
