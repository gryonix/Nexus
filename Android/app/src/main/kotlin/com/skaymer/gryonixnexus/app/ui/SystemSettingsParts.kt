package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.PendingRules
import com.skaymer.gryonixnexus.app.servers.HostSystemSettings
import com.skaymer.gryonixnexus.app.servers.HostSystemUpdate
import com.skaymer.gryonixnexus.app.ui.design.ApplyPendingBar
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.MenuCheckItem
import com.skaymer.gryonixnexus.app.ui.design.MenuValueRow
import com.skaymer.gryonixnexus.app.ui.design.StepperRow
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.servercontrol.HostNameRules
import com.skaymer.gryonixnexus.servercontrol.RebootSchedule
import java.time.DayOfWeek
import java.time.format.TextStyle
import java.util.Locale

/** Time zone, host name and time sync of one machine */
@Composable
fun SystemSettingsSection(
    state: HostSystemSettings,
    header: String?,
    onTimeZone: (String) -> Unit,
    onHostName: (String) -> Unit,
    onTimeSync: (Boolean) -> Unit,
) {
    val settings = state.settings ?: return
    var picking by remember { mutableStateOf(false) }
    var naming by remember { mutableStateOf(false) }
    GroupedSection(header = header, footer = state.errorMessage) {
        ValueRow(stringResource(R.string.system_time_zone), settings.time_zone, onClick = { picking = true })
        ValueRow(stringResource(R.string.system_host_name), settings.host_name, onClick = { naming = true })
        ToggleRow(
            title = stringResource(R.string.system_time_sync),
            subtitle = if (!settings.ntp_enabled) null else stringResource(
                if (settings.ntp_synchronized) R.string.system_time_synced else R.string.system_time_not_synced,
            ),
            checked = settings.ntp_enabled,
            onCheckedChange = onTimeSync,
            enabled = !state.busy,
            showDivider = false,
        )
    }
    if (picking) {
        TimeZoneSheet(settings.time_zone, settings.time_zones, { picking = false; onTimeZone(it) }) { picking = false }
    }
    if (naming) {
        HostNameSheet(settings.host_name, { naming = false; onHostName(it) }) { naming = false }
    }
}

@Composable
private fun TimeZoneSheet(current: String, zones: List<String>, onPick: (String) -> Unit, onClose: () -> Unit) {
    var search by remember { mutableStateOf("") }
    val query = search.trim().replace(' ', '_')
    val shown = if (query.isEmpty()) zones else zones.filter { it.contains(query, ignoreCase = true) }
    IOSSheet(
        title = stringResource(R.string.system_time_zone),
        onClose = onClose,
        closeLabel = stringResource(R.string.close),
        scrollable = false,
    ) {
        GroupedSection { FieldRow(stringResource(R.string.system_search_zones), search, { search = it }, showDivider = false) }
        LazyColumn(Modifier.fillMaxWidth()) {
            items(shown) { zone -> CheckRow(zone, checked = zone == current, onClick = { onPick(zone) }) }
        }
    }
}

@Composable
private fun HostNameSheet(current: String, onSave: (String) -> Unit, onClose: () -> Unit) {
    var draft by remember { mutableStateOf(current) }
    val valid = HostNameRules.isValid(draft)
    IOSSheet(
        title = stringResource(R.string.system_host_name),
        onClose = onClose,
        closeLabel = stringResource(R.string.close),
        bottomBar = {
            ApplyPendingBar(
                visible = PendingRules.hostName(draft, current),
                apply = stringResource(R.string.save),
                cancel = stringResource(R.string.pending_changes_cancel),
                onApply = { onSave(draft) },
                onRevert = { draft = current },
            )
        },
    ) {
        GroupedSection(
            footer = stringResource(
                if (draft.isEmpty() || valid) R.string.system_host_name_hint else R.string.system_host_name_invalid,
            ),
        ) {
            FieldRow(stringResource(R.string.system_host_name), draft, { draft = it.lowercase() }, showDivider = false)
        }
    }
}

/** The reboot timer of one machine */
@Composable
fun RebootScheduleSection(state: HostSystemUpdate?, onSave: (RebootSchedule) -> Unit) {
    val saved = state?.status?.rebootSchedule ?: return
    var draft by remember(saved) { mutableStateOf(saved) }
    val current = draft
    GroupedSection {
        MenuValueRow(
            title = stringResource(R.string.system_reboot_auto),
            value = modeName(current),
            enabled = !state.busy,
            showDivider = current != RebootSchedule.Off,
        ) { close ->
            RebootMode.entries.forEach { mode ->
                MenuCheckItem(stringResource(mode.label), mode == RebootMode.of(current)) {
                    draft = mode.from(current)
                    close()
                }
            }
        }
        if (current is RebootSchedule.Weekly) {
            MenuValueRow(stringResource(R.string.system_reboot_day), dayName(current.weekday)) { close ->
                (1..7).forEach { day ->
                    MenuCheckItem(dayName(day), day == current.weekday) { draft = current.copy(weekday = day); close() }
                }
            }
        }
        if (current != RebootSchedule.Off) TimeRows(current) { draft = it }
    }
    ApplyPendingBar(
        visible = PendingRules.waits(current, saved, busy = state.busy),
        apply = stringResource(R.string.updates_save),
        cancel = stringResource(R.string.pending_changes_cancel),
        onApply = { onSave(current) },
        onRevert = { draft = saved },
    )
}

@Composable
private fun TimeRows(schedule: RebootSchedule, onChange: (RebootSchedule) -> Unit) {
    val (hour, minute) = schedule.timeOfDay()
    StepperRow(stringResource(R.string.updates_at_hour), hour, 0..23, { onChange(schedule.at(it, minute)) },
        format = { "%02d".format(it) })
    StepperRow(stringResource(R.string.updates_at_minute), minute, 0..59, { onChange(schedule.at(hour, it)) },
        showDivider = false, format = { "%02d".format(it) })
}

private enum class RebootMode(val label: Int) {
    OFF(R.string.updates_off), DAILY(R.string.system_reboot_daily), WEEKLY(R.string.system_reboot_weekly);

    fun from(current: RebootSchedule): RebootSchedule {
        val (hour, minute) = current.timeOfDay()
        return when (this) {
            OFF -> RebootSchedule.Off
            DAILY -> RebootSchedule.Daily(hour, minute)
            WEEKLY -> RebootSchedule.Weekly(7, hour, minute)
        }
    }

    companion object {
        fun of(schedule: RebootSchedule): RebootMode = when (schedule) {
            RebootSchedule.Off -> OFF
            is RebootSchedule.Daily -> DAILY
            is RebootSchedule.Weekly -> WEEKLY
        }
    }
}

@Composable
private fun modeName(schedule: RebootSchedule): String = stringResource(
    when (schedule) {
        RebootSchedule.Off -> R.string.updates_off
        is RebootSchedule.Daily -> R.string.system_reboot_daily
        is RebootSchedule.Weekly -> R.string.system_reboot_weekly
    },
)

private fun dayName(weekday: Int): String = DayOfWeek.of(weekday).getDisplayName(TextStyle.FULL, Locale.getDefault())
