package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl
import com.skaymer.gryonixnexus.app.ui.design.StepperRow
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog.Backups.Schedule

/** Interval and time rows of a schedule that is on */
@Composable
fun ScheduleFieldRows(schedule: Schedule, defaultHour: Int, onChange: (Schedule) -> Unit) {
    val hours = schedule as? Schedule.Hours
    val days = schedule as? Schedule.Days
    GroupedRow {
        IOSSegmentedControl(
            segments = listOf(true, false),
            selected = hours != null,
            modifier = Modifier.weight(1f),
            label = { stringResource(if (it) R.string.updates_every_hours else R.string.updates_every_days) },
            onSelect = { wantsHours ->
                onChange(if (wantsHours) Schedule.Hours(6, 0) else Schedule.Days(1, defaultHour, 0))
            },
        )
    }
    if (hours != null) {
        StepperRow(
            label = stringResource(R.string.updates_hours_between),
            value = hours.count,
            range = 1..23,
            onChange = { onChange(hours.copy(count = it)) },
        )
        MinuteRow(hours.minute) { onChange(hours.copy(minute = it)) }
    }
    if (days != null) {
        StepperRow(
            label = stringResource(R.string.updates_days_between),
            value = days.count,
            range = 1..28,
            onChange = { onChange(days.copy(count = it)) },
        )
        StepperRow(
            label = stringResource(R.string.updates_at_hour),
            value = days.hour,
            range = 0..23,
            format = { "%02d".format(it) },
            onChange = { onChange(days.copy(hour = it)) },
        )
        MinuteRow(days.minute) { onChange(days.copy(minute = it)) }
    }
}

@Composable
private fun MinuteRow(minute: Int, onChange: (Int) -> Unit) {
    StepperRow(
        label = stringResource(R.string.updates_at_minute),
        value = minute,
        range = 0..59,
        format = { "%02d".format(it) },
        onChange = onChange,
    )
}
