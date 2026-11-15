package com.skaymer.gryonixnexus.app.ui

import android.widget.Toast
import com.skaymer.gryonixnexus.app.servers.PendingRules
import com.skaymer.gryonixnexus.app.ui.design.ApplyPendingBar
import com.skaymer.gryonixnexus.app.ui.design.RunLog
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.automirrored.outlined.ListAlt
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.CloudUpload
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.SettingsBackupRestore
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.Usb
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ExpandMore
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material.icons.Icons
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl
import com.skaymer.gryonixnexus.app.ui.design.StepperRow
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import androidx.compose.ui.text.style.TextAlign
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.AlertFields
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.FormSheet
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.agentcontrol.PreRestoreCopy
import com.skaymer.gryonixnexus.app.servers.BackupRun
import com.skaymer.gryonixnexus.app.servers.BackupPartsModel
import com.skaymer.gryonixnexus.app.servers.BackupsViewModel
import com.skaymer.gryonixnexus.app.servers.MetricsFormat
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.AutoBackupSettings
import com.skaymer.gryonixnexus.servercontrol.BackupDestinationSettings
import com.skaymer.gryonixnexus.servercontrol.BackupDestinationState
import com.skaymer.gryonixnexus.servercontrol.BackupEntry
import com.skaymer.gryonixnexus.servercontrol.BackupFilter
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** The row on the server screen that leads to backups */
@Composable
fun BackupsCard(
    deployment: Deployment,
    backups: BackupsViewModel,
    onOpen: () -> Unit,
    showDivider: Boolean = true,
) {
    val state by backups.state.collectAsState()
    ValueRow(
        title = stringResource(R.string.backups),
        value = if (state.hasLoadedSchedule) state.schedule.schedule.sentence() else null,
        onClick = onOpen,
        showDivider = showDivider,
        leading = { HubIcon(Icons.Outlined.SettingsBackupRestore) },
    )
}

@Composable
fun BackupsDialog(
    deployment: Deployment,
    backups: BackupsViewModel,
    fleet: List<Deployment> = emptyList(),
    onClose: () -> Unit,
) {
    val state by backups.state.collectAsState()
    val allState by backups.all.collectAsState()
    val partsModel = remember(deployment.id) { backups.parts() }
    LaunchedEffect(deployment.id) {
        backups.loadSchedule(deployment)
        backups.loadDestination(deployment)
        backups.loadAll(deployment)
        partsModel.load(deployment)
    }
    var page by remember(deployment.id) { mutableStateOf<BackupsPage?>(null) }
    var restoring by remember { mutableStateOf<ManagedService?>(null) }
    val capable = remember(deployment) { BackupsViewModel.backupCapableServices(deployment) }
    val restorable = remember(deployment) { BackupsViewModel.restorableServices(deployment) }

    IOSSheet(title = stringResource(R.string.backups), onClose = onClose, closeLabel = stringResource(R.string.close)) {
        BackupNumbers(allState)
        BackupActions(
            canBackUp = capable.isNotEmpty(),
            canRestore = restorable.isNotEmpty(),
            onOpen = { page = it },
        )
        BackupSettings(deployment, state, partsModel, onOpen = { page = it })
    }
    BackupsPageSheet(page, deployment, backups, fleet, partsModel, restorable,
        onRestore = { restoring = it }, onClose = { page = null })
    restoring?.let { service ->
        RestorePickerDialog(deployment = deployment, backups = backups, service = service, onClose = { restoring = null })
    }
}

/** Pages the backups hub opens */
private enum class BackupsPage { ALL, NOW, RESTORE, SCHEDULE, PARTS, DESTINATION, DRIVES }

