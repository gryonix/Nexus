package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.terminal.SavedTerminalSession
import com.skaymer.gryonixnexus.app.terminal.SavedTerminalSessionsStore
import com.skaymer.gryonixnexus.app.terminal.TerminalProfile
import com.skaymer.gryonixnexus.app.terminal.TerminalRestore
import com.skaymer.gryonixnexus.app.terminal.TerminalSessions
import com.skaymer.gryonixnexus.app.terminal.TerminalShells
import com.skaymer.gryonixnexus.app.terminal.TerminalTmux
import com.skaymer.gryonixnexus.app.terminal.TerminalViewModel
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** One server's shell tabs: which is shown, open, close. */
class ShellTabs(
    private val deployment: Deployment,
    private val sessions: TerminalSessions,
    private val saved: SavedTerminalSessionsStore?,
    private val notices: (TerminalViewModel.Notice) -> String,
    /** Machine names by node id, for tab titles */
    private val machineNames: Map<String, String>,
) {
    var shownID by mutableStateOf<String?>(null)
        private set
    var listing by mutableStateOf(false)
        private set

    private val shells: TerminalShells get() = sessions.shells

    /** Opens a login as a tab, or shows its tab */
    fun open(profile: TerminalProfile) {
        obtain(profile)
        saved?.update { it.open(SavedTerminalSession(profile.id, deployment.id, profile.nodeID, profile.username)) }
        shownID = profile.id
        listing = false
    }

    fun select(profileID: String) {
        saved?.update { it.select(profileID) }
        shownID = profileID
        listing = false
    }

    fun close(profileID: String) {
        shells.close(profileID)
        saved?.update { it.close(profileID) }
        if (shownID == profileID) shownID = shells.of(deployment.id).lastOrNull()?.profileID
    }

    fun showList() {
        listing = true
    }

    /** Brings back last run's tabs; background ones dial at once */
    fun restore(known: List<TerminalProfile>) {
        val records = saved?.load() ?: return
        val (back, shown) = TerminalRestore.plan(records, deployment.id, known)
        records.records.filter { it.deploymentID == deployment.id && back.none { p -> p.id == it.profileID } }
            .forEach { gone -> saved.update { it.close(gone.profileID) } }
        for (profile in back) {
            val (shell, fresh) = obtain(profile)
            if (fresh && profile.id != shown) {
                shell.terminal.open(sessions.routes(deployment, nodeOf(deployment, profile)),
                    sessions.login(deployment, profile), BACKGROUND_COLUMNS, BACKGROUND_ROWS)
            }
        }
        if (shownID == null) shownID = shown ?: shells.of(deployment.id).lastOrNull()?.profileID
    }

    private fun obtain(profile: TerminalProfile): Pair<TerminalShells.Shell, Boolean> {
        val node = nodeOf(deployment, profile)
        val machine = machineNames[node.id.toString()].orEmpty()
        val title = if (deployment.isMultiHost && machine.isNotEmpty()) "${profile.username} · $machine" else profile.username
        val startup = if (profile.keepAliveWithTmux) TerminalTmux.launchCommand(profile.id).toByteArray() else null
        return shells.obtain(profile.id, deployment.id, title) { scope ->
            sessions.shellModel(scope, deployment, node, startup, notices)
        }
    }

    private companion object {
        const val BACKGROUND_COLUMNS = 80
        const val BACKGROUND_ROWS = 24
    }
}

/** Tab state for a server, restored once from last run */
@Composable
fun rememberShellTabs(
    deployment: Deployment,
    sessions: TerminalSessions,
    saved: SavedTerminalSessionsStore?,
    known: () -> List<TerminalProfile>,
): ShellTabs {
    val notices = terminalNotices()
    val names = deployment.nodes.associate { it.id.toString() to machineName(deployment, it) }
    val tabs = remember(deployment.id) { ShellTabs(deployment, sessions, saved, notices, names) }
    LaunchedEffect(deployment.id) { tabs.restore(known()) }
    return tabs
}

/** The open shells of one server, as tabs */
@Composable
fun TerminalTabStrip(
    shells: List<TerminalShells.Shell>,
    shownID: String,
    onSelect: (String) -> Unit,
    onClose: (String) -> Unit,
    onNew: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().background(Gryonix.colors.groupedBackground).padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier.weight(1f).horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            shells.forEach { shell -> ShellTab(shell, shell.profileID == shownID, onSelect, onClose) }
        }
        IconButton(onClick = onNew, modifier = Modifier.size(36.dp)) {
            Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.terminal_new_session), tint = Gryonix.colors.accent)
        }
    }
}

@Composable
private fun ShellTab(
    shell: TerminalShells.Shell,
    selected: Boolean,
    onSelect: (String) -> Unit,
    onClose: (String) -> Unit,
) {
    val state by shell.terminal.state.collectAsState()
    val tint = if (selected) Gryonix.colors.accent else Gryonix.colors.secondaryLabel
    Row(
        Modifier
            .clip(RoundedCornerShape(8.dp))
            .background(if (selected) Gryonix.colors.accent.copy(alpha = 0.14f) else Gryonix.colors.cardBackground)
            .clickable { onSelect(shell.profileID) }
            .padding(start = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            (if (state.isOpen) "● " else "○ ") + shell.title,
            style = MaterialTheme.typography.bodyMedium,
            color = tint,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        IconButton(onClick = { onClose(shell.profileID) }, modifier = Modifier.size(32.dp)) {
            Icon(
                Icons.Filled.Close,
                contentDescription = stringResource(R.string.terminal_close_session),
                tint = tint,
                modifier = Modifier.size(16.dp),
            )
        }
    }
}

/** Shells already open on this server, to switch back to */
@Composable
fun OpenShellsSection(shells: List<TerminalShells.Shell>, onSelect: (String) -> Unit) {
    GroupedSection(header = stringResource(R.string.terminal_open_sessions)) {
        shells.forEach { shell ->
            val state by shell.terminal.state.collectAsState()
            GroupedRow(onClick = { onSelect(shell.profileID) }, showDivider = shell != shells.last()) {
                RowLabel(shell.title, stringResource(if (state.isOpen) R.string.terminal_session_live else R.string.terminal_session_idle))
            }
        }
    }
}
