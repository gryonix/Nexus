package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.layout.Layout
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.DeviceThermostat
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.ShowChart
import androidx.compose.material.icons.outlined.WifiOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.HostMetricsState
import com.skaymer.gryonixnexus.app.servers.MetricsFormat
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.SymbolIcons
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostMetricsSnapshot
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

/** One machine's strip on a server card: header, gauges, traffic */
@Composable
fun MachineCardBlock(
    deployment: Deployment,
    host: SSHHostID,
    state: HostMetricsState,
    tint: Color,
    embedded: Boolean,
    compact: Boolean,
    /** Rings, track or minimal; null draws the segmented bars */
    otherGauges: (@Composable () -> Unit)?,
    offline: @Composable () -> Unit,
) {
    val snapshot = state.snapshot.takeIf { state.errorMessage == null }
    Column(verticalArrangement = Arrangement.spacedBy(if (compact) 6.dp else 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (embedded) {
                HostBadge(hostTitle(deployment, host), tint)
            } else {
                LeadingBadge(deployment, snapshot?.osID, tint)
                Text(
                    deployment.name,
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
                    color = Gryonix.colors.label,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.widthIn(max = 220.dp),
                )
            }
            Box(Modifier.weight(1f)) {
                if (!compact && host == deployment.servicesHost) ServiceIcons(deployment)
            }
            HeaderStatus(state, compact)
        }
        if (state.errorMessage != null || state.snapshot == null && !state.isConnecting) {
            offline()
        } else {
            if (otherGauges != null) otherGauges() else Gauges(snapshot, if (compact) 12 else 24)
            TrafficGrid(snapshot)
        }
    }
}

/** Two machines under one name, scenario B's card */
@Composable
fun CombinedCardHeader(deployment: Deployment, osID: String?, tint: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        LeadingBadge(deployment, osID, tint)
        Text(
            deployment.name,
            style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
            color = Gryonix.colors.label,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false),
        )
        HostBadge(machinesTitle(deployment), tint)
    }
}

@Composable
fun MachineDivider() = HorizontalDivider(color = Gryonix.colors.separator.copy(alpha = 0.5f))

@Composable
private fun machinesTitle(deployment: Deployment): String {
    val hosts = deployment.nodes.map { it.sshHost }
    return if (hosts.size == 2 && SSHHostID.VPS in hosts && SSHHostID.HOME in hosts) {
        stringResource(R.string.card_vps_plus_local)
    } else {
        pluralStringResource(R.plurals.machines_count, hosts.size, hosts.size)
    }
}

@Composable
private fun hostTitle(deployment: Deployment, host: SSHHostID): String = when (host) {
    SSHHostID.HOME -> stringResource(R.string.host_badge_local)
    SSHHostID.VPS -> "VPS"
    else -> deployment.nodes.firstOrNull { it.sshHost == host }
        ?.let { node -> node.name.ifEmpty { node.endpoint.host } }
        ?: stringResource(R.string.host_badge_server)
}

@Composable
private fun HostBadge(text: String, tint: Color) {
    Text(
        text,
        fontSize = 12.sp,
        fontWeight = FontWeight.SemiBold,
        color = tint,
        maxLines = 1,
        modifier = Modifier
            .background(tint.copy(alpha = 0.18f), RoundedCornerShape(50))
            .padding(horizontal = 8.dp, vertical = 2.dp),
    )
}

