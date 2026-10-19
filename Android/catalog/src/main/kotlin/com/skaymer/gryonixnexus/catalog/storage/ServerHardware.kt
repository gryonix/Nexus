package com.skaymer.gryonixnexus.catalog.storage

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.longOrNull

/** One whole disk the server reports */
data class ServerDisk(
    val name: String,
    val path: String,
    val sizeBytes: Long,
    val kind: Kind,
    val model: String,
    /** Mount points of the disk and its partitions */
    val mountpoints: List<String>,
    val filesystems: List<String>,
    val partitionCount: Int,
    val raidMember: Boolean,
    /** Filesystem labels on the disk and its partitions */
    val labels: List<String> = emptyList(),
    /** The array this disk belongs to, as mdadm's UUID */
    val raidUUID: String? = null,
    /** The array's name without its host prefix */
    val raidName: String? = null,
    /** Serial number printed on the disk's label */
    val serial: String = "",
    /** USB, hot-pluggable or marked removable by the kernel */
    val removable: Boolean = false,
) {
    enum class Kind { NVME, SSD, HDD }

    /** A cache disk a past install left behind */
    val isEarlierCache: Boolean
        get() = FastStoragePlan.LABEL in labels && dataMount == null && !isSystem

    val identity: DiskIdentity get() = DiskIdentity(path, serial.filterNot(Char::isWhitespace), sizeBytes)

    val isSystem: Boolean get() = mountpoints.any { it in SYSTEM_MOUNTS }
    val isBlank: Boolean get() = partitionCount == 0 && filesystems.isEmpty() && !raidMember
    val isFast: Boolean get() = kind != Kind.HDD

    /** A mounted data filesystem that is not the system */
    val dataMount: String? get() = if (isSystem) null else mountpoints.firstOrNull { it.startsWith("/") }

    companion object {
        val SYSTEM_MOUNTS = setOf("/", "/boot", "/boot/efi", "/usr", "/var", "[SWAP]")
    }
}

/** One lsblk row, with the whole disk it sits on */
data class BlockNode(
    val name: String,
    val path: String,
    val type: String,
    val fstype: String,
    val label: String,
    val uuid: String,
    val mountpoint: String?,
    /** Path of the disk this node lives on */
    val disk: String,
)

