package com.skaymer.gryonixnexus.app.ui

import android.text.format.DateUtils
import android.text.format.Formatter
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.install.StorageStep
import com.skaymer.gryonixnexus.app.servers.BackupDrivesDemo
import com.skaymer.gryonixnexus.app.servers.BackupDrivesModel
import com.skaymer.gryonixnexus.app.servers.DemoDeployments
import com.skaymer.gryonixnexus.app.storage.StorageAgentTasks
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.catalog.storage.BackupDrive
import com.skaymer.gryonixnexus.catalog.storage.BackupDriveCheck
import com.skaymer.gryonixnexus.catalog.storage.BackupDriveScripts
import com.skaymer.gryonixnexus.catalog.storage.BackupDrives
import com.skaymer.gryonixnexus.catalog.storage.ServerHardware
import com.skaymer.gryonixnexus.servercontrol.BackupDriveSettings
import com.skaymer.gryonixnexus.servercontrol.BackupDriveStatus
import com.skaymer.gryonixnexus.servercontrol.BackupDrivesState
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** Which drive step ran, to read its output */
private sealed interface DriveRun {
    data class Format(val driveID: String, val replacing: String?, val name: String) : DriveRun
    data class Check(val driveID: String) : DriveRun
    data class Forget(val uuid: String) : DriveRun
    data object Other : DriveRun
}

private typealias RunDriveStep = (DriveRun, StorageStep) -> Unit

/** USB drives that take a copy of each backup */
@Composable
fun BackupDrivesSheet(deployment: Deployment, drivesModel: BackupDrivesModel, onClose: () -> Unit) {
    val app = LocalContext.current.applicationContext as? GryonixApplication ?: return
    val storage = app.storage
    val demo = DemoDeployments.isDemoID(deployment.id)
    val screen by drivesModel.state.collectAsState()
    val storageState by storage.state.collectAsState()
    var opened by remember { mutableStateOf<String?>(null) }
    var pending by remember { mutableStateOf<DriveRun?>(null) }
    LaunchedEffect(deployment.id) {
        drivesModel.load(deployment)
        if (!demo) storage.load(deployment, deployment.servicesHost)
    }
    LaunchedEffect(storageState.running) {
        val run = pending ?: return@LaunchedEffect
        if (storageState.running) return@LaunchedEffect
        pending = null
        finished(run, storageState.lastOutput, deployment, drivesModel)
    }
    val hardware = if (demo) ServerHardware.parse(BackupDrivesDemo.PROBE) else storageState.hardware
    val drives = BackupDrivesModel.drives(hardware, screen.drives)
    val runStep: RunDriveStep = { run, step ->
        if (demo) {
            finished(run, step.doneMarker, deployment, drivesModel)
        } else {
            pending = run
            StorageSign(usesServer = true).run(storage, deployment, deployment.servicesHost, step)
        }
    }
    val drive = drives.firstOrNull { it.id == opened }
    if (drive != null) {
        BackupDriveSheet(deployment, drivesModel, drive, drives, storageState.running, storageState.stepFailure, runStep) {
            opened = null
        }
        return
    }
    IOSSheet(title = stringResource(R.string.drive_title), onClose = onClose, closeLabel = stringResource(R.string.group_cancel)) {
        if (screen.loaded && !screen.drives.supported) {
            NoteSection(stringResource(R.string.drive_outdated))
        } else {
            DriveModeSection(deployment, drivesModel, screen.drives.settings, screen.busy)
            val needsPassphrase = screen.drives.settings.encrypt && !screen.drives.hasPassphrase && screen.loaded
            DrivePassphraseSection(deployment, drivesModel, needsPassphrase, screen.busy)
            DriveListSection(drives, screen.drives, storageState.isLoading) { opened = it.id }
            DriveLastCopySection(screen.drives)
        }
        (screen.error ?: storageState.stepFailure)?.let { NoteSection(it, warning = true) }
    }
}