@Composable
private fun LeadingBadge(deployment: Deployment, osID: String?, tint: Color) {
    val symbol = deployment.iconSymbol
    val os = OS_BADGES[osID]
    when {
        symbol != null -> Icon(SymbolIcons.of(symbol), null, tint = tint, modifier = Modifier.size(22.dp))
        os != null -> Box(
            Modifier.size(22.dp).background(os.second, CircleShape),
            contentAlignment = Alignment.Center,
        ) { Text(os.first, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
        else -> Icon(
            SymbolIcons.of(if (deployment.isMultiHost) "point.3.connected.trianglepath.dotted" else "server.rack"),
            null, tint = tint, modifier = Modifier.size(22.dp),
        )
    }
}

private val OS_BADGES = mapOf(
    "debian" to ("D" to Color(0xFFFF3B30)),
    "ubuntu" to ("U" to Color(0xFFFF9500)),
    "raspbian" to ("R" to Color(0xFFFF2D55)),
    "fedora" to ("F" to Color(0xFF007AFF)),
    "centos" to ("C" to Color(0xFFAF52DE)),
    "rhel" to ("R" to Color(0xFFFF3B30)),
    "rocky" to ("R" to Color(0xFF34C759)),
    "almalinux" to ("A" to Color(0xFF5856D6)),
    "arch" to ("A" to Color(0xFF32ADE6)),
    "alpine" to ("A" to Color(0xFF007AFF)),
)

/** As many service icons as fit, then "+N" */
@Composable
private fun ServiceIcons(deployment: Deployment) {
    val services = ServiceRegistry.services(deployment.services)
    if (services.isEmpty()) return
    Layout(
        content = {
            services.forEach {
                Icon(SymbolIcons.of(it.systemImage), null, tint = Gryonix.colors.secondaryLabel, modifier = Modifier.size(18.dp))
            }
            for (hidden in 0..services.size) {
                Text("+$hidden", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Gryonix.colors.secondaryLabel)
            }
        },
    ) { measurables, constraints ->
        val loose = constraints.copy(minWidth = 0, minHeight = 0)
        val icons = measurables.take(services.size).map { it.measure(loose) }
        val pluses = measurables.drop(services.size).map { it.measure(loose) }
        val gap = 5.dp.roundToPx()
        val shown = (services.size downTo 0).first { count ->
            val iconsWidth = icons.take(count).sumOf { it.width + gap }
            val plus = if (count < services.size) pluses[services.size - count].width else 0
            iconsWidth + plus <= constraints.maxWidth
        }
        val height = (icons + pluses).maxOf { it.height }
        layout(constraints.maxWidth, height) {
            var x = 0
            icons.take(shown).forEach { it.placeRelative(x, (height - it.height) / 2); x += it.width + gap }
            if (shown < services.size) pluses[services.size - shown].let { it.placeRelative(x, (height - it.height) / 2) }
        }
    }
}

@Composable
private fun HeaderStatus(state: HostMetricsState, compact: Boolean) {
    val snapshot = state.snapshot
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        when {
            snapshot != null -> {
                if (state.errorMessage != null) Icon(Icons.Outlined.WifiOff, null, tint = Gryonix.colors.danger, modifier = Modifier.size(14.dp))
                snapshot.temperatureCelsius?.takeIf { !compact }?.let {
                    StatusItem(Icons.Outlined.DeviceThermostat, MetricsFormat.temperature(it),
                        if (it < 70) Gryonix.colors.success else Gryonix.colors.warning)
                }
                if (!snapshot.isPartial) StatusItem(Icons.Outlined.Schedule, MetricsFormat.uptime(snapshot.uptimeSeconds))
                if (!compact) StatusItem(Icons.Outlined.ShowChart, MetricsFormat.load(snapshot.load1))
            }
            state.errorMessage != null ->
                Icon(Icons.Outlined.WifiOff, null, tint = Gryonix.colors.danger, modifier = Modifier.size(14.dp))
            else -> CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
        }
    }
}

@Composable
private fun StatusItem(icon: ImageVector, text: String, color: Color = Gryonix.colors.secondaryLabel) {
    Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = color, modifier = Modifier.size(13.dp))
        Text(text, fontSize = 12.sp, color = color, maxLines = 1)
    }
}

@Composable
private fun Gauges(snapshot: HostMetricsSnapshot?, segments: Int) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        GaugeRow(stringResource(R.string.metrics_cpu), snapshot?.let { "${it.cpuCores} C" },
            snapshot?.cpuPercent, snapshot?.cpuPercent?.div(100), segments)
        GaugeRow(stringResource(R.string.metrics_memory),
            snapshot?.let { "${MetricsFormat.bytes(it.memUsedBytes)} / ${MetricsFormat.bytes(it.memTotalBytes)}" },
            snapshot?.let { it.memUsedFraction * 100 }, snapshot?.memUsedFraction, segments)
        GaugeRow(stringResource(R.string.metrics_disk),
            snapshot?.let { "${MetricsFormat.bytes(it.diskUsedBytes)} / ${MetricsFormat.bytes(it.diskTotalBytes)}" },
            snapshot?.let { it.diskUsedFraction * 100 }, snapshot?.diskUsedFraction, segments)
        SwapGaugeRow(snapshot, segments)
    }
}

