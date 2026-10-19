package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.BackupsViewModel
import com.skaymer.gryonixnexus.app.servers.MetricsFormat
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.servercontrol.BackupEstimate
import com.skaymer.gryonixnexus.servercontrol.BackupNowChoice
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.launch

/** Picks several services to back up now, and the key */
@Composable
fun BackupNowDialog(deployment: Deployment, backups: BackupsViewModel, onClose: () -> Unit) {
    val services = remember(deployment) { BackupsViewModel.backupCapableServices(deployment) }
    val defaultsOn = remember(services) { BackupsViewModel.encryptedByDefault(deployment, services) }
    val always = remember(services) { BackupsViewModel.alwaysEncrypted(deployment, services) }
    var choice by remember { mutableStateOf(BackupNowChoice()) }
    var hasStoredKey by remember { mutableStateOf<Boolean?>(null) }
    val estimates = remember { mutableStateMapOf<String, BackupEstimate>() }
    val estimating = remember { mutableStateMapOf<String, Boolean>() }
    val scope = rememberCoroutineScope()
    LaunchedEffect(deployment.id) {
        hasStoredKey = backups.hasStoredKey(deployment)
        if (hasStoredKey == false) choice = choice.copy(key = BackupNowChoice.Key.TYPED)
    }
    val select: (List<ManagedService>) -> Unit = { picked ->
        picked.forEach { choice = choice.toggled(it.id.rawValue) }
        picked.map { it.id.rawValue to it }
            .filter { (id, _) -> id in choice.services && id !in estimates && id !in estimating && id !in always }
            .forEach { (id, service) ->
                estimating[id] = true
                scope.launch {
                    backups.estimateOf(deployment, service)?.let { estimates[id] = it }
                    estimating.remove(id)
                }
            }
    }
    IOSSheet(
        title = stringResource(R.string.containers_backup_now),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_cancel),
        action = SheetAction(
            title = stringResource(R.string.backups_now_run, choice.services.size),
            enabled = choice.isReady(defaultsOn, always, hasStoredKey),
            onSelect = {
                backups.backUpMany(deployment, choice)
                onClose()
            },
        ),
    ) {
        BackupNowServices(services, choice.services, select)
        BackupNowSize(choice, estimates, pending = choice.services.any { it in estimating })
        BackupNowKey(choice, defaultsOn, always, services, hasStoredKey) { choice = it }
    }
}

@Composable
private fun BackupNowServices(
    services: List<ManagedService>,
    chosen: List<String>,
    select: (List<ManagedService>) -> Unit,
) {
    val allChosen = chosen.size == services.size
    GroupedSection(header = stringResource(R.string.services)) {
        ValueRow(
            title = stringResource(R.string.backups_selected_count, chosen.size),
            value = stringResource(if (allChosen) R.string.backups_deselect_all else R.string.security_select_all),
            onClick = { select(if (allChosen) services else services.filter { it.id.rawValue !in chosen }) },
        )
        services.forEach { service ->
            CheckRow(
                title = service.displayName,
                checked = service.id.rawValue in chosen,
                onClick = { select(listOf(service)) },
                showDivider = service != services.last(),
            )
        }
    }
}

@Composable
private fun BackupNowSize(choice: BackupNowChoice, estimates: Map<String, BackupEstimate>, pending: Boolean) {
    val total = BackupNowChoice.total(choice.services.mapNotNull { estimates[it] })
    if (!pending && total == null) return
    val footer = when {
        total == null -> null
        !total.fitsOnDisk -> stringResource(R.string.backups_will_not_fit)
        BackupsViewModel.isLarge(total) -> stringResource(R.string.backups_is_large)
        else -> null
    }
    GroupedSection(footer = footer) {
        if (pending || total == null) {
            ValueRow(stringResource(R.string.backups_checking_size), null, null, showDivider = false)
        } else {
            ValueRow(stringResource(R.string.backups_data), MetricsFormat.bytes(total.dataBytes), null)
            ValueRow(stringResource(R.string.backups_free), MetricsFormat.bytes(total.freeBytes), null, showDivider = false)
        }
    }
}

@Composable
private fun BackupNowKey(
    choice: BackupNowChoice,
    defaultsOn: Set<String>,
    always: Set<String>,
    services: List<ManagedService>,
    hasStoredKey: Boolean?,
    onChange: (BackupNowChoice) -> Unit,
) {
    val needsKey = choice.needsKey(defaultsOn, always)
    val notes = services.filter { it.id.rawValue in always && it.id.rawValue in choice.services }
        .map { stringResource(R.string.backups_now_always_encrypted, it.displayName) } +
        listOfNotNull(if (needsKey) keyNote(choice.key, hasStoredKey) else null)
    GroupedSection(footer = notes.joinToString("\n").ifEmpty { null }) {
        ToggleRow(
            title = stringResource(R.string.backups_now_encrypt),
            checked = choice.encrypting(defaultsOn),
            onCheckedChange = { onChange(choice.copy(encrypt = it)) },
            showDivider = needsKey,
        )
        if (needsKey) KeyFields(choice, onChange)
    }
}

@Composable
private fun KeyFields(choice: BackupNowChoice, onChange: (BackupNowChoice) -> Unit) {
    GroupedRow(showDivider = choice.key == BackupNowChoice.Key.TYPED) {
        IOSSegmentedControl(
            segments = BackupNowChoice.Key.entries,
            selected = choice.key,
            label = {
                stringResource(
                    if (it == BackupNowChoice.Key.STORED) R.string.backups_now_key_saved else R.string.backups_now_key_new,
                )
            },
            onSelect = { onChange(choice.copy(key = it)) },
            modifier = Modifier.padding(vertical = 4.dp),
        )
    }
    if (choice.key == BackupNowChoice.Key.TYPED) {
        FieldRow(
            label = stringResource(R.string.backups_password),
            value = choice.passphrase,
            onValueChange = { onChange(choice.copy(passphrase = it)) },
            visualTransformation = PasswordVisualTransformation(),
        )
        FieldRow(
            label = stringResource(R.string.backups_password_repeat),
            value = choice.confirmation,
            onValueChange = { onChange(choice.copy(confirmation = it)) },
            visualTransformation = PasswordVisualTransformation(),
            showDivider = false,
        )
    }
}

@Composable
private fun keyNote(key: BackupNowChoice.Key, hasStoredKey: Boolean?): String = stringResource(
    when {
        key == BackupNowChoice.Key.TYPED -> R.string.backups_now_key_typed_note
        hasStoredKey == false -> R.string.backups_now_key_missing_note
        else -> R.string.backups_now_key_saved_note
    },
)
