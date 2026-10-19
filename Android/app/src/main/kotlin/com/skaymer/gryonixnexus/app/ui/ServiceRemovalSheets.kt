package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.ui.text.style.TextAlign
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.AlertFields
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.HostActionsViewModel
import com.skaymer.gryonixnexus.app.servers.PurgeWarning
import com.skaymer.gryonixnexus.app.servers.ServiceRemovalViewModel
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.servercontrol.AdminLockdownState
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.PurgeOptions

@Composable
fun RemoveServiceDialog(
    deployment: Deployment,
    service: ManagedService,
    lockdown: AdminLockdownState?,
    onCancel: () -> Unit,
    onConfirm: (PurgeOptions) -> Unit,
) {
    var purgeData by remember(service.id) { mutableStateOf(false) }
    var purgeBackups by remember(service.id) { mutableStateOf(false) }
    var confirmingPurge by remember(service.id) { mutableStateOf(false) }
    val purge = PurgeOptions(data = purgeData, backups = purgeBackups)

    val alsoRemoved = remember(service.id, deployment.services) {
        ServiceRemovalViewModel.alsoRemovedNames(service, deployment.services)
    }
    val unguarded = remember(service.id, lockdown, deployment.id) {
        ServiceRemovalViewModel.unguardedPanelNames(
            service,
            lockdown,
            HostActionsViewModel.lockdownPages(deployment),
            deployment.services,
        )
    }

    IOSAlert(
        title = stringResource(R.string.remove_service_title, service.displayName),
        message = listOfNotNull(
            alsoRemoved.takeIf { it.isNotEmpty() }?.let {
                stringResource(R.string.remove_service_vpn_unit, it.joinToString(", "))
            },
            unguarded.takeIf { it.isNotEmpty() }?.let {
                stringResource(R.string.remove_service_unguarded, it.joinToString(", "))
            },
        ).joinToString("\n").takeIf { it.isNotEmpty() },
        onDismiss = onCancel,
        actions = listOf(
            AlertAction(stringResource(R.string.containers_cancel), onSelect = onCancel),
            AlertAction(
                stringResource(R.string.remove_service_confirm),
                destructive = true,
                onSelect = {
                    if (purge.isEmpty) onConfirm(PurgeOptions.NONE) else confirmingPurge = true
                },
            ),
        ),
    ) {
        AlertFields {
            ToggleRow(
                title = stringResource(R.string.remove_service_purge_data),
                checked = purgeData,
                onCheckedChange = { purgeData = it },
            )
            ToggleRow(
                title = stringResource(R.string.remove_service_purge_backups),
                checked = purgeBackups,
                onCheckedChange = { purgeBackups = it },
                showDivider = false,
            )
        }
        Text(
            warningText(ServiceRemovalViewModel.warning(purge)),
            style = MaterialTheme.typography.bodySmall,
            textAlign = TextAlign.Center,
            color = if (purge.isEmpty) Gryonix.colors.secondaryLabel else Gryonix.colors.danger,
            modifier = Modifier.fillMaxWidth().padding(top = 10.dp),
        )
    }

    if (confirmingPurge) {
        ConfirmAlert(
            title = stringResource(R.string.remove_service_delete_title),
            message = warningText(ServiceRemovalViewModel.warning(purge)),
            confirm = stringResource(R.string.remove_service_delete_everything),
            cancel = stringResource(R.string.containers_cancel),
            destructive = true,
            onConfirm = { confirmingPurge = false; onConfirm(purge) },
            onCancel = { confirmingPurge = false },
        )
    }
}

/** The removal while it runs, and its ending */
@Composable
fun RemoveServiceRunDialog(removal: ServiceRemovalViewModel) {
    val state by removal.state.collectAsState()
    val run = state.run ?: return

    IOSAlert(
        title = stringResource(R.string.remove_service_running),
        onDismiss = { if (run.isFinished) removal.clear() },
        actions = listOf(
            AlertAction(
                stringResource(R.string.containers_done),
                preferred = true,
                enabled = run.isFinished,
                onSelect = { removal.clear() },
            ),
        ),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            when {
                run.errorMessage != null -> Text(
                    run.errorMessage!!,
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.danger,
                    textAlign = TextAlign.Center,
                )
                run.isFinished -> Text(
                    stringResource(
                        if (run.purge.data) {
                            R.string.remove_service_done_purged
                        } else {
                            R.string.remove_service_done_kept
                        }
                    ),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.label,
                    textAlign = TextAlign.Center,
                )
                else -> Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(
                        Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = Gryonix.colors.tertiaryLabel,
                    )
                    Text(
                        stringResource(R.string.remove_service_stopping),
                        style = MaterialTheme.typography.bodyMedium,
                        color = Gryonix.colors.secondaryLabel,
                    )
                }
            }
            run.note?.let {
                Text(
                    stringResource(R.string.remove_service_surface_note, it),
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.warning,
                    textAlign = TextAlign.Center,
                )
            }
            if (run.log.isNotEmpty()) {
                Text(
                    run.log,
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = Gryonix.colors.secondaryLabel,
                    modifier = Modifier
                        .heightIn(max = 240.dp)
                        .verticalScroll(rememberScrollState()),
                )
            }
        }
    }
}

@Composable
private fun warningText(warning: PurgeWarning): String = stringResource(
    when (warning) {
        PurgeWarning.NOTHING -> R.string.remove_service_warning_nothing
        PurgeWarning.DATA -> R.string.remove_service_warning_data
        PurgeWarning.BACKUPS -> R.string.remove_service_warning_backups
        PurgeWarning.EVERYTHING -> R.string.remove_service_warning_everything
    }
)