/** Swap load, or "Off" when the machine has none */
@Composable
private fun SwapGaugeRow(snapshot: HostMetricsSnapshot?, segments: Int) {
    val fraction = snapshot?.takeUnless { it.isPartial }?.swapUsedFraction
    val detail = when {
        snapshot == null || snapshot.isPartial -> null
        fraction == null -> stringResource(R.string.metrics_swap_off)
        else -> "${MetricsFormat.bytes(snapshot.swapUsedBytes)} / ${MetricsFormat.bytes(snapshot.swapTotalBytes)}"
    }
    GaugeRow(stringResource(R.string.metrics_swap), detail, fraction?.times(100), fraction, segments)
}

@Composable
private fun GaugeRow(label: String, detail: String?, percent: Double?, fraction: Double?, segments: Int) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(label, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = Gryonix.colors.label, maxLines = 1)
            Text(detail ?: "—", fontSize = 13.sp, color = Gryonix.colors.secondaryLabel, maxLines = 1,
                modifier = Modifier.weight(1f))
            Text(percent?.let { MetricsFormat.percent(it) } ?: "—", fontSize = 13.sp, color = Gryonix.colors.label, maxLines = 1)
        }
        SegmentedBar(fraction ?: 0.0, segments)
    }
}

/** Segments fill green, then yellow past 60 %, orange past 85 % */
@Composable
fun SegmentedBar(fraction: Double, segments: Int = 24) {
    val filledUpTo = fraction.coerceIn(0.0, 1.0) * segments - 0.001
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        for (index in 0 until segments) {
            val position = (index + 1).toDouble() / segments
            val color = when {
                index >= filledUpTo -> Gryonix.colors.label.copy(alpha = 0.12f)
                position < 0.6 -> Gryonix.colors.success
                position < 0.85 -> Color(0xFFFFCC00)
                else -> Gryonix.colors.warning
            }
            Box(Modifier.weight(1f).height(5.dp).background(color, RoundedCornerShape(1.5.dp)))
        }
    }
}

@Composable
private fun TrafficGrid(snapshot: HostMetricsSnapshot?) {
    Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
        TrafficRow(stringResource(R.string.metrics_network),
            stringResource(R.string.metrics_upload), snapshot?.netSentPerSecond,
            stringResource(R.string.metrics_download), snapshot?.netReceivedPerSecond)
        TrafficRow(stringResource(R.string.metrics_io),
            stringResource(R.string.metrics_disk_read), snapshot?.diskReadPerSecond,
            stringResource(R.string.metrics_disk_write), snapshot?.diskWrittenPerSecond)
    }
}

@Composable
private fun TrafficRow(title: String, upLabel: String, up: Double?, downLabel: String, down: Double?) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(title, fontSize = 12.sp, lineHeight = 15.sp, color = Gryonix.colors.secondaryLabel, maxLines = 1,
            modifier = Modifier.weight(1f))
        TrafficValue(upLabel, up)
        Spacer(Modifier.width(10.dp))
        TrafficValue(downLabel, down)
    }
}

@Composable
private fun TrafficValue(label: String, value: Double?) {
    Text(label, fontSize = 12.sp, lineHeight = 15.sp, color = Gryonix.colors.secondaryLabel, maxLines = 1)
    Spacer(Modifier.width(4.dp))
    Text(
        value?.let { MetricsFormat.bytes(it.toLong()) } ?: "—",
        fontSize = 12.sp, lineHeight = 15.sp, color = Gryonix.colors.label, maxLines = 1,
        textAlign = androidx.compose.ui.text.style.TextAlign.End,
        modifier = Modifier.width(54.dp),
    )
}
