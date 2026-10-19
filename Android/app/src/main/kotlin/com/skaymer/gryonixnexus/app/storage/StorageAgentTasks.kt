package com.skaymer.gryonixnexus.app.storage

import com.skaymer.gryonixnexus.app.install.StorageStep
import com.skaymer.gryonixnexus.catalog.storage.ArrayChange
import com.skaymer.gryonixnexus.catalog.storage.BackupDriveScripts
import com.skaymer.gryonixnexus.catalog.storage.DiskBlink
import com.skaymer.gryonixnexus.catalog.storage.DiskIdentity
import com.skaymer.gryonixnexus.catalog.storage.DiskFormatPlan
import com.skaymer.gryonixnexus.catalog.storage.DiskHealth
import com.skaymer.gryonixnexus.catalog.storage.DiskReleasePlan
import com.skaymer.gryonixnexus.catalog.storage.FastStorageMove
import com.skaymer.gryonixnexus.catalog.storage.FastStoragePlan
import com.skaymer.gryonixnexus.catalog.storage.FastStorageRestore
import com.skaymer.gryonixnexus.catalog.storage.RaidImportPlan
import com.skaymer.gryonixnexus.catalog.storage.RaidPlan
import com.skaymer.gryonixnexus.catalog.storage.RaidRepairPlan
import com.skaymer.gryonixnexus.catalog.storage.ServerDisk
import com.skaymer.gryonixnexus.catalog.storage.ServerHardware
import com.skaymer.gryonixnexus.catalog.storage.StorageArray
import com.skaymer.gryonixnexus.catalog.storage.spec
import gryonixnexusd.v1.ArrayChangeAction
import gryonixnexusd.v1.ArrayChangeTask
import gryonixnexusd.v1.CacheCleanupTask
import gryonixnexusd.v1.CacheMoveTask
import gryonixnexusd.v1.CacheProject
import gryonixnexusd.v1.CacheRestoreTask
import gryonixnexusd.v1.DiskBlinkTask
import gryonixnexusd.v1.DiskFormatTask
import gryonixnexusd.v1.DiskHealthTask
import gryonixnexusd.v1.DiskIdentity as WireDiskIdentity
import gryonixnexusd.v1.DiskReleaseTask
import gryonixnexusd.v1.DriveFormatTask
import gryonixnexusd.v1.DriveTask
import gryonixnexusd.v1.RaidCreateTask
import gryonixnexusd.v1.RaidImportTask
import gryonixnexusd.v1.RaidRepairTask
import gryonixnexusd.v1.StorageArrayKind
import gryonixnexusd.v1.StorageTaskKind
import gryonixnexusd.v1.StorageTaskRequest

/** Disk steps that the agent can run as root */
object StorageAgentTasks {
    fun diskHealth(paths: List<String>) = StorageStep(
        StorageStep.Kind.HEALTH, DiskHealth.script(paths), DiskHealth.DONE_MARKER,
        agentTask = StorageTaskRequest(
            kind = StorageTaskKind.STORAGE_TASK_KIND_DISK_HEALTH,
            disk_health = DiskHealthTask(disks = paths),
        ),
    )

    fun raid(plan: RaidPlan, kind: StorageStep.Kind = StorageStep.Kind.RAID) = StorageStep(
        kind, plan.script(), RaidPlan.DONE_MARKER,
        agentTask = StorageTaskRequest(
            kind = StorageTaskKind.STORAGE_TASK_KIND_RAID_CREATE,
            raid_create = RaidCreateTask(
                level = plan.level.number, disks = plan.disks.map { it.path },
                name = plan.name, mount_point = plan.mountPoint.orEmpty(), kind = kind(plan.kind),
                identities = plan.disks.map { wire(it.identity) },
            ),
        ),
    )

    fun importing(array: StorageArray): StorageStep {
        val zfs = array.kind == StorageArray.Kind.ZFS
        return StorageStep(
            StorageStep.Kind.IMPORT, RaidImportPlan(array).script(), RaidImportPlan.DONE_MARKER, array.name,
            agentTask = StorageTaskRequest(
                kind = StorageTaskKind.STORAGE_TASK_KIND_RAID_IMPORT,
                raid_import = RaidImportTask(
                    kind = kind(zfs), address = if (zfs) array.name else array.address, name = array.name,
                    uuid = array.uuid.orEmpty(), mount_point = RaidImportPlan(array).mountPoint.orEmpty(),
                ),
            ),
        )
    }

