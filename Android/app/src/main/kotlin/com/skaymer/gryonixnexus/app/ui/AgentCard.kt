package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import com.skaymer.gryonixnexus.app.GryonixApplication
import androidx.compose.foundation.shape.RoundedCornerShape
import com.skaymer.gryonixnexus.app.agent.AgentBootstrapOperations
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.TileAction
import com.skaymer.gryonixnexus.app.ui.design.TileActionGroup
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.style.TextAlign
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.agent.AgentInstallViewModel
import com.skaymer.gryonixnexus.app.agent.AgentPresence
import com.skaymer.gryonixnexus.app.agent.AgentRemoval
import com.skaymer.gryonixnexus.servercontrol.Deployment

@Composable
fun AgentCard(
    deployment: Deployment,
    install: AgentInstallViewModel,
    onInstalled: () -> Unit,
    removal: AgentRemoval? = null,
) {
    val state by install.state.collectAsState()
    val check by install.check.collectAsState()
    var running by remember(deployment.id) { mutableStateOf(false) }
    var confirmingRemoval by remember(deployment.id) { mutableStateOf(false) }
    var confirmingReinstall by remember(deployment.id) { mutableStateOf(false) }

    Column(verticalArrangement = GroupedSpacing) {
        GroupedSection(header = stringResource(R.string.agent)) {
            ValueRow(
                title = stringResource(
                    if (deployment.usesAgent) R.string.agent_installed
                    else R.string.agent_not_installed
                ),
                value = null,
                onClick = null,
                leading = {
                    StatusDot(
                        if (deployment.usesAgent) Gryonix.colors.success
                        else Gryonix.colors.tertiaryLabel
                    )
                },
            )
        }
        TileActionGroup(
            listOf(
                TileAction(
                    title = stringResource(
                        if (check.isChecking) R.string.agent_checking else R.string.agent_check
                    ),
                    icon = Icons.Filled.Search,
                    onClick = { install.check(deployment) },
                ),
                TileAction(
                    title = stringResource(
                        if (deployment.usesAgent) R.string.agent_update
                        else R.string.agent_install
                    ),
                    icon = Icons.Filled.Download,
                    onClick = {
                        running = true
                        install.install(deployment)
                    },
                )
            ) + listOfNotNull(
                TileAction(
                    title = stringResource(R.string.agent_reinstall),
                    icon = Icons.Filled.Refresh,
                    onClick = { confirmingReinstall = true },
                ).takeIf { deployment.usesAgent },
                removal?.takeIf { deployment.usesAgent }?.let {
                    TileAction(
                        title = stringResource(R.string.agent_remove),
                        icon = Icons.Filled.Delete,
                        onClick = { confirmingRemoval = true },
                        danger = true,
                    )
                },
            ),
            Modifier.padding(horizontal = Metrics.listInset),
        )
        check.answer?.let { answer ->
            Text(
                when (answer) {
                    is AgentPresence.Answer.Installed ->
                        stringResource(R.string.agent_answers, answer.version)
                    AgentPresence.Answer.InstalledUnknownVersion ->
                        stringResource(R.string.agent_answers_no_version)
                    is AgentPresence.Answer.Unreachable -> answer.reason
                },
                style = MaterialTheme.typography.bodySmall,
                color = if (answer is AgentPresence.Answer.Unreachable) Gryonix.colors.danger
                else Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
            )
        }
    }

    if (confirmingRemoval && removal != null) {
        ConfirmAlert(
            title = stringResource(R.string.agent_remove_question),
            message = stringResource(R.string.agent_remove_message),
            confirm = stringResource(R.string.agent_remove_confirm),
            destructive = true,
            onConfirm = {
                confirmingRemoval = false
                removal.remove(deployment)
            },
            onCancel = { confirmingRemoval = false },
        )
    }
    if (confirmingReinstall) {
        ConfirmAlert(
            title = stringResource(R.string.agent_reinstall_question),
            message = stringResource(R.string.agent_reinstall_message),
            confirm = stringResource(R.string.agent_reinstall_confirm),
            onConfirm = {
                confirmingReinstall = false
                running = true
                install.install(deployment, reinstall = true)
            },
            onCancel = { confirmingReinstall = false },
        )
    }
    removal?.let { RemovalOutcomeAlert(it) }

    if (running) {
        IOSAlert(
            title = stringResource(R.string.agent_installing),
            onDismiss = { if (state.isFinished) { running = false; install.reset() } },
            actions = listOf(
                AlertAction(
                    stringResource(R.string.containers_done),
                    preferred = true,
                    enabled = state.isFinished,
                    onSelect = {
                        running = false
                        if (state.installedVersion != null) onInstalled()
                        install.reset()
                    },
                ),
            ),
        ) {
            Column(
                Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    state.errorMessage
                        ?: state.installedVersion?.let {
                            stringResource(R.string.agent_installed_version, it)
                        }
                        ?: state.phase,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (state.errorMessage != null) Gryonix.colors.danger
                    else Gryonix.colors.label,
                    textAlign = TextAlign.Center,
                )
                if (state.isRunning) {
                    CircularProgressIndicator(
                        Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = Gryonix.colors.tertiaryLabel,
                    )
                }
                if (state.log.isNotEmpty()) {
                    SelectionContainer {
                        Column(
                            Modifier.heightIn(max = 240.dp).verticalScroll(rememberScrollState())
                        ) {
                            Text(
                                state.log,
                                style = MaterialTheme.typography.bodySmall,
                                fontFamily = FontFamily.Monospace,
                                color = Gryonix.colors.secondaryLabel,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RemovalOutcomeAlert(removal: AgentRemoval) {
    val outcome = removal.state.collectAsState().value.outcome ?: return
    IOSAlert(
        title = stringResource(
            if (outcome is AgentRemoval.Outcome.Removed) R.string.actions_done else R.string.actions_error
        ),
        message = when (outcome) {
            AgentRemoval.Outcome.Removed -> stringResource(R.string.agent_removed)
            AgentRemoval.Outcome.TooOld -> stringResource(R.string.agent_remove_too_old)
            is AgentRemoval.Outcome.Failed -> outcome.message
        },
        onDismiss = { removal.clear() },
        actions = listOf(AlertAction(stringResource(R.string.actions_ok), preferred = true, onSelect = { removal.clear() })),
    )
}

@Composable
private fun StatusDot(color: Color) {
    Box(Modifier.size(10.dp).clip(CircleShape).background(color))
}

/** Offers to update servers running an older agent */
@Composable
fun AgentUpdateOfferDialog() {
    val model = (LocalContext.current.applicationContext as GryonixApplication).agentUpdateOffer
    val offer by model.offer.collectAsState()
    val progress by model.progress.collectAsState()
    LaunchedEffect(Unit) { model.checkOnLaunch() }
    offer?.let { current ->
        IOSAlert(
            title = stringResource(R.string.agent_update_title, current.version),
            message = stringResource(R.string.agent_update_note),
            onDismiss = { model.later() },
            actions = listOf(
                AlertAction(stringResource(R.string.agent_update_later), onSelect = { model.later() }),
                AlertAction(stringResource(R.string.agent_update_all), preferred = true, onSelect = { model.updateAll() }),
            ),
        ) {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                current.servers.forEach { server ->
                    Text(
                        "${server.deployment.name} — ${server.installed} → ${server.target}",
                        style = MaterialTheme.typography.bodyMedium,
                        color = Gryonix.colors.secondaryLabel,
                    )
                }
            }
        }
    }
    progress?.let { step ->
        val install = (LocalContext.current.applicationContext as GryonixApplication).agentInstall
        val state by install.state.collectAsState()
        IOSAlert(
            title = stringResource(R.string.agent_update_progress, step.server, step.index, step.total),
            message = state.errorMessage ?: state.phase,
            onDismiss = {},
            actions = emptyList(),
        ) {
            if (state.isRunning) {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = Gryonix.colors.tertiaryLabel)
            }
        }
    }
}