@Composable
private fun BackupActions(canBackUp: Boolean, canRestore: Boolean, onOpen: (BackupsPage) -> Unit) {
    val accent = Gryonix.colors.accent
    GroupedSection {
        ValueRow(
            title = stringResource(R.string.backups_all),
            value = null,
            onClick = { onOpen(BackupsPage.ALL) },
            showDivider = canBackUp || canRestore,
            leading = { HubIcon(Icons.AutoMirrored.Outlined.ListAlt, accent) },
        )
        if (canBackUp) {
            ActionRow(
                text = stringResource(R.string.containers_backup_now),
                onClick = { onOpen(BackupsPage.NOW) },
                showDivider = canRestore,
                leading = { HubIcon(Icons.Outlined.Sync, accent) },
            )
        }
        if (canRestore) {
            ActionRow(
                text = stringResource(R.string.backups_restore),
                onClick = { onOpen(BackupsPage.RESTORE) },
                showDivider = false,
                leading = { HubIcon(Icons.Outlined.History, accent) },
            )
        }
    }
}

@Composable
private fun BackupSettings(
    deployment: Deployment,
    state: com.skaymer.gryonixnexus.app.servers.BackupsState,
    partsModel: BackupPartsModel,
    onOpen: (BackupsPage) -> Unit,
) {
    val parts by partsModel.state.collectAsState()
    val accent = Gryonix.colors.accent
    GroupedSection {
        ValueRow(
            title = stringResource(R.string.backups_schedule),
            value = if (state.hasLoadedSchedule) state.schedule.schedule.sentence() else null,
            onClick = { onOpen(BackupsPage.SCHEDULE) },
            leading = { HubIcon(Icons.Outlined.Schedule, accent) },
        )
        ValueRow(
            title = stringResource(R.string.backup_parts_title),
            value = backupPartsSummary(parts.parts.choice.regular),
            onClick = { onOpen(BackupsPage.PARTS) },
            leading = { HubIcon(Icons.Outlined.Checklist, accent) },
        )
        ValueRow(
            title = stringResource(R.string.backup_destination_row),
            value = destinationSummary(state.destination),
            onClick = { onOpen(BackupsPage.DESTINATION) },
            showDivider = deployment.hasPhysicalAccess,
            leading = { HubIcon(Icons.Outlined.CloudUpload, accent) },
        )
        if (deployment.hasPhysicalAccess) {
            ValueRow(
                title = stringResource(R.string.drive_title),
                value = null,
                onClick = { onOpen(BackupsPage.DRIVES) },
                showDivider = false,
                leading = { HubIcon(Icons.Outlined.Usb, accent) },
            )
        }
    }
}

@Composable
private fun BackupsPageSheet(
    page: BackupsPage?,
    deployment: Deployment,
    backups: BackupsViewModel,
    fleet: List<Deployment>,
    partsModel: BackupPartsModel,
    restorable: List<ManagedService>,
    onRestore: (ManagedService) -> Unit,
    onClose: () -> Unit,
) {
    when (page) {
        BackupsPage.ALL -> AllBackupsDialog(deployment, backups, fleet, onClose)
        BackupsPage.NOW -> BackupNowDialog(deployment, backups, onClose)
        BackupsPage.RESTORE -> RestoreServiceChooser(restorable, onPick = { onClose(); onRestore(it) }, onClose = onClose)
        BackupsPage.SCHEDULE -> BackupScheduleSheet(deployment, backups, onClose)
        BackupsPage.PARTS -> BackupPartsSheet(deployment, partsModel, BackupPartsScope.REGULAR, onClose)
        BackupsPage.DESTINATION -> BackupDestinationSheet(deployment = deployment, fleet = fleet, backups = backups, onClose = onClose)
        BackupsPage.DRIVES -> BackupDrivesSheet(deployment, remember(deployment.id) { backups.drives() }, onClose)
        null -> Unit
    }
}

/** Which service to restore */
@Composable
private fun RestoreServiceChooser(services: List<ManagedService>, onPick: (ManagedService) -> Unit, onClose: () -> Unit) {
    IOSSheet(title = stringResource(R.string.backups_restore), onClose = onClose, closeLabel = stringResource(R.string.close)) {
        GroupedSection {
            services.forEachIndexed { index, service ->
                ValueRow(
                    title = service.displayName,
                    value = null,
                    onClick = { onPick(service) },
                    showDivider = index < services.lastIndex,
                )
            }
        }
    }
}

