package com.skaymer.gryonixnexus.catalog.storage

/** Arrays that are not md */
internal object PoolReader {
    // MARK: ZFS

    fun zfs(hardware: ServerHardware): List<StorageArray> {
        val mounts = zfsMounts(hardware.zfsMounts)
        val active = ZpoolReader.pools(hardware.zpoolStatus).map { pool ->
            StorageArray(
                kind = StorageArray.Kind.ZFS, name = pool.name, uuid = null, device = null,
                level = pool.level, members = pool.members, failed = pool.failed,
                slots = pool.members.size + pool.failed.size, working = pool.members.size,
                state = pool.state, mountpoint = mounts[pool.name], filesystem = "zfs",
                spares = pool.spares, groups = maxOf(pool.groups, 1),
            )
        }
        val running = active.map { it.name }.toSet()
        val stopped = hardware.blockNodes
            .filter { it.fstype == "zfs_member" && it.label.isNotEmpty() && it.label !in running }
            .groupBy { it.uuid.ifEmpty { it.label } }
            .values.map { nodes ->
                val first = nodes.first()
                StorageArray(
                    kind = StorageArray.Kind.ZFS, name = first.label, uuid = first.uuid.ifEmpty { null },
                    device = null, level = "", members = nodes.map { it.path }, failed = emptyList(),
                    slots = nodes.size, working = nodes.size, state = StorageArray.State.Stopped,
                    mountpoint = null, filesystem = "zfs",
                )
            }.sortedBy { it.name }
        return active + stopped
    }

    private fun zfsMounts(text: String): Map<String, String> =
        text.split("\n").mapNotNull { line ->
            val parts = line.split(" ", limit = 2)
            if (parts.size == 2 && parts[1].startsWith("/")) parts[0] to parts[1] else null
        }.toMap()

    // MARK: btrfs

    private data class BtrfsInfo(val profile: String, val devices: Int, val missing: Int)

    fun btrfs(hardware: ServerHardware): List<StorageArray> {
        val mounted = btrfsMounted(hardware.btrfsFilesystems)
        return hardware.blockNodes.filter { it.fstype == "btrfs" && it.uuid.isNotEmpty() }
            .groupBy { it.uuid }
            .mapNotNull { (uuid, nodes) ->
                val info = mounted[uuid]
                val slots = maxOf(info?.devices ?: 0, nodes.size)
                if (slots < 2) return@mapNotNull null
                val missing = info?.missing ?: 0
                val state = when {
                    info == null -> StorageArray.State.Unknown
                    missing > 0 -> StorageArray.State.Degraded
                    else -> StorageArray.State.Clean
                }
                StorageArray(
                    kind = StorageArray.Kind.BTRFS,
                    name = nodes.firstOrNull { it.label.isNotEmpty() }?.label ?: "btrfs",
                    uuid = uuid, device = null, level = info?.profile.orEmpty(),
                    members = nodes.map { it.path }, failed = emptyList(), slots = slots,
                    working = slots - missing, state = state,
                    mountpoint = nodes.firstNotNullOfOrNull { it.mountpoint }, filesystem = "btrfs",
                )
            }.sortedBy { it.name }
    }

    private fun btrfsMounted(text: String): Map<String, BtrfsInfo> =
        text.split("\n").mapNotNull { line ->
            val parts = line.split(" ")
            val devices = parts.getOrNull(2)?.toIntOrNull()
            if (parts.size != 4 || devices == null) null
            else parts[0] to BtrfsInfo(parts[1], devices, parts[3].toIntOrNull() ?: 0)
        }.toMap()

    // MARK: LVM

    private val RIMAGE = Regex("""_rimage_\d+$""")

    private data class LvmRow(val segtype: String, val health: String, val sync: Double?)

    /** RAID logical volumes, seen in lsblk as `vg-lv_rimage_N` */
    fun lvm(hardware: ServerHardware): List<StorageArray> {
        val report = lvmReport(hardware.lvmReport)
        return hardware.blockNodes.filter { it.type == "lvm" && RIMAGE.containsMatchIn(it.name) }
            .groupBy { it.name.substring(0, it.name.lastIndexOf("_rimage_")) }
            .map { (volume, nodes) ->
                val row = report[volume]
                val state = when {
                    row == null -> StorageArray.State.Unknown
                    row.health.isNotEmpty() -> StorageArray.State.Degraded
                    row.sync != null && row.sync < 100 -> StorageArray.State.Rebuilding(row.sync)
                    else -> StorageArray.State.Clean
                }
                val top = hardware.blockNodes.firstOrNull { it.name == volume }
                StorageArray(
                    kind = StorageArray.Kind.LVM, name = volume, uuid = null, device = "/dev/mapper/$volume",
                    level = row?.segtype.orEmpty(), members = nodes.map { it.disk }.distinct().sorted(),
                    failed = emptyList(), slots = nodes.size, working = nodes.size, state = state,
                    mountpoint = top?.mountpoint, filesystem = top?.fstype?.ifEmpty { null },
                )
            }.sortedBy { it.name }
    }

