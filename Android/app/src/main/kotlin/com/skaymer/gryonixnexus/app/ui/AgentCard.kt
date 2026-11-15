package com.skaymer.gryonixnexus.app.ui

import androidx.compose.material.icons.outlined.Delete
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

private val NO_HEALTH = kotlinx.coroutines.flow.MutableStateFlow<Map<String, gryonixnexusd.v1.AgentHealth>>(emptyMap())

@Composable
fun AgentCard(
    deployment: Deployment,
    install: AgentInstallViewModel,
    onInstalled: () -> Unit,
    removal: AgentRemoval? = null,
    /** Rows between the check result and reinstalling */
    extraRows: (@Composable () -> Unit)? = null,
) {
    val state by install.state.collectAsState()
    val check by install.check.collectAsState()
    var running by remember(deployment.id) { mutableStateOf(false) }
    var confirmingRemoval by remember(deployment.id) { mutableStateOf(false) }
    var confirmingReinstall by remember(deployment.id) { mutableStateOf(false) }

    val homeDoors = (LocalContext.current.applicationContext as? GryonixApplication)?.homeDoors
    val healths by (homeDoors?.health ?: NO_HEALTH).collectAsState()
    val health = healths[deployment.id.toString()]
    LaunchedEffect(deployment.id) { homeDoors?.load(deployment) }
    LaunchedEffect(deployment.id) { if (deployment.usesAgent && check.answer == null) install.check(deployment) }
    GroupedSection(
        header = stringResource(R.string.agent),
        note = stringResource(if (deployment.usesAgent) R.string.agent_note_installed else R.string.agent_note_missing),
    ) {
        AgentVersionRow(deployment, check.answer)
        if (deployment.usesAgent && health != null) AgentHealthRows(health)
        AgentSourceRow()
        AgentTiles(
            deployment = deployment,
            checking = check.isChecking,
            onCheck = { install.check(deployment) },
            onInstall = {
                running = true
                install.install(deployment)
            },
        )
        check.answer?.let { AgentCheckRow(it) }
        extraRows?.invoke()
        if (deployment.usesAgent) {
            IconActionRow(Icons.Filled.Refresh, stringResource(R.string.agent_reinstall),
                showDivider = removal != null) { confirmingReinstall = true }
        }
        if (deployment.usesAgent && removal != null) {
            IconActionRow(Icons.Outlined.Delete, stringResource(R.string.agent_remove), danger = true,
                showDivider = false) { confirmingRemoval = true }
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