/** Reads what a drive step printed and acts on it */
private fun finished(run: DriveRun, output: String?, deployment: Deployment, model: BackupDrivesModel) {
    val text = output ?: return
    val demo = DemoDeployments.isDemoID(deployment.id)
    when (run) {
        is DriveRun.Format -> {
            val uuid = BackupDriveScripts.formattedUuid(text) ?: if (demo) BackupDrivesDemo.UUID else null
            if (uuid != null) model.formatted(deployment, uuid, run.replacing, run.name) else model.load(deployment)
        }
        is DriveRun.Forget -> model.forgotten(deployment, run.uuid)
        is DriveRun.Check -> {
            model.remember(run.driveID, if (demo) BackupDrivesDemo.check else BackupDriveCheck.parse(text))
            model.load(deployment)
        }
        DriveRun.Other -> model.load(deployment)
    }
}

@Composable
private fun DriveModeSection(deployment: Deployment, model: BackupDrivesModel, settings: BackupDriveSettings, busy: Boolean) {
    val footer = when (settings.mode) {
        BackupDriveSettings.Mode.BOTH -> R.string.drive_mode_both_note
        BackupDriveSettings.Mode.DRIVE -> R.string.drive_mode_drive_note
        BackupDriveSettings.Mode.LOCAL -> R.string.drive_mode_local_note
    }
    GroupedSection(
        header = stringResource(R.string.drive_title),
        note = stringResource(R.string.drive_note),
        footer = stringResource(footer),
    ) {
        val titles = linkedMapOf(
            BackupDriveSettings.Mode.BOTH to stringResource(R.string.drive_mode_both),
            BackupDriveSettings.Mode.DRIVE to stringResource(R.string.drive_mode_drive),
            BackupDriveSettings.Mode.LOCAL to stringResource(R.string.drive_mode_local),
        )
        ChoiceRow(
            title = stringResource(R.string.drive_archives_go_to),
            value = titles.getValue(settings.mode),
            options = titles.map { (mode, title) -> title to { model.save(deployment, settings.copy(mode = mode)) } },
        )
        ToggleRow(
            title = stringResource(R.string.drive_encrypt),
            checked = settings.encrypt,
            onCheckedChange = { model.save(deployment, settings.copy(encrypt = it)) },
            enabled = !busy,
            showDivider = false,
        )
    }
}

@Composable
private fun DrivePassphraseSection(deployment: Deployment, model: BackupDrivesModel, needed: Boolean, busy: Boolean) {
    if (!needed) return
    var passphrase by remember { mutableStateOf("") }
    GroupedSection(footer = stringResource(R.string.drive_passphrase_note)) {
        FieldRow(
            label = stringResource(R.string.drive_passphrase),
            value = passphrase,
            onValueChange = { passphrase = it },
            visualTransformation = PasswordVisualTransformation(),
        )
        ActionRow(
            text = stringResource(R.string.drive_save_passphrase),
            enabled = passphrase.isNotEmpty() && !busy,
            showDivider = false,
            onClick = {
                model.savePassphrase(deployment, passphrase)
                passphrase = ""
            },
        )
    }
}

