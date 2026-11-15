package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.servercontrol.Deployment
import gryonixnexusd.v1.VpnSpeedFacts
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Opens what decides the tunnels' speed */
@Composable
fun VPNSpeedRow(server: Deployment) {
    var open by remember(server.id) { mutableStateOf(false) }
    GroupedSection {
        GroupedRow(
            onClick = { open = true },
            showDivider = false,
            leading = { Icon(Icons.Outlined.Speed, contentDescription = null, modifier = Modifier.size(22.dp), tint = Gryonix.colors.accent) },
            trailing = { com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron() },
        ) { RowLabel(stringResource(R.string.vpn_speed_title)) }
    }
    if (open) VPNSpeedSheet(server) { open = false }
}

@Composable
private fun VPNSpeedSheet(server: Deployment, onClose: () -> Unit) {
    val app = LocalContext.current.applicationContext as? GryonixApplication
    var facts by remember(server.id) { mutableStateOf<VpnSpeedFacts?>(null) }
    var firstDrops by remember(server.id) { mutableStateOf<Long?>(null) }
    var failure by remember(server.id) { mutableStateOf<String?>(null) }
    var reads by remember(server.id) { mutableStateOf(0) }
    val scope = rememberCoroutineScope()
    fun show(fresh: VpnSpeedFacts?) {
        if (fresh != null && firstDrops == null) firstDrops = drops(fresh)
        facts = fresh ?: facts
    }
    suspend fun read(block: suspend () -> VpnSpeedFacts?) {
        try {
            show(block())
            failure = null
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            failure = error.message ?: error::class.simpleName
        }
    }
    LaunchedEffect(server.id, reads) {
        read { app?.vpnSpeedFacts(server) }
        while (facts?.amnezia_kernel_status == "working") {
            delay(5_000)
            read { app?.vpnSpeedFacts(server) }
        }
    }
    IOSSheet(title = stringResource(R.string.vpn_speed_title), onClose = onClose, closeLabel = stringResource(R.string.containers_done)) {
        val shown = facts
        if (shown == null) {
            GroupedSection(footer = failure) { GroupedRow(showDivider = false) { RowLabel("…") } }
            return@IOSSheet
        }
        Tunnels(shown)
        AmneziaKernel(shown) { enabled -> scope.launch { read { app?.setAmneziaKernel(server, enabled) }; reads++ } }
        Server(shown, drops(shown) - minOf(firstDrops ?: drops(shown), drops(shown))) { reads++ }
    }
}

private fun drops(facts: VpnSpeedFacts): Long = facts.udp_receive_errors + facts.udp_buffer_errors

@Composable
private fun Tunnels(facts: VpnSpeedFacts) {
    GroupedSection(
        header = stringResource(R.string.vpn_speed_tunnels),
        note = stringResource(R.string.vpn_speed_mtu_note),
        footer = if (facts.interfaces.any { !it.kernel }) stringResource(R.string.vpn_speed_program_note) else null,
    ) {
        facts.interfaces.forEach { tunnel ->
            GroupedRow(
                showDivider = tunnel != facts.interfaces.last(),
                trailing = { Text("MTU ${tunnel.mtu}", color = Gryonix.colors.secondaryLabel) },
            ) {
                RowLabel(
                    if (tunnel.protocol == "amneziawg") "AmneziaWG" else "WireGuard",
                    stringResource(if (tunnel.kernel) R.string.vpn_speed_kernel else R.string.vpn_speed_program),
                )
            }
        }
    }
}

/** How far the agent got, from a note like "3/4" */
internal fun kernelStep(note: String): Pair<Int, Int>? {
    val parts = note.split("/")
    val done = parts.getOrNull(0)?.toIntOrNull() ?: return null
    val all = parts.getOrNull(1)?.toIntOrNull() ?: return null
    return if (parts.size == 2 && done in 1..all) done to all else null
}

/** The switch that moves AmneziaWG into the kernel */
@Composable
private fun AmneziaKernel(facts: VpnSpeedFacts, onSet: (Boolean) -> Unit) {
    val status = facts.amnezia_kernel_status
    val hasAmnezia = facts.interfaces.any { it.protocol == "amneziawg" }
    if (!hasAmnezia && status != "on" && status != "working") return
    val footer = when {
        status == "working" -> kernelStep(facts.amnezia_kernel_note)
            ?.let { (done, all) -> stringResource(R.string.vpn_kernel_working) + "\n" + stringResource(R.string.install_step, done, all) }
            ?: stringResource(R.string.vpn_kernel_working)
        status == "failed" && facts.amnezia_kernel_note.isNotEmpty() -> stringResource(R.string.vpn_kernel_failed, facts.amnezia_kernel_note)
        !facts.amnezia_kernel_possible && status != "on" -> stringResource(R.string.vpn_kernel_impossible)
        else -> stringResource(R.string.vpn_kernel_note)
    }
    GroupedSection(footer = footer) {
        GroupedRow(
            showDivider = false,
            trailing = {
                com.skaymer.gryonixnexus.app.ui.design.IOSSwitch(
                    checked = status == "on" || status == "working",
                    enabled = status != "working" && (facts.amnezia_kernel_possible || status == "on"),
                    onCheckedChange = onSet,
                )
            },
        ) { RowLabel(stringResource(R.string.vpn_kernel_switch)) }
    }
}

@Composable
private fun Server(facts: VpnSpeedFacts, sinceOpened: Long, onReadAgain: () -> Unit) {
    GroupedSection(header = stringResource(R.string.vpn_speed_server), footer = stringResource(R.string.vpn_speed_drops_note)) {
        GroupedRow(trailing = { Text("${facts.cpu_cores}", color = Gryonix.colors.secondaryLabel) }) {
            RowLabel(stringResource(R.string.vpn_speed_cores))
        }
        GroupedRow(trailing = {
            val busy = facts.load >= maxOf(facts.cpu_cores, 1).toDouble()
            Text(String.format("%.2f", facts.load), color = if (busy) Gryonix.colors.warning else Gryonix.colors.secondaryLabel)
        }) { RowLabel(stringResource(R.string.vpn_speed_load)) }
        GroupedRow(trailing = { Text("${drops(facts)}", color = Gryonix.colors.secondaryLabel) }) {
            RowLabel(stringResource(R.string.vpn_speed_udp_drops))
        }
        GroupedRow(trailing = { Text("+$sinceOpened", color = Gryonix.colors.secondaryLabel) }) {
            RowLabel(stringResource(R.string.vpn_speed_since_opened))
        }
        GroupedRow(onClick = onReadAgain, showDivider = false) {
            Text(stringResource(R.string.refresh_this_again), color = Gryonix.colors.accent)
        }
    }
}