/** What a server is built from, read before installing */
data class ServerHardware(
    val cpuCores: Int,
    val memoryBytes: Long,
    val architecture: String,
    val rootFreeBytes: Long,
    val disks: List<ServerDisk>,
    /** Assembled md devices seen under their member disks */
    val volumes: List<ArrayVolume> = emptyList(),
    /** The raw /proc/mdstat text */
    val mdstat: String = "",
    val blockNodes: List<BlockNode> = emptyList(),
    /** `zpool status -LP` */
    val zpoolStatus: String = "",
    /** `zfs list -d 0`: pool and mountpoint per line */
    val zfsMounts: String = "",
    /** Mounted btrfs filesystems: uuid, data profile, devices, missing */
    val btrfsFilesystems: String = "",
    /** `lvs` for RAID volumes; empty without passwordless sudo */
    val lvmReport: String = "",
    /** The background disk job, if one ran */
    val diskJob: DiskJob? = null,
    /** Swap space the machine already has */
    val swapBytes: Long = 0,
) {
    /** The whole disk a disk or partition path sits on */
    fun diskPath(containing: String): String? =
        if (disks.any { it.path == containing }) containing
        else blockNodes.firstOrNull { it.path == containing }?.disk

    companion object {
        const val BEGIN_MARKER = "GRYONIXNEXUS_HW_BEGIN"
        const val END_MARKER = "GRYONIXNEXUS_HW_END"

        /** Read-only probe; prints key=value lines between markers */
        val PROBE_COMMAND = listOf(
            "echo $BEGIN_MARKER",
            "echo \"cpu=\$(nproc 2>/dev/null || echo 0)\"",
            "echo \"mem=\$(awk '/^MemTotal:/ {printf \"%.0f\", \$2 * 1024}' /proc/meminfo 2>/dev/null)\"",
            "echo \"swap=\$(awk '/^SwapTotal:/ {printf \"%.0f\", \$2 * 1024}' /proc/meminfo 2>/dev/null)\"",
            "echo \"arch=\$(uname -m)\"",
            "echo \"rootfree=\$(df -B1 --output=avail / 2>/dev/null | tail -n 1 | tr -d ' ')\"",
            "echo \"lsblk=\$(lsblk -J -b -o NAME,PATH,SIZE,ROTA,TYPE,MOUNTPOINT,FSTYPE,LABEL,UUID,MODEL,TRAN,SERIAL,RM,HOTPLUG 2>/dev/null | tr -d '\\n')\"",
            "echo \"mdstat=\$(cat /proc/mdstat 2>/dev/null | tr '\\n' '|')\"",
            "echo \"zpool=\$(zpool status -LP 2>/dev/null | tr '\\t\\n' ' |')\"",
            "echo \"zfsmount=\$(zfs list -H -d 0 -o name,mountpoint 2>/dev/null | tr '\\t\\n' ' |')\"",
            "echo \"btrfs=\$(for d in \$(ls -d /sys/fs/btrfs/*-* 2>/dev/null); do " +
                "printf '%s %s %s %s|' \"\${d##*/}\" " +
                "\"\$(ls \"\$d/allocation/data\" 2>/dev/null | grep -xE 'dup|raid[0-9c]+' | head -n 1)\" " +
                "\"\$(ls \"\$d/devinfo\" 2>/dev/null | wc -l | tr -d ' ')\" " +
                "\"\$(cat \"\$d\"/devinfo/*/missing 2>/dev/null | grep -c 1)\"; done)\"",
            "echo \"lvm=\$(sudo -n lvs --noheadings --separator ';' " +
                "-o vg_name,lv_name,segtype,lv_health_status,sync_percent 2>/dev/null | tr -d ' ' | tr '\\n' '|')\"",
            DiskJob.PROBE_LINE,
            "echo $END_MARKER",
        ).joinToString("; ")

        fun parse(output: String): ServerHardware? {
            val begin = output.indexOf(BEGIN_MARKER).takeIf { it >= 0 } ?: return null
            val end = output.indexOf(END_MARKER, begin + BEGIN_MARKER.length).takeIf { it >= 0 } ?: return null
            val fields = output.substring(begin + BEGIN_MARKER.length, end).split("\n")
                .mapNotNull { line ->
                    val equals = line.indexOf('=')
                    if (equals < 0) null else line.substring(0, equals).trim() to line.substring(equals + 1)
                }.toMap()
            val parsed = ServerHardware(
                cpuCores = fields["cpu"]?.trim()?.toIntOrNull() ?: 0,
                memoryBytes = fields["mem"]?.trim()?.toLongOrNull() ?: 0,
                architecture = fields["arch"]?.trim().orEmpty(),
                rootFreeBytes = fields["rootfree"]?.trim()?.toLongOrNull() ?: 0,
                disks = LsblkReader.disks(fields["lsblk"].orEmpty()),
                volumes = LsblkReader.volumes(fields["lsblk"].orEmpty()),
                mdstat = fields["mdstat"].orEmpty().replace("|", "\n"),
                blockNodes = LsblkReader.nodes(fields["lsblk"].orEmpty()),
                zpoolStatus = fields["zpool"].orEmpty().replace("|", "\n"),
                zfsMounts = fields["zfsmount"].orEmpty().replace("|", "\n"),
                btrfsFilesystems = fields["btrfs"].orEmpty().replace("|", "\n"),
                lvmReport = fields["lvm"].orEmpty().replace("|", "\n"),
                diskJob = fields["diskjob"]?.let(DiskJob::parse),
                swapBytes = fields["swap"]?.trim()?.toLongOrNull() ?: 0,
            )
            val pooled = StorageArray.all(parsed).filter { it.kind != StorageArray.Kind.HARDWARE && !it.isForeignSystemPool }
                .flatMap { it.members + it.failed + it.spares }.mapNotNull(parsed::diskPath).toSet()
            return parsed.copy(disks = parsed.disks.map { if (it.path in pooled) it.copy(raidMember = true) else it })
        }
    }
}

/** Turns `lsblk -J` output into whole disks */
internal object LsblkReader {
    fun disks(json: String): List<ServerDisk> = devices(json).mapNotNull(::disk)

