package com.skaymer.gryonixnexus.app.ui

import android.text.format.DateUtils
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.HostMetricsState
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.servers.MetricBlock
import com.skaymer.gryonixnexus.app.servers.RingLayout
import com.skaymer.gryonixnexus.app.servers.MetricsFormat
import com.skaymer.gryonixnexus.servercontrol.HostMetricsSnapshot
import com.skaymer.gryonixnexus.servercontrol.MetricsIndicatorStyle
import kotlinx.coroutines.delay

/** One machine's readings, as a card draws them */
@Composable
fun MetricsBlock(
    state: HostMetricsState,
    style: MetricsIndicatorStyle = MetricsIndicatorStyle.BARS,
    detailed: Boolean,
    compact: Boolean = false,
    /** Sends a wake-up, for the machine Wake-on-LAN reaches */
    onWake: (() -> Unit)? = null,
    /** When and whether the wake-up is offered */
    wakeGate: WakeGate = WakeGate(),
    modifier: Modifier = Modifier
) {
    val snapshot = state.snapshot
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        when {
            snapshot != null -> Readings(snapshot, style, detailed, compact)
            state.errorMessage != null -> OfflineNote(state, onWake, wakeGate)
            else -> Text(
                stringResource(R.string.metrics_waiting),
                style = MaterialTheme.typography.labelMedium,
                maxLines = 1
            )
        }
    }
}

@Composable
private fun Readings(
    snapshot: HostMetricsSnapshot,
    style: MetricsIndicatorStyle,
    detailed: Boolean,
    compact: Boolean
) {
    val gauges = listOf(
        Reading(
            stringResource(R.string.metrics_cpu),
            snapshot.cpuPercent?.div(100.0),
            snapshot.cpuPercent?.let { MetricsFormat.percent(it) }
        ),
        Reading(
            stringResource(R.string.metrics_memory),
            snapshot.memUsedFraction,
            "${MetricsFormat.bytes(snapshot.memUsedBytes)} / " +
                MetricsFormat.bytes(snapshot.memTotalBytes)
        ),
        Reading(
            stringResource(R.string.metrics_disk),
            snapshot.diskUsedFraction,
            "${MetricsFormat.bytes(snapshot.diskUsedBytes)} / " +
                MetricsFormat.bytes(snapshot.diskTotalBytes)
        ),
    )
    Box(Modifier.fillMaxWidth().height(MetricBlock.height(compact).dp)) {
        val spread = Arrangement.spacedBy(MetricBlock.gap(compact).dp, Alignment.CenterVertically)
        when (style) {
            MetricsIndicatorStyle.BARS -> Column(
                Modifier.fillMaxSize(),
                verticalArrangement = spread,
            ) { gauges.forEach { Gauge(it.label, it.fraction, it.detail) } }
            MetricsIndicatorStyle.TRACK -> Column(
                Modifier.fillMaxSize(),
                verticalArrangement = spread,
            ) { gauges.forEach { Track(it) } }
            MetricsIndicatorStyle.RINGS -> Rings(gauges, compact)
            MetricsIndicatorStyle.MINIMAL -> Column(
                Modifier.fillMaxSize(),
                verticalArrangement = spread,
            ) { gauges.forEach { Minimal(it) } }
        }
    }
    if (!detailed) return

    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Caption(
            stringResource(R.string.metrics_load),
            MetricsFormat.load(snapshot.load1)
        )
        if (!snapshot.isPartial) {
            Caption(
                stringResource(R.string.metrics_uptime),
                MetricsFormat.uptime(snapshot.uptimeSeconds)
            )
        }
        snapshot.temperatureCelsius?.let {
            Caption(null, MetricsFormat.temperature(it))
        }
    }
    Caption(
        stringResource(R.string.metrics_network),
        rates(
            stringResource(R.string.metrics_download), snapshot.netReceivedPerSecond,
            stringResource(R.string.metrics_upload), snapshot.netSentPerSecond
        )
    )
    Caption(
        stringResource(R.string.metrics_io),
        rates(
            stringResource(R.string.metrics_disk_read), snapshot.diskReadPerSecond,
            stringResource(R.string.metrics_disk_write), snapshot.diskWrittenPerSecond
        )
    )
}

@Composable
private fun rates(
    incomingLabel: String,
    incoming: Double?,
    outgoingLabel: String,
    outgoing: Double?
): String =
    if (incoming == null || outgoing == null) {
        stringResource(R.string.metrics_no_reading)
    } else {
        "$incomingLabel ${MetricsFormat.rate(incoming)}  " +
            "$outgoingLabel ${MetricsFormat.rate(outgoing)}"
    }

@Composable
private fun Gauge(label: String, fraction: Double?, detail: String?) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            maxLines = 1,
            modifier = Modifier.width(34.dp)
        )
        LinearProgressIndicator(
            progress = { fraction?.coerceIn(0.0, 1.0)?.toFloat() ?: 0f },
            modifier = Modifier.weight(1f)
        )
        Text(
            detail ?: stringResource(R.string.metrics_no_reading),
            style = MaterialTheme.typography.labelSmall,
            maxLines = 1,
            overflow = TextOverflow.Clip
        )
    }
}

