package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.storage.StorageAgentTasks
import com.skaymer.gryonixnexus.app.storage.StorageState
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.catalog.storage.DiskFormatPlan
import com.skaymer.gryonixnexus.catalog.storage.DiskReleasePlan
import com.skaymer.gryonixnexus.catalog.storage.ServerDisk

/** What can be done to one disk */
private enum class DiskWork { FORMAT, RELEASE, BLINK }

/** One disk's facts, and formatting, disconnecting or finding it */
@Composable
internal fun DiskManageSheet(target: StorageRunTarget, state: StorageState, disk: ServerDisk, onClose: () -> Unit) {
    val hardware = state.hardware ?: return
    val free = disk in DiskFormatPlan.candidates(hardware)
    val releaseMount = DiskReleasePlan.mount(disk)
    val works = listOfNotNull(DiskWork.FORMAT.takeIf { free }, DiskWork.RELEASE.takeIf { releaseMount != null }, DiskWork.BLINK)
    var work by remember { mutableStateOf(DiskWork.BLINK) }
    var filesystem by remember { mutableStateOf(DiskFormatPlan.Filesystem.EXT4) }
    var typed by remember { mutableStateOf("") }
    var sign by remember { mutableStateOf(target.account.sign) }
    val word = stringResource(R.string.storage_erase_word)
    val plan = DiskFormatPlan.plan(disk, filesystem, hardware)
    val step = when (work) {
        DiskWork.FORMAT -> StorageAgentTasks.format(plan).takeIf { free && typed.trim().equals(word, ignoreCase = true) }
        DiskWork.RELEASE -> releaseMount?.let { StorageAgentTasks.release(DiskReleasePlan(it)) }
        DiskWork.BLINK -> StorageAgentTasks.blink(disk)
    }
    IOSSheet(
        title = disk.name,
        onClose = onClose,
        closeLabel = stringResource(R.string.access_cancel),
        action = SheetAction(
            title = workTitle(work),
            enabled = step != null && !state.running,
            destructive = work == DiskWork.FORMAT,
            onSelect = {
                step?.let { sign.run(target.model, target.server, target.host, it) }
                onClose()
            },
        ),
    ) {
        DiskFacts(disk)
        GroupedSection(footer = workNote(work, word)) {
            ChoiceRow(
                title = stringResource(R.string.disk_what_to_do),
                value = workTitle(work),
                options = works.map { option -> workTitle(option) to { work = option } },
                showDivider = work == DiskWork.FORMAT,
            )
            if (work == DiskWork.FORMAT) {
                ChoiceRow(
                    title = stringResource(R.string.disk_filesystem),
                    value = filesystemTitle(filesystem),
                    options = DiskFormatPlan.Filesystem.entries.map { fs -> filesystemTitle(fs) to { filesystem = fs } },
                )
                ValueRow(stringResource(R.string.disk_mounted_at), plan.mountPoint, null)
                FieldRow(label = word, value = typed, onValueChange = { typed = it }, placeholder = word, showDivider = false)
            }
        }
        GroupedSection(header = stringResource(R.string.storage_sign_in)) {
            StorageSignInRows(target.account, sign) { sign = it }
        }
    }
}

@Composable
private fun DiskFacts(disk: ServerDisk) {
    GroupedSection {
        ValueRow(stringResource(R.string.disk_model), disk.model.ifEmpty { "—" }, null)
        ValueRow(stringResource(R.string.disk_serial), disk.serial.ifEmpty { "—" }, null)
        ValueRow(stringResource(R.string.disk_size), diskDetail(disk), null)
        ValueRow(stringResource(R.string.disk_path), disk.path, null, showDivider = false)
    }
}

@Composable
private fun workTitle(work: DiskWork): String = stringResource(
    when (work) {
        DiskWork.FORMAT -> R.string.disk_format
        DiskWork.RELEASE -> R.string.disk_release
        DiskWork.BLINK -> R.string.disk_blink
    },
)

@Composable
private fun workNote(work: DiskWork, word: String): String = when (work) {
    DiskWork.FORMAT -> stringResource(R.string.disk_format_note, word)
    DiskWork.RELEASE -> stringResource(R.string.disk_release_note)
    DiskWork.BLINK -> stringResource(R.string.disk_blink_note)
}

@Composable
private fun filesystemTitle(filesystem: DiskFormatPlan.Filesystem): String = stringResource(
    when (filesystem) {
        DiskFormatPlan.Filesystem.EXT4 -> R.string.disk_fs_ext4
        DiskFormatPlan.Filesystem.XFS -> R.string.disk_fs_xfs
        DiskFormatPlan.Filesystem.BTRFS -> R.string.disk_fs_btrfs
    },
)
