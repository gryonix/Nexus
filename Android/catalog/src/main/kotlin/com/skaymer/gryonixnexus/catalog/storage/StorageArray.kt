package com.skaymer.gryonixnexus.catalog.storage

/** An md device as lsblk shows it under its members */
data class ArrayVolume(
    val name: String,
    val level: String,
    val mountpoint: String?,
    val filesystem: String?,
    val label: String?,
)

/** One RAID array or pool and how healthy it is */
data class StorageArray(
    val kind: Kind = Kind.MD,
    val name: String,
    val uuid: String?,
    /** `/dev/md127` while running, null while stopped */
    val device: String?,
    val level: String,
    val members: List<String>,
    val failed: List<String>,
    val slots: Int,
    val working: Int,
    val state: State,
    val mountpoint: String?,
    val filesystem: String?,
    /** Standby disks that take over a failed member */
    val spares: List<String> = emptyList(),
    /** Top-level groups of a ZFS pool, such as mirror pairs */
    val groups: Int = 1,
) {
    sealed interface State {
        data object Clean : State
        data object Degraded : State
        data class Rebuilding(val percent: Double) : State
        /** Reading every block for errors */
        data class Checking(val percent: Double) : State
        /** Found on the disks but not running */
        data object Stopped : State

        /** Nothing this account can read says */
        data object Unknown : State
    }

    /** What keeps the array together */
    enum class Kind { MD, ZFS, BTRFS, LVM, HARDWARE }

    val id: String get() = if (kind == Kind.MD) uuid ?: name else "${kind.name.lowercase()}:${uuid ?: name}"

    /** md and ZFS are brought back and repaired here */
    val repairsHere: Boolean get() = (kind == Kind.MD || kind == Kind.ZFS) && !isForeignSystemPool

    /** A TrueNAS system pool: never imported on this machine */
    val isForeignSystemPool: Boolean get() = kind == Kind.ZFS && name in setOf("boot-pool", "freenas-boot")

    /** Arrays this product builds for data or cache */
    val isStorage: Boolean get() = name == RaidPlan.STORAGE_NAME
    val isCacheMirror: Boolean get() = name == RaidPlan.CACHE_NAME

    /** Where assembling and mounting address it */
    val address: String get() = device ?: "/dev/md/$name"

    val needsAttention: Boolean
        get() = !isForeignSystemPool && (state == State.Degraded || state == State.Stopped)

    companion object {
        fun all(hardware: ServerHardware): List<StorageArray> =
            mdArrays(hardware) + PoolReader.zfs(hardware) + PoolReader.btrfs(hardware) +
                PoolReader.lvm(hardware) + PoolReader.controllers(hardware)

        private fun mdArrays(hardware: ServerHardware): List<StorageArray> {
            val active = MdstatReader.arrays(hardware.mdstat).map { array(it, hardware) }
            val claimed = (active.flatMap { it.members } + active.flatMap { it.failed } + active.flatMap { it.spares })
                .mapNotNull(hardware::diskPath).toSet()
            val running = active.mapNotNull { it.uuid }.toSet()
            val stopped = hardware.disks
                .filter { disk -> disk.raidUUID != null && disk.path !in claimed && disk.raidUUID !in running }
                .groupBy { it.raidUUID.orEmpty() }
                .values.mapNotNull(::stoppedArray)
                .sortedBy { it.name }
            return active + stopped
        }

        private fun array(entry: MdstatReader.Entry, hardware: ServerHardware): StorageArray {
            val volume = hardware.volumes.firstOrNull { it.name == entry.device }
            val memberDisks = entry.members.mapNotNull(hardware::diskPath).toSet()
            val memberDisk = hardware.disks.firstOrNull { it.path in memberDisks }
            return StorageArray(
                name = memberDisk?.raidName ?: entry.device, uuid = memberDisk?.raidUUID,
                device = "/dev/${entry.device}", level = entry.level, members = entry.members,
                failed = entry.failed, slots = entry.slots, working = entry.working,
                state = entry.state, mountpoint = volume?.mountpoint, filesystem = volume?.filesystem,
                spares = entry.spares,
            )
        }

        private fun stoppedArray(disks: List<ServerDisk>): StorageArray? {
            val first = disks.firstOrNull() ?: return null
            return StorageArray(
                name = first.raidName ?: "md", uuid = first.raidUUID, device = null, level = "",
                members = disks.map { it.path }, failed = emptyList(), slots = disks.size,
                working = disks.size, state = State.Stopped, mountpoint = null, filesystem = null,
            )
        }
    }
}

/** Reads running arrays out of /proc/mdstat */
internal object MdstatReader {
    data class Entry(
        val device: String,
        var level: String = "",
        val members: MutableList<String> = mutableListOf(),
        val failed: MutableList<String> = mutableListOf(),
        val spares: MutableList<String> = mutableListOf(),
        var slots: Int = 0,
        var working: Int = 0,
        var state: StorageArray.State = StorageArray.State.Clean,
    )

    private val COUNTS = Regex("""\[(\d+)/(\d+)]""")
    private val PROGRESS = Regex("""(recovery|resync|reshape|check) = +([0-9.]+)%""")

    fun arrays(text: String): List<Entry> {
        val entries = mutableListOf<Entry>()
        for (line in text.split("\n")) {
            val entry = header(line)
            if (entry != null) entries += entry else entries.lastOrNull()?.let { detail(line, it) }
        }
        return entries
    }

    private fun header(line: String): Entry? {
        val parts = line.split(" ").filter { it.isNotEmpty() }
        if (parts.size < 3 || !parts[0].startsWith("md") || parts[1] != ":") return null
        val entry = Entry(parts[0])
        for (word in parts.drop(2)) {
            if (word.startsWith("raid")) { entry.level = word; continue }
            val bracket = word.indexOf('[').takeIf { it >= 0 } ?: continue
            val path = "/dev/" + word.substring(0, bracket)
            when {
                word.endsWith("(F)") -> entry.failed += path
                word.endsWith("(S)") -> entry.spares += path
                else -> entry.members += path
            }
        }
        if (parts[2] == "inactive") entry.state = StorageArray.State.Stopped
        entry.slots = entry.members.size
        entry.working = entry.members.size
        return entry
    }

    private fun detail(line: String, entry: Entry) {
        COUNTS.find(line)?.let { match ->
            entry.slots = match.groupValues[1].toInt()
            entry.working = match.groupValues[2].toInt()
            if (entry.working < entry.slots && entry.state == StorageArray.State.Clean) {
                entry.state = StorageArray.State.Degraded
            }
        }
        PROGRESS.find(line)?.let { match ->
            val percent = match.groupValues[2].toDoubleOrNull() ?: 0.0
            entry.state = if (match.groupValues[1] == "check") StorageArray.State.Checking(percent)
            else StorageArray.State.Rebuilding(percent)
        }
    }
}
