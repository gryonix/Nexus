package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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

@Composable
fun RelayStatusCard(deployment: Deployment, relay: RelayStatusViewModel) {
    if (!RelayStatusViewModel.offered(deployment)) return
    val state by relay.state.collectAsState()

    GroupedSection(header = stringResource(R.string.relay_title)) {
        StatusRow(
            title = stringResource(R.string.relay_forwarding),
            read = state.forwarding,
            healthy = { it },
            text = { stringResource(if (it) R.string.relay_on else R.string.relay_off) },
        )
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
        ActionRow(
            text = stringResource(R.string.relay_check),
            onClick = { relay.refresh(deployment) },
            showDivider = false,
        )
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