    fun repair(array: StorageArray, disk: ServerDisk): StorageStep {
        val zfs = array.kind == StorageArray.Kind.ZFS
        return StorageStep(
            StorageStep.Kind.RAID, RaidRepairPlan(array, disk).script(), RaidRepairPlan.DONE_MARKER,
            agentTask = StorageTaskRequest(
                kind = StorageTaskKind.STORAGE_TASK_KIND_RAID_REPAIR,
                raid_repair = RaidRepairTask(
                    kind = kind(zfs), address = if (zfs) array.name else array.address, name = array.name,
                    failed = array.failed.firstOrNull().orEmpty(), replacement = disk.path,
                    identities = listOf(wire(disk.identity)),
                ),
            ),
        )
    }

    private fun kind(zfs: Boolean) =
        if (zfs) StorageArrayKind.STORAGE_ARRAY_KIND_ZFS else StorageArrayKind.STORAGE_ARRAY_KIND_MD

    private fun kind(kind: StorageArray.Kind) = when (kind) {
        StorageArray.Kind.ZFS -> StorageArrayKind.STORAGE_ARRAY_KIND_ZFS
        StorageArray.Kind.BTRFS -> StorageArrayKind.STORAGE_ARRAY_KIND_BTRFS
        else -> StorageArrayKind.STORAGE_ARRAY_KIND_MD
    }

    private fun action(action: ArrayChange.Action) = when (action) {
        ArrayChange.Action.ADD_SPARE -> ArrayChangeAction.ARRAY_CHANGE_ACTION_ADD_SPARE
        ArrayChange.Action.GROW -> ArrayChangeAction.ARRAY_CHANGE_ACTION_GROW
        ArrayChange.Action.REPLACE -> ArrayChangeAction.ARRAY_CHANGE_ACTION_REPLACE
        ArrayChange.Action.DETACH -> ArrayChangeAction.ARRAY_CHANGE_ACTION_DETACH
        ArrayChange.Action.REMOVE -> ArrayChangeAction.ARRAY_CHANGE_ACTION_REMOVE
        ArrayChange.Action.CHANGE_LEVEL -> ArrayChangeAction.ARRAY_CHANGE_ACTION_CHANGE_LEVEL
        ArrayChange.Action.CHECK -> ArrayChangeAction.ARRAY_CHANGE_ACTION_CHECK
        ArrayChange.Action.DELETE -> ArrayChangeAction.ARRAY_CHANGE_ACTION_DELETE
    }

    fun change(change: ArrayChange, hardware: ServerHardware): StorageStep {
        val spec = change.spec(hardware)
        return StorageStep(
            StorageStep.Kind.CHANGE, spec.script(), ArrayChange.DONE_MARKER, change.array.name,
            agentTask = StorageTaskRequest(
                kind = StorageTaskKind.STORAGE_TASK_KIND_ARRAY_CHANGE,
                array_change = ArrayChangeTask(
                    action = action(spec.action), kind = kind(spec.kind), address = spec.address, name = spec.name,
                    level = spec.level, member = spec.member, disks = spec.disks, devices = maxOf(spec.devices, 0),
                    new_level = spec.newLevel, members = spec.members, check_disks = spec.checkDisks,
                    identities = spec.identities.map(::wire),
                ),
            ),
        )
    }

    fun format(plan: DiskFormatPlan) = StorageStep(
        StorageStep.Kind.CHANGE, plan.script(), DiskFormatPlan.DONE_MARKER,
        agentTask = StorageTaskRequest(
            kind = StorageTaskKind.STORAGE_TASK_KIND_DISK_FORMAT,
            disk_format = DiskFormatTask(
                disk = plan.disk, filesystem = plan.filesystem.raw, label = plan.label, mount_point = plan.mountPoint,
                identity = plan.identity?.let(::wire),
            ),
        ),
    )

    fun release(plan: DiskReleasePlan) = StorageStep(
        StorageStep.Kind.CHANGE, plan.script(), DiskReleasePlan.DONE_MARKER,
        agentTask = StorageTaskRequest(
            kind = StorageTaskKind.STORAGE_TASK_KIND_DISK_RELEASE,
            disk_release = DiskReleaseTask(mount_point = plan.mountPoint),
        ),
    )