/** The server's backup timer, saved on its own page */
@Composable
private fun BackupScheduleSheet(deployment: Deployment, backups: BackupsViewModel, onClose: () -> Unit) {
    val state by backups.state.collectAsState()
    val capable = remember(deployment) { BackupsViewModel.backupCapableServices(deployment) }
    var draft by remember(state.schedule) { mutableStateOf(state.schedule) }
    var passphrase by remember(deployment.id) { mutableStateOf("") }
    IOSSheet(
        title = stringResource(R.string.backups_schedule),
        onClose = onClose,
        closeLabel = stringResource(R.string.close),
        bottomBar = {
            ApplyPendingBar(
                visible = PendingRules.backupSchedule(
                    canSave = BackupsViewModel.canSaveSchedule(
                        deployment = deployment,
                        draft = draft,
                        saved = state.schedule,
                        typedPassphrase = passphrase,
                        isSaving = state.isSaving,
                    ),
                    changed = draft != state.schedule,
                    typedPassphrase = passphrase,
                ),
                apply = stringResource(R.string.updates_save),
                cancel = stringResource(R.string.pending_changes_cancel),
                onApply = {
                    backups.saveSchedule(deployment, draft, passphrase.ifEmpty { null })
                    passphrase = ""
                },
                onRevert = { draft = state.schedule; passphrase = "" },
            )
        },
    ) {
        ScheduleEditor(
            deployment = deployment,
            draft = draft,
            services = serviceTitles(deployment.id).let { title -> capable.map { it.id to title(it) } },
            passphrase = passphrase,
            hasStoredPassphrase = BackupsViewModel.hasStoredPassphrase(deployment, state.schedule),
            onChange = { draft = it },
            onPassphrase = { passphrase = it },
            error = state.scheduleError,
        )
    }
}

/** One service's backup: size check and passphrase */
@Composable
internal fun BackupConfirmDialog(
    deployment: Deployment,
    backups: BackupsViewModel,
    service: ManagedService,
    onClose: () -> Unit,
) {
    val state by backups.state.collectAsState()
    LaunchedEffect(service.id) { backups.estimate(deployment, service.id) }

    val estimate = state.estimate?.takeIf { it.service == service.id }
    val encryptsByDefault = remember(service, deployment) {
        service.actions(deployment.serviceContext).backup?.encryptsByDefault ?: false
    }
    var encrypt by remember(service.id) { mutableStateOf<Boolean?>(null) }
    var passphrase by remember(service.id) { mutableStateOf("") }
    var confirmation by remember(service.id) { mutableStateOf("") }
    val encrypting = encrypt ?: encryptsByDefault
    val doesNotFit = BackupsViewModel.doesNotFit(estimate?.estimate)

    val armed = estimate?.isLoading == false &&
        BackupsViewModel.passphraseIsUsable(passphrase, confirmation)
    FormSheet(
        title = serviceTitles(deployment.id)(service),
        onDismiss = onClose,
        message = when {
            doesNotFit -> stringResource(R.string.backups_will_not_fit)
            BackupsViewModel.isLarge(estimate?.estimate) ->
                stringResource(R.string.backups_is_large)
            encrypting -> stringResource(R.string.backups_password_note)
            else -> stringResource(R.string.backups_plain_note)
        },
        actions = listOf(
            AlertAction(stringResource(R.string.containers_cancel), onSelect = onClose),
            AlertAction(
                stringResource(
                    if (doesNotFit) R.string.backups_run_anyway else R.string.backups_run
                ),
                destructive = doesNotFit,
                preferred = !doesNotFit,
                enabled = armed,
                onSelect = {
                    backups.backUp(
                        deployment,
                        service.id,
                        encrypt = encrypt,
                        passphrase = passphrase.ifEmpty { null },
                    )
                    onClose()
                },
            ),
        ),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            when {
                estimate == null || estimate.isLoading -> Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement =
                        Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(
                        Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = Gryonix.colors.tertiaryLabel,
                    )
                    Text(
                        stringResource(R.string.backups_checking_size),
                        style = MaterialTheme.typography.bodySmall,
                        color = Gryonix.colors.secondaryLabel,
                    )
                }
                estimate.estimate != null -> AlertFields {
                    ValueRow(
                        title = stringResource(R.string.backups_data),
                        value = MetricsFormat.bytes(estimate.estimate!!.dataBytes),
                        onClick = null,
                    )
                    ValueRow(
                        title = stringResource(R.string.backups_free),
                        value = MetricsFormat.bytes(estimate.estimate!!.freeBytes),
                        onClick = null,
                        showDivider = false,
                    )
                }
                else -> Text(
                    stringResource(R.string.backups_no_estimate),
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.secondaryLabel,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            estimate?.errorMessage?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.danger,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            AlertFields {
                ToggleRow(
                    title = stringResource(R.string.backups_encrypt),
                    checked = encrypting,
                    onCheckedChange = { encrypt = it },
                    showDivider = encrypting,
                )
                if (encrypting) {
                    FieldRow(
                        label = stringResource(R.string.backups_password),
                        value = passphrase,
                        onValueChange = { passphrase = it },
                        visualTransformation = PasswordVisualTransformation(),
                    )
                    FieldRow(
                        label = stringResource(R.string.backups_password_repeat),
                        value = confirmation,
                        onValueChange = { confirmation = it },
                        visualTransformation = PasswordVisualTransformation(),
                        showDivider = false,
                    )
                }
            }
        }
    }
}

