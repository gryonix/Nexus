package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.InfoNoteButton
import androidx.compose.material3.Icon
import androidx.compose.material.icons.outlined.SyncAlt
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.Icons
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.RelayRead
import com.skaymer.gryonixnexus.app.servers.RelayStatusViewModel
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.PingResult

/** How the server is reached: routing, its machines, its DNS */
@Composable
fun ConnectionCard(
    deployment: Deployment,
    relay: RelayStatusViewModel,
    onServers: () -> Unit,
    onDynamicDNS: (() -> Unit)?,
) {
    GroupedSection(header = stringResource(R.string.connection_header)) {
        if (RelayStatusViewModel.offered(deployment)) RelayRows(deployment, relay)
        NavRow(Icons.Outlined.Dns, stringResource(R.string.agent_servers), onServers, showDivider = onDynamicDNS != null)
        onDynamicDNS?.let {
            GroupedRow(
                onClick = it,
                showDivider = false,
                leading = { Icon(Icons.Outlined.Sync, contentDescription = null, modifier = Modifier.size(22.dp)) },
                trailing = {
                    InfoNoteButton(title = stringResource(R.string.ddns_title), note = stringResource(R.string.ddns_note))
                    DisclosureChevron()
                },
            ) { RowLabel(stringResource(R.string.ddns_title)) }
        }
    }
    RelayConfiguringAlert(relay)
}

@Composable
private fun RelayRows(deployment: Deployment, relay: RelayStatusViewModel) {
    LaunchedEffect(deployment.id) { relay.refresh(deployment) }
    val state by relay.state.collectAsState()
    StatusRow(
        title = stringResource(R.string.relay_forwarding),
        read = state.forwarding,
        healthy = { it },
        text = { stringResource(if (it) R.string.relay_on else R.string.relay_off) },
    )
    if (deployment.usesAgent) {
        GroupedRow(
            onClick = { relay.configure(deployment) },
            leading = { Icon(Icons.Outlined.SyncAlt, contentDescription = null, modifier = Modifier.size(22.dp)) },
            trailing = {
                InfoNoteButton(title = stringResource(R.string.relay_configure), note = stringResource(R.string.relay_configure_note))
            },
        ) {
            Text(stringResource(R.string.relay_configure), style = MaterialTheme.typography.bodyLarge,
                color = Gryonix.colors.accent, modifier = Modifier.weight(1f))
        }
    }
    StatusRow(
        title = stringResource(R.string.relay_self),
        read = state.selfPing,
        healthy = { it.isAlive },
        text = { pingWords(it) },
    )
    StatusRow(
        title = stringResource(R.string.relay_tunnel),
        read = state.tunnelPing,
        healthy = { it.isAlive },
        text = { pingWords(it) },
    )
}

/** Progress, then the relay's notes or why it failed */
@Composable
private fun RelayConfiguringAlert(relay: RelayStatusViewModel) {
    val configuring = relay.state.collectAsState().value.configuring
    if (configuring is RelayRead.Idle) return
    IOSAlert(
        title = stringResource(R.string.relay_configuring),
        message = when (configuring) {
            is RelayRead.Loaded -> (listOf(stringResource(R.string.relay_configured)) + configuring.value).joinToString("\n")
            is RelayRead.Failed -> configuring.message
            else -> null
        },
        onDismiss = { if (configuring !is RelayRead.Loading) relay.dismissConfiguring() },
        actions = listOf(
            AlertAction(
                stringResource(R.string.containers_done),
                preferred = true,
                enabled = configuring !is RelayRead.Loading,
                onSelect = { relay.dismissConfiguring() },
            ),
        ),
    ) {
        if (configuring is RelayRead.Loading) {
            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = Gryonix.colors.tertiaryLabel)
        }
    }
}

@Composable
private fun pingWords(result: PingResult): String = stringResource(
    if (result.isAlive) R.string.relay_responding else R.string.relay_not_responding
)

@Composable
private fun <T> StatusRow(
    title: String,
    read: RelayRead<T>,
    healthy: (T) -> Boolean,
    text: @Composable (T) -> String,
) {
    GroupedRow(
        trailing = {
            when (read) {
                is RelayRead.Idle -> Unit
                is RelayRead.Loading -> CircularProgressIndicator(
                    Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color = Gryonix.colors.secondaryLabel,
                )
                is RelayRead.Failed -> Text(
                    read.message,
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.danger,
                )
                is RelayRead.Loaded<T> -> Text(
                    text(read.value),
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (healthy(read.value)) Color(0xFF34C759) else Gryonix.colors.danger,
                )
            }
        },
    ) {
        RowLabel(title)
    }
}
