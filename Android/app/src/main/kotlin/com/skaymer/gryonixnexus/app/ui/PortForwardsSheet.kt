package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.AlertFields
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.FormSheet
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.PortForward
import com.skaymer.gryonixnexus.servercontrol.PortForwardState
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.UUID

/** Saved port forwards of one server */
@Composable
fun PortForwardsSheet(deployment: Deployment, onClose: () -> Unit) {
    val manager = (LocalContext.current.applicationContext as GryonixApplication).portForwards
    val all by manager.forwards.collectAsState()
    val states by manager.states.collectAsState()
    val scope = rememberCoroutineScope()
    var editing by remember { mutableStateOf<PortForward?>(null) }
    LaunchedEffect(Unit) { while (true) { manager.refreshCounts(); delay(1000) } }
    val mine = all.filter { it.deploymentID == deployment.id }
    IOSSheet(
        title = stringResource(R.string.port_forwarding_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.close),
    ) {
        GroupedSection(footer = stringResource(R.string.port_forwarding_footer)) {
            if (mine.isEmpty()) {
                GroupedRow(showDivider = false) {
                    Text(stringResource(R.string.port_forwarding_empty), color = Gryonix.colors.secondaryLabel)
                }
            }
            mine.forEach { forward ->
                val state = states[forward.id] ?: PortForwardState.Stopped
                GroupedRow(showDivider = forward != mine.last(), onClick = { editing = forward }) {
                    RowLabel(forward.title, forward.summary + "\n" + statusText(state))
                    PlainButton(
                        text = stringResource(if (state.isActive) R.string.port_forwarding_stop else R.string.port_forwarding_start),
                        onClick = {
                            if (state.isActive) manager.stop(forward) else scope.launch { manager.start(forward, deployment) }
                        },
                    )
                }
            }
        }
        GroupedSection {
            ActionRow(stringResource(R.string.port_forwarding_add), showDivider = false, onClick = {
                editing = PortForward(UUID.randomUUID().toString(), deployment.id, localPort = 8080, remotePort = 80)
            })
        }
    }
    editing?.let { forward ->
        PortForwardEditor(forward, all, onSave = { manager.save(it); editing = null },
            onDelete = { manager.delete(it); editing = null }, onCancel = { editing = null })
    }
}

@Composable
private fun statusText(state: PortForwardState): String = when (state) {
    PortForwardState.Stopped -> stringResource(R.string.port_forwarding_stopped)
    PortForwardState.Starting -> stringResource(R.string.port_forwarding_starting)
    is PortForwardState.Running -> stringResource(R.string.port_forwarding_running, state.connections)
    is PortForwardState.Failed -> state.message
}

@Composable
private fun PortForwardEditor(
    forward: PortForward,
    all: List<PortForward>,
    onSave: (PortForward) -> Unit,
    onDelete: (PortForward) -> Unit,
    onCancel: () -> Unit,
) {
    var name by remember { mutableStateOf(forward.name) }
    var local by remember { mutableStateOf(forward.localPort.toString()) }
    var host by remember { mutableStateOf(forward.remoteHost) }
    var remote by remember { mutableStateOf(forward.remotePort.toString()) }
    val draft = forward.copy(name = name, localPort = local.toIntOrNull() ?: 0, remoteHost = host,
        remotePort = remote.toIntOrNull() ?: 0)
    val valid = draft.problems(all).isEmpty()
    val actions = buildList {
        add(AlertAction(stringResource(R.string.access_cancel), onSelect = onCancel))
        if (all.any { it.id == forward.id }) {
            add(AlertAction(stringResource(R.string.port_forwarding_delete), destructive = true, onSelect = { onDelete(forward) }))
        }
        add(AlertAction(stringResource(R.string.port_forwarding_save), enabled = valid, preferred = true,
            onSelect = { onSave(draft) }))
    }
    FormSheet(
        title = stringResource(R.string.port_forwarding_edit),
        onDismiss = onCancel,
        actions = actions,
        content = { EditorFields(name, local, host, remote, { name = it }, { local = it }, { host = it }, { remote = it }) },
    )
}

@Composable
private fun androidx.compose.foundation.layout.ColumnScope.EditorFields(
    name: String, local: String, host: String, remote: String,
    onName: (String) -> Unit, onLocal: (String) -> Unit, onHost: (String) -> Unit, onRemote: (String) -> Unit,
) {
    val numbers = KeyboardOptions(keyboardType = KeyboardType.Number)
    AlertFields {
        OutlinedTextField(name, onName, label = { Text(stringResource(R.string.port_forwarding_name)) })
        OutlinedTextField(local, onLocal, label = { Text(stringResource(R.string.port_forwarding_local_port)) },
            keyboardOptions = numbers)
        OutlinedTextField(host, onHost, label = { Text(stringResource(R.string.port_forwarding_remote_host)) })
        OutlinedTextField(remote, onRemote, label = { Text(stringResource(R.string.port_forwarding_remote_port)) },
            keyboardOptions = numbers)
    }
}
