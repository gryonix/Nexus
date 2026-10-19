package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.servercontrol.CommandCatalog.Backups.Schedule
import android.text.format.Formatter
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
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
    LaunchedEffect(deployment.id) { model.load(deployment) }
    IOSSheet(
        title = stringResource(R.string.system_update_title),
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
                onSwap = { size -> model.setSwap(deployment, node.sshHost, size) },
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
            showDivider = current.isOn || current != saved,
        )
        if (current.isOn) ScheduleFieldRows(current, defaultHour = 4) { draft = it }
        if (current != saved) {
            ActionRow(
                text = stringResource(R.string.updates_save),
                enabled = !state.busy,
                onClick = { onSave(current) },
                showDivider = false,
            )
        }
    }
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
    onSwap: (Int?) -> Unit,
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
        )
        if (status != null && (status.isRunning || (status.exitCode ?: 0) != 0)) {
            RunLog(status.log.takeLast(12).joinToString("\n"))
        }
        if (status?.needsRestart == true) Muted(stringResource(R.string.system_update_restart))
        SwapLine(status, enabled = status != null && !state.busy, onSwap = onSwap)
        ToggleRow(
            title = stringResource(R.string.system_update_at_start_system),
            checked = status?.systemAtStart ?: false,
            onCheckedChange = { onAtStart(SystemUpdate.Part.SYSTEM, it) },
            enabled = status != null && !state.busy,
        )
        val offersAtStop = status?.offersAtStop == true
        ToggleRow(
            title = stringResource(R.string.system_update_at_start_apps),
            checked = status?.appsAtStart ?: false,
            onCheckedChange = { onAtStart(SystemUpdate.Part.APPS, it) },
            enabled = status != null && !state.busy,
            showDivider = offersAtStop,
        )
        if (offersAtStop) {
            ToggleRow(
                title = stringResource(R.string.system_update_at_stop_system),
                checked = status?.systemAtStop ?: false,
                onCheckedChange = { onAtStop(SystemUpdate.Part.SYSTEM, it) },
                enabled = !state.busy,
            )
            ToggleRow(
                title = stringResource(R.string.system_update_at_stop_apps),
                checked = status?.appsAtStop ?: false,
                onCheckedChange = { onAtStop(SystemUpdate.Part.APPS, it) },
                enabled = !state.busy,
                showDivider = false,
            )
        }
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

/** The machine's swap, tapped to pick a new size */
@Composable
private fun SwapLine(status: SystemUpdateStatus?, enabled: Boolean, onSwap: (Int?) -> Unit) {
    var asking by remember { mutableStateOf(false) }
    var custom by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val value = status?.swapBytes?.takeIf { it > 0 }?.let { Formatter.formatShortFileSize(context, it) }
        ?: stringResource(R.string.swap_none)
    ValueRow(stringResource(R.string.storage_swap), value, onClick = if (enabled) ({ asking = true }) else null)
    if (asking) {
        IOSAlert(
            title = stringResource(R.string.swap_title),
            message = stringResource(R.string.swap_note),
            onDismiss = { asking = false },
            actions = SwapPlan.SIZES.map { size ->
                AlertAction(stringResource(R.string.swap_size, size.toString())) { asking = false; onSwap(size) }
            } + AlertAction(stringResource(R.string.swap_other)) { asking = false; custom = true } +
                AlertAction(stringResource(R.string.swap_off), destructive = true) { asking = false; onSwap(null) } +
                AlertAction(stringResource(R.string.close)) { asking = false },
        )
    }
    if (custom) CustomSwapSizeAlert(onSet = { onSwap(it) }, onDismiss = { custom = false })
}
