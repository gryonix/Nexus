package com.skaymer.gryonixnexus.app.ui

import androidx.compose.ui.Alignment
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.ArrowCircleDown
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.MonitorHeart
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.agent.AgentPresence
import com.skaymer.gryonixnexus.app.agent.AgentSource
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.InfoNoteButton
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.TileAction
import com.skaymer.gryonixnexus.app.ui.design.TileActionGroup
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** "Agent" and the version the server reports */
@Composable
fun AgentVersionRow(deployment: Deployment, answer: AgentPresence.Answer?) {
    GroupedRow(
        trailing = {
            if (deployment.usesAgent) {
                Text(
                    (answer as? AgentPresence.Answer.Installed)?.version ?: stringResource(R.string.agent_installed),
                    style = MaterialTheme.typography.bodyLarge,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
        },
    ) {
        RowLabel(stringResource(if (deployment.usesAgent) R.string.agent else R.string.agent_not_installed))
    }
}

/** Which sources an install or update uses */
@Composable
fun AgentSourceRow() {
    val store = (LocalContext.current.applicationContext as GryonixApplication).store
    store.revision.collectAsState().value
    val chosen = AgentSource.named(store.string(AgentSource.SETTINGS_KEY))
    var open by remember { mutableStateOf(false) }
    GroupedRow(
        onClick = { open = true },
        trailing = {
            Box {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(sourceTitle(chosen), style = MaterialTheme.typography.bodyLarge, color = Gryonix.colors.secondaryLabel)
                    com.skaymer.gryonixnexus.app.ui.design.PopupChevron()
                }
                DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                    AgentSource.entries.forEach { source ->
                        DropdownMenuItem(
                            text = { Text(sourceTitle(source)) },
                            onClick = {
                                open = false
                                store.setString(AgentSource.SETTINGS_KEY, source.raw)
                            },
                        )
                    }
                }
            }
            InfoNoteButton(title = stringResource(R.string.agent_sources_title), note = sourcesNote())
        },
    ) { RowLabel(stringResource(R.string.agent_sources)) }
}

@Composable
private fun sourcesNote(): String = buildString {
    append(stringResource(R.string.agent_sources_note))
    AgentSource.entries.forEach { source ->
        append("\n\n").append(sourceTitle(source)).append("\n").append(sourceSummary(source))
    }
}

@Composable
private fun sourceTitle(source: AgentSource): String = stringResource(
    when (source) {
        AgentSource.APP -> R.string.agent_source_app
        AgentSource.REPOSITORY_MAIN -> R.string.agent_source_main
        AgentSource.REPOSITORY_BETA -> R.string.agent_source_beta
        AgentSource.REPOSITORY_WIP -> R.string.agent_source_wip
    }
)

@Composable
private fun sourceSummary(source: AgentSource): String = stringResource(
    when (source) {
        AgentSource.APP -> R.string.agent_source_app_summary
        AgentSource.REPOSITORY_MAIN -> R.string.agent_source_main_summary
        AgentSource.REPOSITORY_BETA -> R.string.agent_source_beta_summary
        AgentSource.REPOSITORY_WIP -> R.string.agent_source_wip_summary
    }
)

/** Check, install or update, and copy the command */
@Composable
fun AgentTiles(deployment: Deployment, checking: Boolean, onCheck: () -> Unit, onInstall: () -> Unit) {
    val clipboard = LocalClipboardManager.current
    val store = (LocalContext.current.applicationContext as GryonixApplication).store
    var copied by remember { mutableStateOf(false) }
    GroupedRow(showDivider = copied) {
        TileActionGroup(
            listOf(
                TileAction(stringResource(if (checking) R.string.agent_checking else R.string.agent_check),
                    Icons.Outlined.MonitorHeart, onCheck, enabled = !checking),
                TileAction(stringResource(if (deployment.usesAgent) R.string.agent_update else R.string.agent_install),
                    Icons.Outlined.ArrowCircleDown, onInstall, enabled = !checking),
                TileAction(stringResource(if (deployment.usesAgent) R.string.agent_copy_update else R.string.agent_copy_install),
                    Icons.Outlined.ContentCopy, {
                        clipboard.setText(AnnotatedString(installCommand(deployment, AgentSource.named(store.string(AgentSource.SETTINGS_KEY)))))
                        copied = true
                    }),
            ),
            Modifier.weight(1f),
        )
    }
    if (copied) {
        GroupedRow {
            Text(stringResource(R.string.agent_copied), style = MaterialTheme.typography.bodySmall, color = Gryonix.colors.secondaryLabel)
        }
    }
}

/** What the last check found */
@Composable
fun AgentCheckRow(answer: AgentPresence.Answer) {
    val failed = answer is AgentPresence.Answer.Unreachable
    GroupedRow(
        leading = {
            Icon(
                if (failed) Icons.Filled.Warning else Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = if (failed) Gryonix.colors.warning else Gryonix.colors.success,
                modifier = Modifier.size(18.dp),
            )
        },
    ) {
        Text(
            when (answer) {
                is AgentPresence.Answer.Installed -> stringResource(R.string.agent_answers, answer.version)
                AgentPresence.Answer.InstalledUnknownVersion -> stringResource(R.string.agent_answers_no_version)
                is AgentPresence.Answer.Unreachable -> answer.reason
            },
            style = MaterialTheme.typography.bodySmall,
            color = Gryonix.colors.label,
        )
    }
}

/** A row with an icon that does something */
@Composable
fun IconActionRow(
    icon: ImageVector,
    title: String,
    danger: Boolean = false,
    showDivider: Boolean = true,
    onClick: () -> Unit,
) {
    val tint = if (danger) Gryonix.colors.danger else Gryonix.colors.accent
    GroupedRow(
        onClick = onClick,
        showDivider = showDivider,
        leading = { Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(22.dp)) },
    ) {
        Text(title, style = MaterialTheme.typography.bodyLarge, color = tint)
    }
}

/** The command that installs or updates the agent by hand */
fun installCommand(deployment: Deployment, source: AgentSource): String {
    val target = "${deployment.entry.user}@${deployment.entry.host}"
    val port = if (deployment.entry.port == 22) "" else " -p ${deployment.entry.port}"
    val branch = source.branch
        ?: return "tar -czf - Agent | ssh$port $target 'tar -xzf - -C /root && cd /root/Agent && bash bootstrap/install-agent.sh'"
    return "ssh$port $target 'curl -fsSL https://codeload.github.com/${AgentSource.REPOSITORY}/tar.gz/refs/heads/$branch" +
        " | tar -xz && cd */Agent && bash bootstrap/install-agent.sh'"
}
