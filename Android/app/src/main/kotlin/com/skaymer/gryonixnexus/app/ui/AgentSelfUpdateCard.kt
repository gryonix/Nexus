package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Download
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.agent.AgentSelfUpdateViewModel
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.TileAction
import com.skaymer.gryonixnexus.app.ui.design.TileActionGroup
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.servercontrol.Deployment

@Composable
fun AgentSelfUpdateCard(
    deployment: Deployment,
    selfUpdate: AgentSelfUpdateViewModel,
) {
    val state by selfUpdate.state.collectAsState()
    val status = state.status ?: return
    GroupedSection(header = stringResource(R.string.agent_auto_update_header)) {
        ToggleRow(
            title = stringResource(R.string.agent_auto_update_toggle),
            checked = status.auto_update,
            onCheckedChange = { selfUpdate.setAutoUpdate(deployment, it) },
            showDivider = false,
            infoNote = stringResource(R.string.agent_auto_update_note),
        )
    }
    if (!status.update_available) return
    var confirming by remember(deployment.id) { mutableStateOf(false) }

    Column(verticalArrangement = GroupedSpacing) {
        GroupedSection(header = stringResource(R.string.agent_self_update_header)) {
            ValueRow(
                title = stringResource(R.string.agent_self_update_available, status.available_version),
                value = null,
                onClick = null,
            )
        }
        if (state.isApplying) {
            Column(
                Modifier.fillMaxWidth().padding(horizontal = Metrics.listInset),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                state.progress?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall, color = Gryonix.colors.secondaryLabel, textAlign = TextAlign.Center)
                }
            }
        } else {
            TileActionGroup(
                listOf(
                    TileAction(
                        title = stringResource(R.string.agent_self_update_action),
                        icon = Icons.Filled.Download,
                        onClick = { confirming = true },
                    )
                ),
                Modifier.padding(horizontal = Metrics.listInset),
            )
        }
        state.errorMessage?.let { error ->
            Text(
                error,
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.danger,
                modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
            )
        }
    }

    if (confirming) {
        IOSAlert(
            title = stringResource(R.string.agent_self_update_confirm_title),
            onDismiss = { confirming = false },
            actions = listOf(
                AlertAction(stringResource(R.string.agent_self_update_cancel), onSelect = { confirming = false }),
                AlertAction(
                    stringResource(R.string.agent_self_update_action),
                    preferred = true,
                    onSelect = {
                        confirming = false
                        selfUpdate.apply(deployment)
                    },
                ),
            ),
        ) {
            Text(
                stringResource(R.string.agent_self_update_confirm_message, status.available_version),
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
            )
        }
    }
}