    /** Every node under every real disk, tagged with that disk */
    fun nodes(json: String): List<BlockNode> =
        devices(json).filter { disk(it) != null }.flatMap { device ->
            val diskPath = text(device["path"]).ifEmpty { "/dev/${text(device["name"])}" }
            (listOf(device) + descendants(children(device))).map { node ->
                val name = text(node["name"])
                BlockNode(
                    name = name, path = text(node["path"]).ifEmpty { "/dev/$name" },
                    type = text(node["type"]), fstype = text(node["fstype"]),
                    label = text(node["label"]), uuid = text(node["uuid"]),
                    mountpoint = text(node["mountpoint"]).ifEmpty { null }, disk = diskPath,
                )
            }
        }

    /** Every md device, once, with its mount and filesystem */
    fun volumes(json: String): List<ArrayVolume> =
        descendants(devices(json))
            .filter { text(it["type"]).startsWith("raid") }
            .distinctBy { text(it["name"]) }
            .map {
                ArrayVolume(
                    name = text(it["name"]), level = text(it["type"]),
                    mountpoint = text(it["mountpoint"]).ifEmpty { null },
                    filesystem = text(it["fstype"]).ifEmpty { null },
                    label = text(it["label"]).ifEmpty { null },
                )
            }

    private fun devices(json: String): List<JsonObject> {
        val root = runCatching { Json.parseToJsonElement(json).jsonObject }.getOrNull() ?: return emptyList()
        return (root["blockdevices"] as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()
    }

    /** lsblk's dashed UUID in mdadm's colon form */
    fun mdadmUUID(dashed: String): String? {
        val hex = dashed.replace("-", "")
        if (hex.length != 32) return null
        return hex.chunked(8).joinToString(":")
    }

    private fun disk(device: JsonObject): ServerDisk? {
        if (text(device["type"]) != "disk") return null
        val name = text(device["name"])
        if (name.startsWith("zram") || name.startsWith("loop")) return null
        val children = children(device)
        val nodes = listOf(device) + descendants(children)
        val filesystems = nodes.map { text(it["fstype"]) }.filter { it.isNotEmpty() }
        val member = nodes.firstOrNull { text(it["fstype"]) == "linux_raid_member" }
        return ServerDisk(
            name = name,
            path = text(device["path"]).ifEmpty { "/dev/$name" },
            sizeBytes = number(device["size"]),
            kind = kind(device),
            model = text(device["model"]).trim(),
            mountpoints = nodes.map { text(it["mountpoint"]) }.filter { it.isNotEmpty() },
            filesystems = filesystems,
            partitionCount = children.count { text(it["type"]) == "part" },
            raidMember = "linux_raid_member" in filesystems || nodes.any { text(it["type"]).startsWith("raid") },
            labels = nodes.filter { !text(it["type"]).startsWith("raid") }
                .map { text(it["label"]) }.filter { it.isNotEmpty() },
            raidUUID = member?.let { mdadmUUID(text(it["uuid"])) },
            raidName = member?.let { text(it["label"]).split(":").last() },
            serial = text(device["serial"]).trim(),
            removable = flag(device["rm"]) || flag(device["hotplug"]) || text(device["tran"]) == "usb",
        )
    }

    private fun children(node: JsonObject): List<JsonObject> =
        (node["children"] as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()

    private fun descendants(nodes: List<JsonObject>): List<JsonObject> =
        nodes.flatMap { listOf(it) + descendants(children(it)) }

    private fun kind(device: JsonObject): ServerDisk.Kind = when {
        text(device["tran"]) == "nvme" || text(device["name"]).startsWith("nvme") -> ServerDisk.Kind.NVME
        flag(device["rota"]) -> ServerDisk.Kind.HDD
        else -> ServerDisk.Kind.SSD
    }

    private fun text(value: JsonElement?): String = (value as? JsonPrimitive)?.contentOrNull ?: ""

    private fun number(value: JsonElement?): Long {
        val primitive = value as? JsonPrimitive ?: return 0
        return primitive.longOrNull ?: primitive.contentOrNull?.toLongOrNull() ?: 0
    }

    private fun flag(value: JsonElement?): Boolean {
        val primitive = value as? JsonPrimitive ?: return false
        return primitive.booleanOrNull ?: (primitive.contentOrNull == "1")
    }
}
