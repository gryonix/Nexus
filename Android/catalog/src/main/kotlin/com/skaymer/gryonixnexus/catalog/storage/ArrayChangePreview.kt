package com.skaymer.gryonixnexus.catalog.storage

/** Space and protection before and after the change */
data class ArrayChangePreview(
    val usableBefore: Long,
    val usableAfter: Long,
    val failuresBefore: Int,
    val failuresAfter: Int,
    /** Hours on big disks; the server keeps working */
    val takesLong: Boolean,
    /** The array's folder is offline for a few minutes */
    val goesOffline: Boolean,
)

fun ArrayChange.preview(hardware: ServerHardware): ArrayChangePreview {
    val size = { path: String ->
        val disk = hardware.diskPath(path)
        hardware.disks.firstOrNull { it.path == disk }?.sizeBytes ?: 0L
    }
    val before = array.members.map(size)
    val after = when (action) {
        ArrayChange.Action.GROW, ArrayChange.Action.CHANGE_LEVEL -> before + disks.map { it.sizeBytes }
        ArrayChange.Action.REMOVE -> array.members.filter { it != member }.map(size)
        else -> before
    }
    val kind = array.kind
    val current = array.raidLevel
    val next = if (action == ArrayChange.Action.CHANGE_LEVEL) level ?: current else current
    val failuresBefore = current?.survivableFailures(before.size, kind) ?: 0
    val failuresAfter = if (action == ArrayChange.Action.DETACH) maxOf(failuresBefore - 1, 0)
    else next?.survivableFailures(after.size, kind) ?: 0
    return ArrayChangePreview(
        usableBefore = current?.usableBytes(before, kind) ?: 0,
        usableAfter = next?.usableBytes(after, kind) ?: 0,
        failuresBefore = failuresBefore,
        failuresAfter = failuresAfter,
        takesLong = takesLong,
        goesOffline = action == ArrayChange.Action.REMOVE && kind == StorageArray.Kind.MD &&
            (current == RaidPlan.Level.RAID5 || current == RaidPlan.Level.RAID6),
    )
}

internal val ArrayChange.takesLong: Boolean
    get() = when (action) {
        ArrayChange.Action.GROW, ArrayChange.Action.REPLACE, ArrayChange.Action.CHANGE_LEVEL,
        ArrayChange.Action.CHECK -> true
        ArrayChange.Action.REMOVE -> array.raidLevel != RaidPlan.Level.RAID1
        else -> false
    }

/** The same change as flat fields for the agent */
fun ArrayChange.spec(hardware: ServerHardware): ArrayChangeSpec {
    val wholeDisks = array.members.filter { it != member }.mapNotNull(hardware::diskPath).toSortedSet()
    val attachTo = action == ArrayChange.Action.GROW && array.kind == StorageArray.Kind.ZFS &&
        array.raidLevel == RaidPlan.Level.RAID1
    return ArrayChangeSpec(
        action = action, kind = array.kind,
        address = when (array.kind) {
            StorageArray.Kind.ZFS -> array.name
            StorageArray.Kind.BTRFS -> array.mountpoint.orEmpty()
            else -> array.address
        },
        name = RaidImportPlan.safeName(array.name), level = array.level,
        member = if (attachTo) array.members.firstOrNull().orEmpty() else member.orEmpty(),
        disks = disks.map { it.path }, devices = devicesAfter, newLevel = level?.number ?: 0,
        members = if (action == ArrayChange.Action.DELETE) array.members + array.spares else emptyList(),
        checkDisks = if (takesLong && action != ArrayChange.Action.CHECK) wholeDisks.toList() else emptyList(),
        identities = disks.map { it.identity },
    )
}

/** md member count once the change is done */
private val ArrayChange.devicesAfter: Int
    get() {
        if (array.kind != StorageArray.Kind.MD) return 0
        return when (action) {
            ArrayChange.Action.GROW -> array.members.size + 1
            ArrayChange.Action.REMOVE -> array.members.size - 1
            ArrayChange.Action.CHANGE_LEVEL -> if (level == RaidPlan.Level.RAID5) 3 else array.members.size + 1
            else -> 0
        }
    }
