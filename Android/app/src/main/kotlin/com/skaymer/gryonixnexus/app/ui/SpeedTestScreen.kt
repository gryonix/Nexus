package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.size
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.speed.SpeedRecord
import com.skaymer.gryonixnexus.app.speed.SpeedState
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.catalog.storage.RaidPlan
import com.skaymer.gryonixnexus.catalog.storage.SpeedTest
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import java.text.DateFormat
import java.text.NumberFormat
import java.util.Date

/** Internet and disk speed of one server, with past runs */
@Composable
fun SpeedTestScreen(server: Deployment, host: SSHHostID) {
    val model = (LocalContext.current.applicationContext as GryonixApplication).speed
    val state by model.state.collectAsState()
    LaunchedEffect(server.id, host) { model.load(server, host) }

    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item {
            GroupedSection(header = stringResource(R.string.speed_internet), footer = stringResource(R.string.speed_internet_note)) {
                ResultRows(state.latest(null))
                RunRow(stringResource(R.string.speed_test_internet), state, "") { model.testInternet(server, host) }
            }
        }
        items(state.locations) { location ->
            val system = location == SpeedTest.SYSTEM_DIRECTORY
            GroupedSection(
                header = place(location),
                footer = stringResource(if (system) R.string.speed_system_note else R.string.speed_root_note),
            ) {
                ResultRows(state.latest(location))
                RunRow(stringResource(R.string.speed_test_disk), state, location) { model.testDisk(server, host, location) }
            }
        }
        state.failure?.let { failure -> item { GroupedSection(footer = failureText(failure, model.failureDetail)) {} } }
        if (state.records.isNotEmpty()) {
            item {
                GroupedSection(header = stringResource(R.string.speed_past)) {
                    state.records.forEach { HistoryRow(it, showDivider = it != state.records.last()) }
                }
            }
        }
    }
}

@Composable
private fun RunRow(title: String, state: SpeedState, location: String, onRun: () -> Unit) {
    ActionRow(
        text = title, onClick = onRun, enabled = state.running == null, showDivider = false,
        trailing = if (state.running == location) {
            { CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) }
        } else null,
    )
}

@Composable
private fun ResultRows(record: SpeedRecord?) {
    val internet = record?.internet
    val disk = record?.disk
    when {
        internet != null -> {
            ValueRow(stringResource(R.string.speed_download), bits(internet.downloadBitsPerSecond), null)
            ValueRow(stringResource(R.string.speed_upload), bits(internet.uploadBitsPerSecond), null)
            ValueRow(stringResource(R.string.speed_ping), stringResource(R.string.speed_ms, number(internet.latencySeconds * 1000)), null)
        }
        disk != null -> {
            ValueRow(stringResource(R.string.speed_write), bytes(disk.writeBytesPerSecond), null)
            ValueRow(stringResource(R.string.speed_read), bytes(disk.readBytesPerSecond), null,
                subtitle = if (disk.cached) stringResource(R.string.speed_cached) else null)
        }
        else -> ValueRow(stringResource(R.string.speed_not_tested), null, null)
    }
}

@Composable
private fun HistoryRow(record: SpeedRecord, showDivider: Boolean) {
    val internet = record.internet
    val disk = record.disk
    val summary = when {
        internet != null -> "↓ ${bits(internet.downloadBitsPerSecond)}  ↑ ${bits(internet.uploadBitsPerSecond)}"
        disk != null -> stringResource(
            R.string.speed_disk_summary, place(record.location.orEmpty()),
            bytes(disk.writeBytesPerSecond), bytes(disk.readBytesPerSecond),
        )
        else -> ""
    }
    val date = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(record.epochMillis))
    ValueRow(summary, null, null, subtitle = date, showDivider = showDivider)
}

@Composable
private fun place(location: String): String = when (location) {
    SpeedTest.SYSTEM_DIRECTORY -> stringResource(R.string.speed_system_disk)
    RaidPlan.MOUNT_POINT -> stringResource(R.string.speed_raid)
    else -> stringResource(R.string.speed_disk_at, location)
}

@Composable
private fun failureText(failure: SpeedState.Failure, detail: String?): String = when (failure) {
    SpeedState.Failure.NO_CURL -> stringResource(R.string.speed_no_curl)
    SpeedState.Failure.NO_ANSWER -> stringResource(R.string.speed_no_answer)
    SpeedState.Failure.NO_NUMBERS -> stringResource(R.string.speed_no_numbers)
    SpeedState.Failure.OTHER -> detail.orEmpty()
}

@Composable
private fun bits(perSecond: Double) = stringResource(R.string.speed_mbit, number(perSecond / 1_000_000))

@Composable
private fun bytes(perSecond: Double) = stringResource(R.string.speed_mb, number(perSecond / 1_000_000))

private fun number(value: Double): String = NumberFormat.getNumberInstance().apply {
    maximumFractionDigits = if (value < 10) 1 else 0
}.format(value)