/** Which archive to put back */
@Composable
internal fun RestorePickerDialog(
    deployment: Deployment,
    backups: BackupsViewModel,
    service: ManagedService,
    onClose: () -> Unit,
) {
    val state by backups.state.collectAsState()
    LaunchedEffect(service.id) { backups.list(deployment, service.id) }

    val listing = state.services[service.id]
    var chosen by remember(service.id) { mutableStateOf<BackupEntry?>(null) }
    var place by remember(service.id) { mutableStateOf(BackupFilter.Place.ANY) }
    var passphrase by remember(service.id) { mutableStateOf("") }
    var deletingCopy by remember(service.id) { mutableStateOf<PreRestoreCopy?>(null) }
    val path = chosen?.let { BackupsViewModel.path(service, deployment.serviceContext, it) }
    val needsPassphrase = path != null && BackupsViewModel.restoreNeedsPassphrase(
        service, deployment.serviceContext, path
    )

    val armed = chosen != null && (!needsPassphrase || passphrase.isNotEmpty())
    IOSSheet(
        title = stringResource(R.string.backups_restoring, serviceTitles(deployment.id)(service)),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_cancel),
        action = SheetAction(
            title = stringResource(R.string.backups_restore),
            enabled = armed,
            destructive = true,
            onSelect = {
                backups.restore(
                    deployment,
                    service.id,
                    chosen!!.name,
                    passphrase.ifEmpty { null },
                )
                onClose()
            },
        ),
    ) {
        Text(
            stringResource(R.string.backups_restore_warning),
            style = MaterialTheme.typography.bodySmall,
            color = Gryonix.colors.danger,
            modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
        )
        when {
            listing == null || listing.isLoading -> Text(
                stringResource(R.string.backups_loading),
                style = MaterialTheme.typography.bodyMedium,
                color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
            )
            listing.errorMessage != null -> Text(
                listing.errorMessage!!,
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.danger,
                modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
            )
            listing.saysThereAreNone -> Text(
                stringResource(R.string.backups_none),
                style = MaterialTheme.typography.bodyMedium,
                color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
            )
            else -> GroupedSection(
                header = stringResource(R.string.backups_restore_pick),
                footer = chosen?.let {
                    stringResource(
                        R.string.backups_restore_confirm,
                        service.displayName,
                        it.displayName,
                    )
                },
            ) {
                val shown = listing.entries.filter { place.admits(it) }
                GroupedRow(showDivider = shown.isNotEmpty()) { PlacePicker(place) { place = it } }
                if (shown.isEmpty()) {
                    GroupedRow(showDivider = false) {
                        Text(
                            stringResource(R.string.backups_none),
                            style = MaterialTheme.typography.bodyMedium,
                            color = Gryonix.colors.secondaryLabel,
                        )
                    }
                }
                shown.forEach { entry ->
                    CheckRow(
                        title = entry.displayName,
                        subtitle = listOfNotNull(
                            stringResource(R.string.backups_entry_detail, entry.sizeText, entry.dateText),
                            entry.drive?.let { stringResource(R.string.drive_copy_on, it) },
                        ).joinToString(" · "),
                        checked = chosen?.name == entry.name,
                        onClick = { chosen = entry },
                        showDivider = entry != shown.last(),
                    )
                }
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
        RestoreFromFileSection(deployment, backups, service, passphrase, onStarted = onClose)
        OldCopiesSection(
            copies = state.oldCopies[service.id].orEmpty(),
            onDelete = { deletingCopy = it },
        )
    }
    deletingCopy?.let { copy ->
        ConfirmAlert(
            title = stringResource(R.string.backups_old_copy_delete_title),
            message = stringResource(R.string.backups_old_copy_delete_message, copy.name),
            confirm = stringResource(R.string.backups_delete),
            cancel = stringResource(R.string.containers_cancel),
            destructive = true,
            onConfirm = {
                backups.deleteOldCopy(deployment, service.id, copy)
                deletingCopy = null
            },
            onCancel = { deletingCopy = null },
        )
    }
}

/** Restores from an archive picked on this phone */
@Composable
private fun RestoreFromFileSection(
    deployment: Deployment,
    backups: BackupsViewModel,
    service: ManagedService,
    passphrase: String,
    onStarted: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val readFrom = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val bytes = withContext(Dispatchers.IO) {
                runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull()
            } ?: return@launch
            backups.restoreFromDevice(deployment, service.id, bytes, DocumentFileName.of(context, uri), passphrase.ifEmpty { null })
            onStarted()
        }
    }
    GroupedSection {
        ActionRow(
            text = stringResource(R.string.backups_restore_from_file),
            onClick = { readFrom.launch(arrayOf("*/*")) },
            showDivider = false,
        )
    }
}