    private fun lvmReport(text: String): Map<String, LvmRow> =
        text.split("\n").mapNotNull { line ->
            val parts = line.split(";")
            if (parts.size < 5 || !parts[2].startsWith("raid")) null
            else mapperName(parts[0], parts[1]) to LvmRow(parts[2], parts[3], parts[4].toDoubleOrNull())
        }.toMap()

    /** Device-mapper doubles every dash inside a name */
    fun mapperName(vg: String, lv: String): String =
        vg.replace("-", "--") + "-" + lv.replace("-", "--")

    // MARK: RAID controllers

    val CONTROLLER_MODELS = listOf(
        "PERC", "MEGARAID", "LOGICAL VOLUME", "SERVERAID", "SMART ARRAY", "ADAPTEC", "ASR8", "MR9", "RAID",
    )

    /** A disk the controller made out of several */
    fun controllers(hardware: ServerHardware): List<StorageArray> =
        hardware.disks.filter { disk -> CONTROLLER_MODELS.any { it in disk.model.uppercase() } }
            .map { disk ->
                StorageArray(
                    kind = StorageArray.Kind.HARDWARE, name = disk.model, uuid = disk.path, device = disk.path,
                    level = "", members = listOf(disk.path), failed = emptyList(), slots = 1, working = 1,
                    state = StorageArray.State.Unknown, mountpoint = disk.dataMount,
                    filesystem = disk.filesystems.firstOrNull(),
                )
            }
}

/** Reads `zpool status -LP` with tabs turned into spaces */
internal object ZpoolReader {
    data class Pool(
        val name: String,
        var state: StorageArray.State = StorageArray.State.Clean,
        var level: String = "",
        val members: MutableList<String> = mutableListOf(),
        val failed: MutableList<String> = mutableListOf(),
        val spares: MutableList<String> = mutableListOf(),
        /** Top-level mirror or raidz groups */
        var groups: Int = 0,
    )

    private val GROUP_SECTIONS = setOf("logs", "cache", "spares", "special", "dedup")
    private val GROUP = Regex("""^(mirror|raidz[123]?|draid[123]?)""")
    private val DONE = Regex("""([0-9.]+)% done""")

    /** Work that a later `% done` line measures */
    private enum class Activity { IDLE, REBUILD, CHECK }

    private class Cursor(var inConfig: Boolean = false, var section: String = "", var progress: Activity = Activity.IDLE)

    fun pools(text: String): List<Pool> {
        val pools = mutableListOf<Pool>()
        var cursor = Cursor()
        for (raw in text.split("\n")) {
            val line = raw.trim()
            if (line.startsWith("pool:")) {
                pools += Pool(value(line))
                cursor = Cursor()
                continue
            }
            val pool = pools.lastOrNull() ?: continue
            line(line, pool, cursor)
        }
        return pools
    }

    private fun line(line: String, pool: Pool, cursor: Cursor) {
        val done = DONE.find(line)
        val started = activity(line)
        when {
            line.startsWith("state:") ->
                pool.state = if (value(line) == "ONLINE") StorageArray.State.Clean else StorageArray.State.Degraded
            started != null -> cursor.progress = started
            cursor.progress != Activity.IDLE && done != null -> {
                progress(pool, cursor.progress, done.groupValues[1].toDoubleOrNull() ?: 0.0)
                cursor.progress = Activity.IDLE
            }
            line.startsWith("config:") -> cursor.inConfig = true
            line.startsWith("errors:") -> cursor.inConfig = false
            cursor.inConfig -> device(line, cursor, pool)
        }
    }

    /** null when the line starts no scan, expansion or removal */
    private fun activity(line: String): Activity? {
        if (listOf("scan:", "expand:", "remove:").none { line.startsWith(it) }) return null
        if ("in progress" !in line) return Activity.IDLE
        return if (line.startsWith("scan:") && "scrub" in line) Activity.CHECK else Activity.REBUILD
    }

    private fun progress(pool: Pool, activity: Activity, percent: Double) {
        if (activity == Activity.REBUILD) pool.state = StorageArray.State.Rebuilding(percent)
        else if (pool.state == StorageArray.State.Clean) pool.state = StorageArray.State.Checking(percent)
    }

    private fun value(line: String): String = line.substringAfter(":").trim()

    private fun device(line: String, cursor: Cursor, pool: Pool) {
        val words = line.split(" ").filter { it.isNotEmpty() }
        val name = words.firstOrNull() ?: return
        if (name == "NAME" || name == pool.name) return
        if (name in GROUP_SECTIONS) { cursor.section = name; return }
        GROUP.find(name)?.let { group ->
            if (cursor.section.isEmpty()) pool.groups += 1
            if (pool.level.isEmpty()) pool.level = if (group.value == "raidz") "raidz1" else group.value
            return
        }
        if (words.size < 2) return
        if (!name.startsWith("/") && !name.all { it.isDigit() }) return
        if (cursor.section == "spares") {
            if (words[1] == "AVAIL") pool.spares += name
            return
        }
        if (words[1] == "ONLINE") pool.members += name else pool.failed += name
        if (pool.level.isEmpty() && cursor.section.isEmpty()) pool.level = "stripe"
        if (pool.level == "stripe" && cursor.section.isEmpty()) pool.groups += 1
    }
}
