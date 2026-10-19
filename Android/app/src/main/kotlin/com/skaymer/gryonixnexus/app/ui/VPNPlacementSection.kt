package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.app.vpn.VPNMoveState
import com.skaymer.gryonixnexus.app.vpn.VPNMoveViewModel
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.vpnRunsOnRelay

/** Where the VPN runs: at home or on the VPS */
@Composable
fun VPNPlacementSection(server: Deployment) {
    val move = (LocalContext.current.applicationContext as GryonixApplication).vpnMove
    val state by move.state.collectAsState()
    val onRelay = server.vpnRunsOnRelay
    var confirming by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        PlacementRows(onRelay, moving = state.isRunning, onMove = { confirming = true })
        if (state.title != null && state.serverID == server.id) MoveProgress(state, onClose = move::clear)
    }
    if (confirming) {
        ConfirmAlert(
            title = stringResource(if (onRelay) R.string.vpn_placement_confirm_home else R.string.vpn_placement_confirm_relay),
            message = stringResource(R.string.vpn_placement_confirm_message),
            confirm = stringResource(R.string.vpn_placement_move),
            cancel = stringResource(R.string.vpn_cancel),
            onConfirm = {
                confirming = false
                move.move(server, toRelay = !onRelay)
            },
            onCancel = { confirming = false },
        )
    }
}

@Composable
private fun PlacementRows(onRelay: Boolean, moving: Boolean, onMove: () -> Unit) {
    GroupedSection(
        header = stringResource(R.string.vpn_placement_header),
        note = stringResource(R.string.vpn_placement_note),
        footer = stringResource(if (onRelay) R.string.vpn_placement_footer_relay else R.string.vpn_placement_footer_home),
    ) {
        ValueRow(
            title = stringResource(R.string.vpn_placement_runs_on),
            value = stringResource(if (onRelay) R.string.vpn_placement_vps else R.string.vpn_placement_home),
            onClick = null,
        )
        ActionRow(
            text = stringResource(if (onRelay) R.string.vpn_placement_move_home else R.string.vpn_placement_move_relay),
            enabled = !moving,
            onClick = onMove,
            showDivider = false,
        )
    }
}

/** The move's progress, notes and outcome */
@Composable
private fun MoveProgress(state: VPNMoveState, onClose: () -> Unit) {
    GroupedSection(header = state.title, footer = state.errorMessage) {
        GroupedRow(showDivider = !state.isRunning) {
            Column(Modifier.padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                state.progress?.let { MoveLine(it, Gryonix.colors.label) }
                state.log.forEach { MoveLine(it, Gryonix.colors.secondaryLabel) }
            }
        }
        if (!state.isRunning) ActionRow(text = stringResource(R.string.close), onClick = onClose, showDivider = false)
    }
}

@Composable
private fun MoveLine(text: String, color: androidx.compose.ui.graphics.Color) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = color)
}
