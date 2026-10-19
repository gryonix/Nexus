package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.catalog.storage.ArrayChange
import com.skaymer.gryonixnexus.catalog.storage.DiskJob
import com.skaymer.gryonixnexus.catalog.storage.ServerHardware
import com.skaymer.gryonixnexus.catalog.storage.StorageArray

@Composable
internal fun changeTitle(action: ArrayChange.Action): String = stringResource(
    when (action) {
        ArrayChange.Action.ADD_SPARE -> R.string.storage_change_add_spare
        ArrayChange.Action.GROW -> R.string.storage_change_grow
        ArrayChange.Action.REPLACE -> R.string.storage_change_replace
        ArrayChange.Action.DETACH -> R.string.storage_change_detach
        ArrayChange.Action.REMOVE -> R.string.storage_change_remove
        ArrayChange.Action.CHANGE_LEVEL -> R.string.storage_change_level
        ArrayChange.Action.CHECK -> R.string.storage_change_check
        ArrayChange.Action.DELETE -> R.string.storage_change_delete
    },
)

@Composable
internal fun changeExplanation(action: ArrayChange.Action): String = stringResource(
    when (action) {
        ArrayChange.Action.ADD_SPARE -> R.string.storage_change_add_spare_note
        ArrayChange.Action.GROW -> R.string.storage_change_grow_note
        ArrayChange.Action.REPLACE -> R.string.storage_change_replace_note
        ArrayChange.Action.DETACH -> R.string.storage_change_detach_note
        ArrayChange.Action.REMOVE -> R.string.storage_change_remove_note
        ArrayChange.Action.CHANGE_LEVEL -> R.string.storage_change_level_note
        ArrayChange.Action.CHECK -> R.string.storage_change_check_note
        ArrayChange.Action.DELETE -> R.string.storage_change_delete_note
    },
)

@Composable
internal fun kindTitle(kind: StorageArray.Kind): String = when (kind) {
    StorageArray.Kind.ZFS -> "ZFS"
    StorageArray.Kind.BTRFS -> "Btrfs"
    else -> stringResource(R.string.storage_kind_md)
}

@Composable
internal fun kindNote(kind: StorageArray.Kind): String = stringResource(
    when (kind) {
        StorageArray.Kind.ZFS -> R.string.storage_kind_zfs_note
        StorageArray.Kind.BTRFS -> R.string.storage_kind_btrfs_note
        else -> R.string.storage_kind_md_note
    },
)

@Composable
internal fun jobTitle(job: DiskJob): String {
    val action = ArrayChange.Action.of(job.action)?.let { changeTitle(it) } ?: job.action
    return "$action — ${job.target}"
}

@Composable
internal fun jobOutcome(job: DiskJob): String = stringResource(
    when (job.outcome) {
        DiskJob.Outcome.RUNNING -> R.string.storage_job_running
        DiskJob.Outcome.DONE -> R.string.storage_job_done
        DiskJob.Outcome.FAILED -> R.string.storage_job_failed
    },
)

/** A member as name, model and serial number */
@Composable
internal fun memberTitle(path: String, hardware: ServerHardware?): String {
    val name = path.removePrefix("/dev/")
    val disk = hardware?.let { h -> h.disks.firstOrNull { it.path == h.diskPath(path) } } ?: return name
    val serial = disk.serial.takeIf { it.isNotEmpty() }?.let { stringResource(R.string.storage_serial_short, it) }
    return listOfNotNull(name, disk.model.ifEmpty { null }, serial).joinToString(" · ")
}