@Composable
private fun DriveListSection(drives: List<BackupDrive>, state: BackupDrivesState, loading: Boolean, onOpen: (BackupDrive) -> Unit) {
    GroupedSection(header = stringResource(R.string.drive_list)) {
        if (drives.isEmpty()) {
            GroupedRow(showDivider = false) {
                Text(
                    stringResource(if (loading) R.string.drive_looking else R.string.drive_none),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
        }
        drives.forEachIndexed { index, drive ->
            val used = drive.uuid != null && drive.uuid in state.settings.uuids
            ValueRow(
                title = drive.name,
                value = driveState(drive, used),
                subtitle = driveSize(drive, BackupDrivesModel.status(drive, state)),
                onClick = { onOpen(drive) },
                showDivider = index != drives.lastIndex,
            )
        }
    }
}

@Composable
private fun DriveLastCopySection(state: BackupDrivesState) {
    if (state.lastCopyAt <= 0) return
    val now = System.currentTimeMillis()
    val ago = DateUtils.getRelativeTimeSpanString(state.lastCopyAt * 1000L, now, DateUtils.MINUTE_IN_MILLIS).toString()
    GroupedSection {
        ValueRow(stringResource(R.string.drive_last_copy), ago, null, showDivider = !state.lastCopySucceeded)
        if (!state.lastCopySucceeded) {
            GroupedRow(showDivider = false) {
                Text(
                    state.lastError.ifEmpty { stringResource(R.string.drive_last_failed) },
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.warning,
                )
            }
        }
    }
}

@Composable
private fun NoteSection(text: String, warning: Boolean = false) {
    GroupedSection {
        GroupedRow(showDivider = false) {
            Text(
                text,
                style = MaterialTheme.typography.bodyMedium,
                color = if (warning) Gryonix.colors.warning else Gryonix.colors.secondaryLabel,
            )
        }
    }
}

@Composable
private fun driveState(drive: BackupDrive, used: Boolean): String = stringResource(
    when (drive.state) {
        BackupDrive.State.BLANK -> R.string.drive_state_blank
        BackupDrive.State.UNMOUNTED -> R.string.drive_state_unmounted
        BackupDrive.State.MISSING -> R.string.drive_state_missing
        BackupDrive.State.READY -> if (used) R.string.drive_state_used else R.string.drive_state_ready
    },
)

@Composable
private fun driveSize(drive: BackupDrive, status: BackupDriveStatus?): String {
    val context = LocalContext.current
    if (status != null && status.mounted && status.sizeBytes > 0) {
        return stringResource(
            R.string.drive_free_of,
            Formatter.formatFileSize(context, status.freeBytes),
            Formatter.formatFileSize(context, status.sizeBytes),
        )
    }
    return if (drive.sizeBytes > 0) Formatter.formatFileSize(context, drive.sizeBytes) else "—"
}

/** One USB drive and the work it allows */
@Composable
private fun BackupDriveSheet(
    deployment: Deployment,
    model: BackupDrivesModel,
    drive: BackupDrive,
    drives: List<BackupDrive>,
    running: Boolean,
    failure: String?,
    run: RunDriveStep,
    onClose: () -> Unit,
) {
    val screen by model.state.collectAsState()
    val used = drive.uuid != null && drive.uuid in screen.drives.settings.uuids
    IOSSheet(title = drive.name, onClose = onClose, closeLabel = stringResource(R.string.group_cancel)) {
        DriveFacts(drive, BackupDrivesModel.status(drive, screen.drives))
        drive.uuid?.let { uuid ->
            GroupedSection {
                ToggleRow(
                    title = stringResource(R.string.drive_use),
                    checked = used,
                    onCheckedChange = { model.setUsed(deployment, uuid, it) },
                    enabled = !screen.busy && !running,
                    showDivider = false,
                )
            }
        }
        screen.checks[drive.id]?.let { DriveCheckSection(it) }
        val unmapped = drive.state == BackupDrive.State.MISSING && drive.uuid?.let(screen.drives::isUnmapped) == true
        DriveActions(drive, running, run) { uuid ->
            if (unmapped) {
                model.forgotten(deployment, uuid)
            } else {
                run(DriveRun.Forget(uuid), StorageAgentTasks.drive(StorageAgentTasks.DriveWork.FORGET, uuid, drive.name))
            }
        }
        if (drive.disk != null) DriveFormatSection(drive, drives, running, run)
        failure?.let { NoteSection(it, warning = true) }
    }
}

@Composable
private fun DriveFacts(drive: BackupDrive, status: BackupDriveStatus?) {
    GroupedSection {
        drive.disk?.let { disk ->
            ValueRow(stringResource(R.string.drive_model), disk.model.ifEmpty { "—" }, null)
            ValueRow(stringResource(R.string.drive_serial), disk.serial.ifEmpty { "—" }, null)
            ValueRow(stringResource(R.string.drive_path), disk.path, null)
        }
        ValueRow(stringResource(R.string.drive_size), driveSize(drive, status), null)
        ValueRow(stringResource(R.string.drive_state), driveState(drive, false), null, showDivider = false)
    }
}

@Composable
private fun DriveCheckSection(check: BackupDriveCheck) {
    val context = LocalContext.current
    val filesystem = when (check.filesystem) {
        BackupDriveCheck.Filesystem.CLEAN -> R.string.drive_fs_clean
        BackupDriveCheck.Filesystem.ERRORS -> R.string.drive_fs_errors
        BackupDriveCheck.Filesystem.BUSY -> R.string.drive_fs_busy
        BackupDriveCheck.Filesystem.UNKNOWN -> R.string.drive_fs_unchecked
    }
    val smart = when (check.smart) {
        BackupDriveCheck.Smart.PASSED -> R.string.drive_smart_healthy
        BackupDriveCheck.Smart.FAILED -> R.string.drive_smart_failed
        BackupDriveCheck.Smart.NONE -> R.string.drive_smart_none
    }
    val speeds = check.writeBytesPerSecond > 0
    GroupedSection(header = stringResource(R.string.drive_check_header)) {
        ValueRow(stringResource(R.string.drive_filesystem), stringResource(filesystem), null)
        ValueRow(stringResource(R.string.drive_smart), stringResource(smart), null, showDivider = speeds)
        if (speeds) {
            val write = Formatter.formatFileSize(context, check.writeBytesPerSecond) + "/s"
            val read = Formatter.formatFileSize(context, check.readBytesPerSecond) + "/s"
            ValueRow(stringResource(R.string.drive_write_speed), write, null)
            ValueRow(stringResource(R.string.drive_read_speed), read, null, showDivider = false)
        }
    }
}

@Composable
private fun DriveActions(drive: BackupDrive, running: Boolean, run: RunDriveStep, forget: (String) -> Unit) {
    val uuid = drive.uuid ?: return
    val works = listOfNotNull(
        StorageAgentTasks.DriveWork.CHECK.takeIf { drive.state != BackupDrive.State.MISSING },
        StorageAgentTasks.DriveWork.ATTACH.takeIf { drive.state == BackupDrive.State.UNMOUNTED },
        StorageAgentTasks.DriveWork.EJECT.takeIf { drive.state == BackupDrive.State.READY },
        StorageAgentTasks.DriveWork.FORGET,
    )
    GroupedSection(footer = stringResource(R.string.drive_actions_note)) {
        works.forEachIndexed { index, work ->
            ActionRow(
                text = stringResource(workTitle(work)),
                enabled = !running,
                showDivider = index != works.lastIndex,
                onClick = {
                    val kind = if (work == StorageAgentTasks.DriveWork.CHECK) DriveRun.Check(drive.id) else DriveRun.Other
                    if (work == StorageAgentTasks.DriveWork.FORGET) forget(uuid) else run(kind, StorageAgentTasks.drive(work, uuid, drive.name))
                },
            )
        }
    }
}

private fun workTitle(work: StorageAgentTasks.DriveWork): Int = when (work) {
    StorageAgentTasks.DriveWork.CHECK -> R.string.drive_check
    StorageAgentTasks.DriveWork.ATTACH -> R.string.drive_connect
    StorageAgentTasks.DriveWork.EJECT -> R.string.drive_eject
    StorageAgentTasks.DriveWork.FORGET -> R.string.drive_forget
}

@Composable
private fun DriveFormatSection(drive: BackupDrive, drives: List<BackupDrive>, running: Boolean, run: RunDriveStep) {
    val disk = drive.disk ?: return
    val expected = disk.model.ifEmpty { disk.name }
    val suggested = if (drive.state == BackupDrive.State.BLANK) BackupDrives.suggestedName(drives.map { it.name }) else drive.name
    var name by remember(drive.id) { mutableStateOf(suggested) }
    var typed by remember(drive.id) { mutableStateOf("") }
    val confirmed = typed.trim().equals(expected, ignoreCase = true)
    GroupedSection(
        header = stringResource(R.string.drive_format_header),
        footer = stringResource(R.string.drive_format_note, expected),
    ) {
        FieldRow(label = stringResource(R.string.drive_name), value = name, onValueChange = { name = it })
        FieldRow(label = expected, value = typed, onValueChange = { typed = it }, placeholder = expected)
        ActionRow(
            text = stringResource(R.string.drive_format),
            danger = true,
            enabled = confirmed && BackupDrives.isValidName(name) && !running,
            showDivider = false,
            onClick = { run(DriveRun.Format(drive.id, drive.uuid, name), StorageAgentTasks.driveFormat(disk, name)) },
        )
    }
}