    fun blink(disk: ServerDisk) = StorageStep(
        StorageStep.Kind.CHANGE, DiskBlink.script(disk.path), DiskBlink.DONE_MARKER,
        agentTask = StorageTaskRequest(
            kind = StorageTaskKind.STORAGE_TASK_KIND_DISK_BLINK,
            disk_blink = DiskBlinkTask(disk = disk.path),
        ),
    )

    fun cacheProbe(script: String, doneMarker: String) = StorageStep(
        StorageStep.Kind.CACHE, script, doneMarker,
        agentTask = StorageTaskRequest(kind = StorageTaskKind.STORAGE_TASK_KIND_CACHE_PROBE),
    )

    fun cacheMove(move: FastStorageMove) = StorageStep(
        StorageStep.Kind.CACHE, move.script(), FastStorageMove.DONE_MARKER,
        agentTask = StorageTaskRequest(
            kind = StorageTaskKind.STORAGE_TASK_KIND_CACHE_MOVE,
            cache_move = CacheMoveTask(
                device = (move.target as? FastStoragePlan.Target.Device)?.path.orEmpty(),
                folder_on = (move.target as? FastStoragePlan.Target.Folder)?.on.orEmpty(),
                projects = move.projects.map(::project),
            ),
        ),
    )

    fun cacheRestore(projects: List<FastStorageMove.Project>) = StorageStep(
        StorageStep.Kind.CACHE, FastStorageRestore.script(projects), FastStorageRestore.DONE_MARKER,
        agentTask = StorageTaskRequest(
            kind = StorageTaskKind.STORAGE_TASK_KIND_CACHE_RESTORE,
            cache_restore = CacheRestoreTask(projects = projects.map(::project)),
        ),
    )

    fun cacheCleanup(paths: List<String>) = StorageStep(
        StorageStep.Kind.CACHE, FastStorageRestore.cleanupScript(paths), FastStorageRestore.CLEANUP_DONE_MARKER,
        agentTask = StorageTaskRequest(
            kind = StorageTaskKind.STORAGE_TASK_KIND_CACHE_CLEANUP,
            cache_cleanup = CacheCleanupTask(paths = paths),
        ),
    )

    fun driveFormat(disk: ServerDisk, name: String) = StorageStep(
        StorageStep.Kind.CHANGE, BackupDriveScripts.format(disk.path, name, disk.identity), BackupDriveScripts.FORMAT_DONE,
        agentTask = StorageTaskRequest(
            kind = StorageTaskKind.STORAGE_TASK_KIND_DRIVE_FORMAT,
            drive_format = DriveFormatTask(disk = disk.path, name = name, identity = wire(disk.identity)),
        ),
    )

    enum class DriveWork { ATTACH, CHECK, EJECT, FORGET }

    fun drive(work: DriveWork, uuid: String, name: String): StorageStep {
        val (kind, script, marker) = when (work) {
            DriveWork.ATTACH -> Triple(StorageTaskKind.STORAGE_TASK_KIND_DRIVE_ATTACH, BackupDriveScripts.attach(uuid, name), BackupDriveScripts.ATTACH_DONE)
            DriveWork.CHECK -> Triple(StorageTaskKind.STORAGE_TASK_KIND_DRIVE_CHECK, BackupDriveScripts.check(uuid, name), BackupDriveScripts.CHECK_DONE)
            DriveWork.EJECT -> Triple(StorageTaskKind.STORAGE_TASK_KIND_DRIVE_EJECT, BackupDriveScripts.eject(uuid, name), BackupDriveScripts.EJECT_DONE)
            DriveWork.FORGET -> Triple(StorageTaskKind.STORAGE_TASK_KIND_DRIVE_FORGET, BackupDriveScripts.forget(uuid, name), BackupDriveScripts.FORGET_DONE)
        }
        return StorageStep(
            StorageStep.Kind.CHANGE, script, marker,
            agentTask = StorageTaskRequest(kind = kind, drive = DriveTask(uuid = uuid, name = name)),
        )
    }

    private fun wire(identity: DiskIdentity) =
        WireDiskIdentity(path = identity.path, serial = identity.serial, size_bytes = identity.sizeBytes)

    private fun project(project: FastStorageMove.Project) =
        CacheProject(directory = project.directory, hot_paths = project.hotPaths)
}