/** The timer the SERVER keeps */
@Composable
private fun ScheduleEditor(
    deployment: Deployment,
    draft: AutoBackupSettings,
    services: List<Pair<ServiceID, String>>,
    passphrase: String,
    hasStoredPassphrase: Boolean,
    onChange: (AutoBackupSettings) -> Unit,
    onPassphrase: (String) -> Unit,
    error: String? = null,
) {
    val schedule = draft.schedule
    val needsPassphrase = BackupsViewModel.scheduleNeedsPassphrase(deployment, draft)

    GroupedSection(
        footer = error ?: if (needsPassphrase) {
            stringResource(
                if (hasStoredPassphrase) R.string.backups_schedule_passphrase_stored
                else R.string.backups_schedule_passphrase_note
            )
        } else {
            null
        },
    ) {
        ToggleRow(
            title = stringResource(R.string.backups_schedule),
            checked = draft.isOn,
            onCheckedChange = { on ->
                onChange(
                    draft.copy(
                        schedule = if (on) CommandCatalog.Backups.Schedule.Days(1, 3, 0)
                        else CommandCatalog.Backups.Schedule.Off
                    )
                )
            },
            showDivider = draft.isOn,
        )
        if (draft.isOn) {
            ScheduleFieldRows(schedule, defaultHour = 3) { onChange(draft.copy(schedule = it)) }
            StepperRow(
                label = stringResource(R.string.backups_keep),
                value = draft.retention,
                range = 1..30,
                onChange = { onChange(draft.copy(retention = it)) },
            )
            services.forEach { (id, name) ->
                ToggleRow(
                    title = name,
                    checked = id.rawValue in draft.services,
                    onCheckedChange = { on ->
                        onChange(
                            draft.copy(
                                services = if (on) draft.services + id.rawValue
                                else draft.services - id.rawValue
                            )
                        )
                    },
                )
            }
            if (needsPassphrase) {
                FieldRow(
                    label = stringResource(
                        if (hasStoredPassphrase) R.string.backups_schedule_passphrase_new
                        else R.string.backups_schedule_passphrase
                    ),
                    value = passphrase,
                    onValueChange = onPassphrase,
                    visualTransformation = PasswordVisualTransformation(),
                    showDivider = false,
                )
            }
        }
    }
}

