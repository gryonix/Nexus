package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.terminal.TerminalScriptQueue
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.shell.AppTab
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.SavedScript
import com.skaymer.gryonixnexus.servercontrol.SavedScriptList
import kotlinx.coroutines.launch
import kotlin.time.Duration.Companion.seconds

private enum class RunMode { TERMINAL, OUTPUT }

/** Run a script on a chosen server */
@Composable
fun ScriptRunSheet(script: SavedScript, onEdit: () -> Unit, onClose: () -> Unit) {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val servers by app.fleet.deployments.collectAsState()
    val scope = rememberCoroutineScope()
    var pending by remember { mutableStateOf<Pair<Deployment, RunMode>?>(null) }
    var output by remember { mutableStateOf<String?>(null) }
    val failedText = stringResource(R.string.scripts_failed)
    val available = servers.filter { script.appliesTo(it.id) }
    IOSSheet(title = script.name, onClose = onClose, closeLabel = stringResource(R.string.close)) {
        GroupedSection { ActionRow(stringResource(R.string.scripts_edit_action), onEdit, showDivider = false) }
        available.forEach { server ->
            GroupedSection(header = server.name) {
                ActionRow(stringResource(R.string.scripts_run_terminal), { pending = server to RunMode.TERMINAL })
                ActionRow(stringResource(R.string.scripts_run_output), { pending = server to RunMode.OUTPUT }, showDivider = false)
            }
        }
    }
    pending?.let { (server, mode) ->
        ScriptConfirm(script, server, onCancel = { pending = null }) {
            pending = null
            if (mode == RunMode.TERMINAL) {
                TerminalScriptQueue.queue(server.id, script.terminalInput)
                app.navigator.show(AppTab.TERMINAL)
                onClose()
            } else {
                scope.launch {
                    output = runCatching {
                        val result = app.sshRunner(server).run(script.execCommand, SSHHostID.VPS, 60.seconds)
                        (result.stdout + result.stderr).ifBlank { "(exit ${result.exitCode})" }
                    }.getOrElse { it.message ?: failedText }
                }
            }
        }
    }
    output?.let { text ->
        IOSAlert(
            title = stringResource(R.string.scripts_output),
            onDismiss = { output = null },
            actions = listOf(AlertAction(stringResource(R.string.close), preferred = true, onSelect = { output = null })),
            content = {
                Text(text, style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    color = Gryonix.colors.label,
                    modifier = Modifier.heightIn(max = 320.dp).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp))
            },
        )
    }
}

@Composable
private fun ScriptConfirm(script: SavedScript, server: Deployment, onCancel: () -> Unit, onRun: () -> Unit) {
    IOSAlert(
        title = stringResource(R.string.scripts_confirm_title, server.name),
        onDismiss = onCancel,
        actions = listOf(
            AlertAction(stringResource(R.string.access_cancel), onSelect = onCancel),
            AlertAction(stringResource(R.string.scripts_run), preferred = true, onSelect = onRun),
        ),
        content = {
            Text(script.body, style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                color = Gryonix.colors.label,
                modifier = Modifier.heightIn(max = 320.dp).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp))
        },
    )
}
