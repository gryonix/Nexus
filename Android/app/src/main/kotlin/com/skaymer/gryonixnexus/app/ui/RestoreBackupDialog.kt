package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.BackupsViewModel
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.FleetBackup

/** One listed backup, restored here or on another server */
@Composable
fun RestoreBackupDialog(
    here: Deployment,
    row: FleetBackup,
    fleet: List<Deployment>,
    backups: BackupsViewModel,
    onClose: () -> Unit,
) {
    val targets = remember(row, fleet) { BackupsViewModel.restoreTargets(here, row, fleet) }
    var targetId by remember { mutableStateOf(here.id) }
    var passphrase by remember { mutableStateOf("") }
    var confirming by remember { mutableStateOf(false) }
    val target = targets.firstOrNull { it.id == targetId }
    val service = ServiceRegistry.service(ServiceID(row.serviceId))
    val needsPassphrase = target != null && service != null &&
        BackupsViewModel.restoreNeedsPassphrase(service, target.serviceContext, row.entry.name)

    IOSSheet(
        title = stringResource(R.string.backups_restore),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_cancel),
        action = SheetAction(
            title = stringResource(R.string.backups_restore),
            enabled = target != null && (!needsPassphrase || passphrase.isNotEmpty()),
            onSelect = { confirming = true },
        ),
    ) {
        GroupedSection(
            header = stringResource(R.string.backups_restore_to),
            footer = if (targetId != here.id) stringResource(R.string.backups_restore_through_device, here.name) else null,
            note = stringResource(R.string.backups_restore_warning),
        ) {
            targets.forEach { server ->
                CheckRow(
                    title = server.name,
                    checked = server.id == targetId,
                    onClick = { targetId = server.id },
                    showDivider = server != targets.last(),
                )
            }
        }
        if (needsPassphrase) {
            GroupedSection(footer = stringResource(R.string.backups_restore_passphrase_note)) {
                FieldRow(
                    label = stringResource(R.string.backups_restore_passphrase),
                    value = passphrase,
                    onValueChange = { passphrase = it },
                    visualTransformation = PasswordVisualTransformation(),
                    showDivider = false,
                )
            }
        }
    }

    if (confirming && target != null) {
        ConfirmAlert(
            title = stringResource(R.string.backups_restore_confirm, row.serviceName, row.entry.displayName),
            message = stringResource(R.string.backups_restore_warning),
            confirm = stringResource(R.string.backups_restore),
            cancel = stringResource(R.string.containers_cancel),
            destructive = true,
            onConfirm = {
                confirming = false
                backups.restoreListed(here, target, row, passphrase.ifEmpty { null })
                onClose()
            },
            onCancel = { confirming = false },
        )
    }
}
