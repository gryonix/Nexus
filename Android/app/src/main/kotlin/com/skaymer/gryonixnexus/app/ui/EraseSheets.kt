package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.app.ui.design.RunLog
import com.skaymer.gryonixnexus.app.ui.design.RunProgressRow
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import androidx.compose.ui.text.style.TextAlign
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.IOSSwitch
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.security.LocalDeviceGate
import com.skaymer.gryonixnexus.app.servers.EraseViewModel
import kotlinx.coroutines.launch
import com.skaymer.gryonixnexus.app.servers.EraseWarning
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.PurgeOptions
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

@Composable
fun EraseCard(onOpen: () -> Unit) {
    GroupedSection(footer = stringResource(R.string.erase_explains)) {
        ActionRow(
            text = stringResource(R.string.erase_server),
            onClick = onOpen,
            danger = true,
            showDivider = false,
        )
    }
}

/** The two toggles, and the sentence they change */
@Composable
fun EraseDialog(
    deployment: Deployment,
    erase: EraseViewModel,
    onClose: () -> Unit,
) {
    var purgeData by remember(deployment.id) { mutableStateOf(false) }
    var purgeBackups by remember(deployment.id) { mutableStateOf(false) }
    var confirming by remember(deployment.id) { mutableStateOf(false) }
    var unlockDenied by remember { mutableStateOf(false) }
    val gate = LocalDeviceGate.current
    val scope = rememberCoroutineScope()
    val unlockReason = stringResource(R.string.erase_unlock_reason)
    val purge = PurgeOptions(data = purgeData, backups = purgeBackups)

    IOSAlert(
        title = stringResource(R.string.erase_title, deployment.name),
        message = stringResource(R.string.erase_explains),
        onDismiss = onClose,
        actions = listOf(
            AlertAction(stringResource(R.string.erase_cancel), onSelect = onClose),
            AlertAction(
                stringResource(R.string.erase_server),
                destructive = true,
                onSelect = { confirming = true },
            ),
        ),
    ) {
        Column(
            Modifier.verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            ToggleRow(
                label = stringResource(R.string.erase_purge_data),
                checked = purgeData,
                onChange = { purgeData = it },
            )
            ToggleRow(
                label = stringResource(R.string.erase_purge_backups),
                checked = purgeBackups,
                onChange = { purgeBackups = it },
            )
            Text(
                stringResource(warningText(EraseViewModel.warning(purge))),
                style = MaterialTheme.typography.bodySmall,
                textAlign = TextAlign.Center,
                color = if (purge.isEmpty) {
                    Gryonix.colors.secondaryLabel
                } else {
                    Gryonix.colors.danger
                },
            )
        }
    }

    if (confirming) {
        ConfirmAlert(
            title = stringResource(R.string.erase_title, deployment.name),
            message = stringResource(warningText(EraseViewModel.warning(purge))),
            confirm = stringResource(R.string.erase_confirm),
            cancel = stringResource(R.string.erase_cancel),
            destructive = true,
            onConfirm = {
                confirming = false
                scope.launch {
                    if (gate.confirm(unlockReason)) {
                        onClose()
                        erase.erase(deployment, purge)
                    } else {
                        unlockDenied = true
                    }
                }
            },
            onCancel = { confirming = false },
        )
    }
    if (unlockDenied) {
        IOSAlert(
            title = stringResource(R.string.erase_not_unlocked),
            message = stringResource(R.string.erase_not_unlocked_message),
            onDismiss = { unlockDenied = false },
            actions = listOf(AlertAction(stringResource(R.string.containers_done)) { unlockDenied = false }),
        )
    }
}

/** The run itself, outside the sheet that ordered it */
@Composable
fun EraseRunDialog(erase: EraseViewModel, name: (String) -> String, onErased: (String) -> Unit) {
    val run by erase.run.collectAsState()
    val current = run ?: return
    IOSAlert(
        title = stringResource(R.string.erase_running, name(current.deploymentID)),
        onDismiss = { if (current.isFinished) erase.clear() },
        actions = listOf(
            AlertAction(
                stringResource(R.string.containers_done),
                preferred = true,
                enabled = current.isFinished,
                onSelect = {
                    val id = current.deploymentID
                    val erased = current.erased
                    erase.clear()
                    if (erased) onErased(id)
                },
            ),
        ),
    ) {
        Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (!current.isFinished) RunProgressRow(stringResource(R.string.erase_cleaning, hostLabel(current.host)))
            if (current.erased) {
                Text(
                    stringResource(R.string.erase_done),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.label,
                    textAlign = TextAlign.Center,
                )
            }
            current.errorMessage?.let {
                Text(
                    stringResource(R.string.erase_failed, it),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.danger,
                    textAlign = TextAlign.Center,
                )
            }
            if (current.isFinished && !current.erased) {
                Text(
                    stringResource(R.string.erase_kept),
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.warning,
                    textAlign = TextAlign.Center,
                )
            }
            RunLog(current.log)
        }
    }
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            label,
            Modifier.weight(1f),
            style = MaterialTheme.typography.bodyMedium,
            color = Gryonix.colors.label,
        )
        IOSSwitch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun hostLabel(host: SSHHostID?): String = host?.let {
    when (val kind = it.kind) {
        is SSHHostID.Kind.Slot -> kind.slot.name.lowercase()
        is SSHHostID.Kind.Node -> kind.id
    }
} ?: ""

private fun warningText(warning: EraseWarning): Int = when (warning) {
    EraseWarning.NOTHING_DELETED -> R.string.erase_keeps_everything
    EraseWarning.DATA -> R.string.erase_deletes_data
    EraseWarning.BACKUPS -> R.string.erase_deletes_backups
    EraseWarning.DATA_AND_BACKUPS -> R.string.erase_deletes_both
}
