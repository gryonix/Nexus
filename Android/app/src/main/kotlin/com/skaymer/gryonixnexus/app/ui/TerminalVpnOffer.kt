package com.skaymer.gryonixnexus.app.ui

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.terminal.TerminalVpn
import com.skaymer.gryonixnexus.app.terminal.TerminalViewModel
import com.skaymer.gryonixnexus.app.vpn.LastTunnel
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.transport.TerminalEndpoint
import kotlinx.coroutines.launch

/** Turns the VPN on when no route answered, then redials */
@Composable
fun TerminalVpnOffer(
    vpn: TerminalVpn,
    deployment: Deployment,
    routes: List<TerminalEndpoint>,
    terminal: TerminalViewModel,
) {
    val state by terminal.state.collectAsState()
    val tunnel by vpn.state.collectAsState()
    val scope = rememberCoroutineScope()
    var working by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    val offer = remember(state.noRouteAnswered, tunnel) {
        if (state.noRouteAnswered) vpn.offer(deployment, routes) else null
    }

    fun bringUp(profile: LastTunnel.Profile) {
        scope.launch {
            working = true
            failed = false
            val up = vpn.connect(profile)
            working = false
            failed = !up
            if (up) terminal.retry()
        }
    }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == Activity.RESULT_OK) offer?.let(::bringUp)
    }

    if (offer == null && !failed) return
    Column(Modifier.padding(horizontal = 8.dp)) {
        if (failed) {
            Text(
                stringResource(R.string.terminal_vpn_failed),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
        offer?.let { profile ->
            TextButton(
                enabled = !working,
                onClick = {
                    val ask = vpn.permissionRequest()
                    if (ask != null) permission.launch(ask) else bringUp(profile)
                },
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (working) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    Text(stringResource(R.string.terminal_vpn_reconnect))
                }
            }
        }
    }
}
