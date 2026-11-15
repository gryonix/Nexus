package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.servers.DemoDeployments
import com.skaymer.gryonixnexus.app.servers.ServerRemoval
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.AlertFields
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** Where the removal dialog stands */
private sealed interface RemovalPhase {
    data object Choosing : RemovalPhase
    data object Working : RemovalPhase
    data class LastWayIn(val names: List<String>, val ids: Set<String>) : RemovalPhase
    data class Unreachable(val message: String) : RemovalPhase
    data class Failed(val names: List<String>) : RemovalPhase
}

/** Removing a server, optionally taking the app's access back */
@Composable
fun ServerRemovalDialog(deployment: Deployment, onRemoved: () -> Unit, onCancel: () -> Unit) {
    val removal = (LocalContext.current.applicationContext as GryonixApplication).serverRemoval
    val scope = rememberCoroutineScope()
    var phase by remember { mutableStateOf<RemovalPhase>(RemovalPhase.Choosing) }
    var revoke by remember { mutableStateOf(true) }
    val offersRevoke = !DemoDeployments.isDemoID(deployment.id)
    val finish = { kept: Set<String> ->
        phase = RemovalPhase.Working
        scope.launch {
            val failures = removal.revoke(deployment, kept)
            if (failures.isEmpty()) onRemoved() else phase = RemovalPhase.Failed(failures)
        }
        Unit
    }
    when (val current = phase) {
        RemovalPhase.Choosing -> RemovalChoice(deployment.name, offersRevoke, revoke, { revoke = it }, onCancel) {
            if (!revoke || !offersRevoke) onRemoved() else startCheck(scope, removal, deployment, { phase = it }, finish)
        }
        RemovalPhase.Working -> RemovalNote(stringResource(R.string.server_removal_working), null) {}
        is RemovalPhase.LastWayIn -> RemovalLastWayIn(current.names, keep = { finish(current.ids) }, removeAnyway = { finish(emptySet()) })
        is RemovalPhase.Unreachable -> RemovalNote(
            stringResource(R.string.server_removal_unreachable, current.message),
            stringResource(R.string.server_removal_app_only), onCancel = onCancel, onAction = onRemoved,
        )
        is RemovalPhase.Failed -> RemovalNote(
            stringResource(R.string.server_removal_failed, current.names.joinToString(", ")),
            stringResource(R.string.server_removal_done), onAction = onRemoved,
        )
    }
}

private fun startCheck(
    scope: CoroutineScope,
    removal: ServerRemoval,
    deployment: Deployment,
    setPhase: (RemovalPhase) -> Unit,
    finish: (Set<String>) -> Unit,
) {
    setPhase(RemovalPhase.Working)
    scope.launch {
        try {
            val last = removal.check(deployment).filter { it.check?.isLastWayIn == true }
            if (last.isEmpty()) finish(emptySet())
            else setPhase(RemovalPhase.LastWayIn(last.map { it.node.name.ifEmpty { deployment.name } }, last.map { it.node.id }.toSet()))
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            setPhase(RemovalPhase.Unreachable(failure.message ?: failure::class.simpleName.orEmpty()))
        }
    }
}

@Composable
private fun RemovalChoice(
    name: String,
    offersRevoke: Boolean,
    revoke: Boolean,
    onRevoke: (Boolean) -> Unit,
    onCancel: () -> Unit,
    onRemove: () -> Unit,
) {
    IOSAlert(
        title = stringResource(R.string.delete_server_title, name),
        message = stringResource(R.string.delete_server_message),
        onDismiss = onCancel,
        actions = listOf(
            AlertAction(stringResource(R.string.delete_server_cancel), onSelect = onCancel),
            AlertAction(stringResource(R.string.delete_server_confirm), destructive = true, onSelect = onRemove),
        ),
    ) {
        if (offersRevoke) {
            AlertFields {
                ToggleRow(stringResource(R.string.server_removal_revoke), revoke, onRevoke, showDivider = false)
            }
            Text(
                stringResource(R.string.server_removal_revoke_note),
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
    }
}

@Composable
private fun RemovalLastWayIn(names: List<String>, keep: () -> Unit, removeAnyway: () -> Unit) {
    IOSAlert(
        title = stringResource(R.string.server_removal_last_way_in, names.joinToString(", ")),
        onDismiss = keep,
        actions = listOf(
            AlertAction(stringResource(R.string.server_removal_keep_key), preferred = true, onSelect = keep),
            AlertAction(stringResource(R.string.server_removal_anyway), destructive = true, onSelect = removeAnyway),
        ),
    )
}

@Composable
private fun RemovalNote(text: String, action: String?, onCancel: (() -> Unit)? = null, onAction: () -> Unit) {
    val actions = buildList {
        onCancel?.let { add(AlertAction(stringResource(R.string.delete_server_cancel), onSelect = it)) }
        action?.let { add(AlertAction(it, preferred = true, onSelect = onAction)) }
    }
    IOSAlert(title = text, onDismiss = onCancel ?: {}, actions = actions)
}