@Composable
fun BackupRunDialog(backups: BackupsViewModel) {
    val state by backups.state.collectAsState()
    val run = state.run ?: return
    val name = ServiceRegistry.service(run.service)?.displayName ?: run.service.rawValue
    IOSAlert(
        title = stringResource(
            when (run.kind) {
                BackupRun.Kind.BACKUP -> R.string.backups_running
                BackupRun.Kind.RESTORE -> R.string.backups_restoring
            },
            name,
        ),
        onDismiss = { if (run.isFinished) backups.clearRun() },
        actions = listOf(
            AlertAction(
                stringResource(R.string.containers_done),
                preferred = true,
                enabled = run.isFinished,
                onSelect = { backups.clearRun() },
            ),
        ),
    ) {
        Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (!run.isFinished) {
                CircularProgressIndicator(
                    Modifier.size(20.dp),
                    strokeWidth = 2.dp,
                    color = Gryonix.colors.tertiaryLabel,
                )
            }
            if (run.isFinished && run.errorMessage == null) {
                Text(
                    when {
                        run.kind == BackupRun.Kind.RESTORE ->
                            stringResource(R.string.backups_restore_finished)
                        run.sizeBytes != null -> stringResource(
                            R.string.backups_finished,
                            MetricsFormat.bytes(run.sizeBytes!!),
                        )
                        else -> stringResource(R.string.backups_finished_unnamed)
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.label,
                    textAlign = TextAlign.Center,
                )
            }
            run.errorMessage?.let {
                Text(
                    stringResource(
                        when (run.kind) {
                            BackupRun.Kind.BACKUP -> R.string.backups_failed
                            BackupRun.Kind.RESTORE -> R.string.backups_restore_failed
                        },
                        it,
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.danger,
                    textAlign = TextAlign.Center,
                )
            }
            AiExplainFailure(stringResource(R.string.backups_failed, run.errorMessage.orEmpty()), run.errorMessage, run.log)
            RunLog(run.log)
        }
    }
}

@Composable
private fun CommandCatalog.Backups.Schedule.sentence(): String = when (this) {
    CommandCatalog.Backups.Schedule.Off -> stringResource(R.string.updates_off)
    is CommandCatalog.Backups.Schedule.Hours ->
        stringResource(R.string.updates_summary_hours, count, minute)
    is CommandCatalog.Backups.Schedule.Days ->
        stringResource(R.string.updates_summary_days, count, hour, minute)
}

@Composable
private fun destinationSummary(state: BackupDestinationState): String {
    if (state.settings.kind == BackupDestinationSettings.Kind.NONE) {
        return stringResource(R.string.backup_destination_this_server)
    }
    if (state.lastShipmentAt != null && !state.lastShipmentSucceeded) {
        return stringResource(R.string.backup_destination_last_failed)
    }
    return when (state.settings.kind) {
        BackupDestinationSettings.Kind.SSH -> state.settings.host
        BackupDestinationSettings.Kind.S3 -> state.settings.bucket
        BackupDestinationSettings.Kind.NONE ->
            stringResource(R.string.backup_destination_this_server)
    }
}
