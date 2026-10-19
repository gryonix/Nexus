package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.hosts.HostProbeState
import com.skaymer.gryonixnexus.app.servers.MetricsFormat
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.servercontrol.DiskMount
import com.skaymer.gryonixnexus.servercontrol.DiskRowPlan
import com.skaymer.gryonixnexus.servercontrol.WGStatus

/** One machine's own numbers: the tunnel, memory and disk */
@Composable
fun HostCard(
    title: String,
    state: HostProbeState,
    modifier: Modifier = Modifier,
    /** Opens THIS machine's history */
    onOpenHistory: (() -> Unit)? = null,
    inlineHistory: (@Composable () -> Unit)? = null,
    /** Opens THIS machine's power and energy */
    onOpenEnergy: (() -> Unit)? = null,
    /** Opens THIS machine's disk and internet speed test */
    onOpenSpeed: (() -> Unit)? = null,
    /** Opens THIS machine's busiest processes */
    onOpenProcesses: (() -> Unit)? = null,
) {
    var othersExpanded by remember { mutableStateOf(false) }
    var historyExpanded by remember { mutableStateOf(false) }
    GroupedSection(modifier = modifier, header = title) {
        val rows = mutableListOf<@Composable (Boolean) -> Unit>()

        state.wireGuard?.let { status ->
            rows += { last -> WireGuardRow(status, last) }
        }
        state.wireGuardFailed?.let { message ->
            rows += { last -> FailureRow(message, last) }
        }

        state.memory?.let { usage ->
            rows += { last ->
                UsageRow(
                    title = stringResource(R.string.metrics_memory),
                    usedBytes = usage.memUsedBytes,
                    totalBytes = usage.memTotalBytes,
                    showDivider = !last,
                )
            }
            if (usage.swapTotalBytes > 0) {
                rows += { last ->
                    UsageRow(
                        title = "Swap",
                        usedBytes = usage.swapUsedBytes,
                        totalBytes = usage.swapTotalBytes,
                        showDivider = !last,
                    )
                }
            }
        }
        state.memoryFailed?.let { message -> rows += { last -> FailureRow(message, last) } }

        state.disk?.let { mounts ->
            // The rule lives in `DiskRowPlan`, which both apps go through.
            val plan = DiskRowPlan.make(mounts)
            for (mount in plan.primary) {
                rows += { last ->
                    UsageRow(
                        title = if (plan.namesPrimaryByTarget) {
                            "${stringResource(R.string.metric_disk)} ${mount.target}"
                        } else {
                            stringResource(R.string.metric_disk)
                        },
                        usedBytes = mount.usedBytes,
                        totalBytes = mount.sizeBytes,
                        showDivider = !last,
                    )
                }
            }
            if (plan.others.isNotEmpty()) {
                rows += { last ->
                    GroupedRow(
                        onClick = { othersExpanded = !othersExpanded },
                        showDivider = !last || othersExpanded,
                        trailing = {
                            Text(
                                if (othersExpanded) "−" else "+",
                                style = MaterialTheme.typography.bodyMedium,
                                color = Gryonix.colors.secondaryLabel,
                            )
                        },
                    ) {
                        Text(
                            stringResource(R.string.host_other_volumes, plan.others.size),
                            style = MaterialTheme.typography.bodyMedium,
                            color = Gryonix.colors.secondaryLabel,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
                if (othersExpanded) {
                    for ((index, mount) in plan.others.withIndex()) {
                        rows += { last ->
                            UsageRow(
                                title = mount.target,
                                usedBytes = mount.usedBytes,
                                totalBytes = mount.sizeBytes,
                                showDivider = !last || index < plan.others.lastIndex,
                            )
                        }
                    }
                }
            }
        }
        state.diskFailed?.let { message -> rows += { last -> FailureRow(message, last) } }

        if (inlineHistory != null) {
            rows += { last ->
                GroupedRow(
                    onClick = { historyExpanded = !historyExpanded },
                    showDivider = !last || historyExpanded,
                    trailing = {
                        Text(
                            if (historyExpanded) "−" else "+",
                            style = MaterialTheme.typography.bodyMedium,
                            color = Gryonix.colors.secondaryLabel,
                        )
                    },
                ) {
                    Text(
                        stringResource(R.string.metrics_history),
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            if (historyExpanded) {
                rows += { last ->
                    GroupedRow(showDivider = !last) {
                        Column(Modifier.weight(1f).padding(vertical = 4.dp)) { inlineHistory() }
                    }
                }
            }
        } else {
            onOpenHistory?.let { open ->
                rows += { last ->
                    GroupedRow(onClick = open, showDivider = !last) {
                        Text(
                            stringResource(R.string.metrics_open_history),
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }

        onOpenProcesses?.let { open ->
            rows += { last ->
                GroupedRow(onClick = open, showDivider = !last) {
                    Text(
                        stringResource(R.string.processes_title),
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }

        onOpenSpeed?.let { open ->
            rows += { last ->
                GroupedRow(onClick = open, showDivider = !last) {
                    Text(
                        stringResource(R.string.speed_title),
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }

        onOpenEnergy?.let { open ->
            rows += { last ->
                GroupedRow(onClick = open, showDivider = !last) {
                    Text(
                        stringResource(R.string.energy_title),
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }

        if (rows.isEmpty()) {
            GroupedRow(showDivider = false) {
                Text(
                    if (state.hasAnswered) {
                        stringResource(R.string.host_nothing_reported)
                    } else {
                        stringResource(R.string.host_reading)
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
        } else {
            for ((index, row) in rows.withIndex()) row(index == rows.lastIndex)
        }
    }
}

@Composable
private fun UsageRow(title: String, usedBytes: Long, totalBytes: Long, showDivider: Boolean) {
    val colors = Gryonix.colors
    GroupedRow(showDivider = showDivider) {
        Column(Modifier.weight(1f)) {
            androidx.compose.foundation.layout.Row(Modifier.fillMaxWidth()) {
                Text(
                    title,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    "${MetricsFormat.bytes(usedBytes)} / ${MetricsFormat.bytes(totalBytes)}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.secondaryLabel,
                )
            }
            Spacer(Modifier.height(6.dp))
            val fraction =
                if (totalBytes > 0) (usedBytes.toDouble() / totalBytes.toDouble()) else 0.0
            LinearProgressIndicator(
                progress = { fraction.toFloat().coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun WireGuardRow(status: WGStatus, last: Boolean) {
    val colors = Gryonix.colors
    val up = status.peers.isNotEmpty()
    GroupedRow(
        showDivider = !last,
        trailing = {
            Text(
                if (up) {
                    stringResource(R.string.relay_on)
                } else {
                    stringResource(R.string.relay_off)
                },
                style = MaterialTheme.typography.bodyMedium,
                color = if (up) colors.success else colors.secondaryLabel,
            )
        },
    ) {
        Text(
            stringResource(R.string.host_vpn_connection),
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f),
        )
    }
}

/** A probe that refused, said as a refusal */
@Composable
private fun FailureRow(message: String, last: Boolean) {
    GroupedRow(showDivider = !last) {
        Text(
            message,
            style = MaterialTheme.typography.bodySmall,
            color = Gryonix.colors.danger,
            modifier = Modifier.padding(vertical = 2.dp),
        )
    }
}