@Composable
private fun Caption(label: String?, value: String) {
    Text(
        if (label == null) value else "$label $value",
        style = MaterialTheme.typography.labelSmall,
        maxLines = 1
    )
}

private data class Reading(val label: String, val fraction: Double?, val detail: String?)

/** "Line": the words above, one continuous track underneath */
@Composable
private fun Track(reading: Reading) {
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(reading.label, style = MaterialTheme.typography.labelSmall, maxLines = 1)
            Text(
                reading.detail ?: stringResource(R.string.metrics_no_reading),
                style = MaterialTheme.typography.labelSmall,
                maxLines = 1,
                overflow = TextOverflow.Clip
            )
        }
        LinearProgressIndicator(
            progress = { reading.fraction?.coerceIn(0.0, 1.0)?.toFloat() ?: 0f },
            strokeCap = StrokeCap.Round,
            modifier = Modifier.fillMaxWidth().height(6.dp)
        )
    }
}

@Composable
private fun Rings(readings: List<Reading>, compact: Boolean) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val width = maxWidth.value
        val height = maxHeight.value
        val stacked = RingLayout.stacks(width, height, readings.size)
        if (stacked) {
            Column(
                Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(
                    MetricBlock.STACKED_RING_GUTTER.dp,
                    Alignment.CenterVertically,
                ),
            ) {
                val diameter = RingLayout.stackedDiameter(width, height, readings.size)
                readings.forEach { reading ->
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(MetricBlock.STACKED_LABEL_GAP.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Ring(reading, diameter)
                        Text(reading.label, style = MaterialTheme.typography.labelSmall, maxLines = 1)
                    }
                }
            }
        } else {
            val diameter = RingLayout.diameter(width, height, readings.size)
            Row(
                Modifier.fillMaxSize(),
                horizontalArrangement = Arrangement.spacedBy(
                    MetricBlock.RING_GUTTER.dp,
                    Alignment.CenterHorizontally,
                ),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                readings.forEach { reading ->
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Ring(reading, diameter)
                        Text(reading.label, style = MaterialTheme.typography.labelSmall, maxLines = 1)
                    }
                }
            }
        }
    }
}

@Composable
private fun Ring(reading: Reading, diameter: Float) {
    Box(contentAlignment = Alignment.Center) {
        CircularProgressIndicator(
            progress = { reading.fraction?.coerceIn(0.0, 1.0)?.toFloat() ?: 0f },
            strokeCap = StrokeCap.Round,
            modifier = Modifier.size(diameter.dp)
        )
        Text(
            reading.fraction?.let { MetricsFormat.percent(it * 100) }
                ?: stringResource(R.string.metrics_no_reading),
            style = if (diameter >= 60f) {
                MaterialTheme.typography.labelLarge
            } else {
                MaterialTheme.typography.labelSmall
            },
            maxLines = 1
        )
    }
}

@Composable
private fun Minimal(reading: Reading) {
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(reading.label, style = MaterialTheme.typography.labelSmall, maxLines = 1)
            Text(
                reading.fraction?.let { MetricsFormat.percent(it * 100) }
                    ?: stringResource(R.string.metrics_no_reading),
                style = MaterialTheme.typography.titleSmall,
                maxLines = 1
            )
        }
        HorizontalDivider()
    }
}

/** Silence before the wake-up, and whether we share its network */
data class WakeGate(val afterSeconds: Int = 15, val onNetwork: Boolean? = null)

/** No connection, when the machine last answered, and a wake-up */
@Composable
private fun OfflineNote(state: HostMetricsState, onWake: (() -> Unit)?, gate: WakeGate) {
    val lastSeen = state.lastSeen
    Text(
        stringResource(R.string.metrics_no_connection),
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.error,
        maxLines = 1
    )
    val now by produceState(System.currentTimeMillis()) {
        while (true) {
            delay(5_000)
            value = System.currentTimeMillis()
        }
    }
    lastSeen?.let { seen ->
        val ago = DateUtils.getRelativeTimeSpanString(minOf(seen, now), now, DateUtils.SECOND_IN_MILLIS)
        Text(
            stringResource(R.string.metrics_last_answered, ago),
            style = MaterialTheme.typography.labelMedium,
            color = Gryonix.colors.secondaryLabel,
            maxLines = 2
        )
    }
    val since = lastSeen ?: state.offlineSince ?: now
    if (onWake == null || now - since < gate.afterSeconds * 1000L) return
    if (gate.onNetwork == false) {
        Text(
            stringResource(R.string.metrics_wake_off_network),
            style = MaterialTheme.typography.labelMedium,
            color = Gryonix.colors.secondaryLabel,
            maxLines = 3,
            modifier = Modifier.padding(top = 6.dp),
        )
        return
    }
    Button(
        onClick = onWake,
        modifier = Modifier.fillMaxWidth().padding(top = 6.dp).height(48.dp),
    ) {
        Text(stringResource(R.string.metrics_wake_up), style = MaterialTheme.typography.titleMedium)
    }
}
