package com.skaymer.gryonixnexus.catalog.storage

import com.skaymer.gryonixnexus.catalog.Apt
/** A software RAID array built from whole disks */
data class RaidPlan(
    val level: Level,
    val disks: List<ServerDisk>,
    val name: String = STORAGE_NAME,
    /** Where it is mounted; null leaves formatting to the caller */
    val mountPoint: String? = MOUNT_POINT,
    /** What builds it: mdadm, ZFS or btrfs */
    val kind: StorageArray.Kind = StorageArray.Kind.MD,
) {
    val device: String get() = "/dev/md/$name"

    enum class Level(val number: Int, val minimumDisks: Int) {
        RAID0(0, 2), RAID1(1, 2), RAID5(5, 3), RAID6(6, 4), RAID10(10, 4);

        /** Disks that may fail without losing data */
        fun survivableFailures(disks: Int): Int = when (this) {
            RAID0 -> 0
            RAID1 -> maxOf(disks - 1, 0)
            RAID5, RAID10 -> 1
            RAID6 -> 2
        }

        /** Failures survived when built as `kind` */
        fun survivableFailures(disks: Int, kind: StorageArray.Kind): Int =
            if (kind == StorageArray.Kind.BTRFS && this == RAID1) (if (disks >= 2) 1 else 0)
            else survivableFailures(disks)

        /** Space left for data when built as `kind` */
        fun usableBytes(sizes: List<Long>, kind: StorageArray.Kind): Long {
            val total = sizes.sum()
            return when {
                this == RAID0 && (kind == StorageArray.Kind.ZFS || kind == StorageArray.Kind.BTRFS) -> total
                this == RAID1 && kind == StorageArray.Kind.BTRFS -> minOf(total / 2, total - (sizes.maxOrNull() ?: 0))
                else -> usableBytes(sizes)
            }
        }

        fun usableBytes(sizes: List<Long>): Long {
            val smallest = sizes.minOrNull() ?: return 0
            val count = sizes.size.toLong()
            return when (this) {
                RAID0 -> smallest * count
                RAID1 -> smallest
                RAID5 -> smallest * (count - 1)
                RAID6 -> smallest * (count - 2)
                RAID10 -> smallest * (count / 2)
            }
        }

        companion object {
            fun of(number: Int): Level? = entries.firstOrNull { it.number == number }
        }
    }

    val isValid: Boolean
        get() = level in levels(kind) && disks.size >= level.minimumDisks &&
            (level != Level.RAID10 || disks.size % 2 == 0)

    val usableBytes: Long get() = level.usableBytes(disks.map { it.sizeBytes }, kind)

    val survivableFailures: Int get() = level.survivableFailures(disks.size, kind)

    fun script(): String = when (kind) {
        StorageArray.Kind.ZFS -> RaidPools.zfsScript(this)
        StorageArray.Kind.BTRFS -> RaidPools.btrfsScript(this)
        else -> mdScript()
    }

    private fun mdScript(): String {
        val members = disks.joinToString(" ") { FastStoragePlan.quoted(it.path) }
        val lines = mutableListOf("#!/bin/bash", "set -euo pipefail", "ARRAY=${FastStoragePlan.quoted(device)}")
        mountPoint?.let { lines += "MOUNT=${FastStoragePlan.quoted(it)}" }
        lines += ArrayScript.diskGuard(disks.map { it.identity }) + installLines() + createLines(members)
        if (mountPoint != null) lines += mountLines()
        lines += "echo $DONE_MARKER"
        return lines.joinToString("\n") + "\n"
    }

    private fun createLines(members: String) = listOf(
        "if [ ! -e \"\$ARRAY\" ]; then",
    ) + ArrayScript.checkAll(members) + listOf(
        "  for disk in $members; do",
        "    wipefs -a -q \"\$disk\"",
        "  done",
        "  mdadm --create \"\$ARRAY\" --name=$name --metadata=1.2 --run " +
            "--level=${level.number} --raid-devices=${disks.size} $members",
        "  wipefs -a -q \"\$ARRAY\"",
    ) + (if (mountPoint == null) emptyList() else listOf("  mkfs.ext4 -q -L gnx-storage \"\$ARRAY\"")) + listOf(
        "  install -d /etc/mdadm",
        "  mdadm --detail --brief \"\$ARRAY\" >> /etc/mdadm/mdadm.conf",
        "  update-initramfs -u >/dev/null 2>&1 || true",
        "fi",
    )

    companion object {
        internal fun installLines() = listOf(
            "if ! command -v mdadm >/dev/null 2>&1; then",
            "  ${Apt.QUIET} install -y -q mdadm",
            "fi",
        )
        internal fun mountLines() = listOf(
            "install -d \"\$MOUNT\"",
            "uuid=\"\$(blkid -s UUID -o value \"\$ARRAY\")\"",
            "grep -q \"UUID=\$uuid \$MOUNT \" /etc/fstab || echo \"UUID=\$uuid \$MOUNT ext4 defaults,nofail 0 2\" >> /etc/fstab",
            "mountpoint -q \"\$MOUNT\" || mount \"\$MOUNT\"",
        )

        const val STORAGE_NAME = "gryonixnexus"
        const val CACHE_NAME = "gnx-fast"
        const val MOUNT_POINT = "/srv/gryonixnexus-storage"
        const val DONE_MARKER = "GRYONIXNEXUS_RAID_DONE"

        /** Kinds of array this app can build */
        val BUILDABLE_KINDS = listOf(StorageArray.Kind.MD, StorageArray.Kind.ZFS, StorageArray.Kind.BTRFS)

        /** Levels offered per kind, without btrfs RAID 5 and 6 */
        fun levels(kind: StorageArray.Kind): List<Level> =
            if (kind == StorageArray.Kind.BTRFS) listOf(Level.RAID0, Level.RAID1, Level.RAID10) else Level.entries

        /** Two fast disks mirrored for the cache */
        fun cacheMirror(disks: List<ServerDisk>) = RaidPlan(Level.RAID1, disks, CACHE_NAME, null)

        /** Disks that may be wiped for an array */
        fun candidates(hardware: ServerHardware): List<ServerDisk> =
            hardware.disks.filter { !it.isSystem && !it.raidMember && it.dataMount == null }

        /** A storage array under the first free name and mount */
        fun storage(
            level: Level,
            disks: List<ServerDisk>,
            hardware: ServerHardware,
            kind: StorageArray.Kind = StorageArray.Kind.MD,
        ): RaidPlan {
            val names = StorageArray.all(hardware).map { it.name }.toSet()
            val mounts = (hardware.volumes.mapNotNull { it.mountpoint } + hardware.disks.flatMap { it.mountpoints }).toSet()
            return generateSequence(1) { it + 1 }
                .map { if (it == 1) "" else it.toString() }
                .first { STORAGE_NAME + it !in names && MOUNT_POINT + it !in mounts }
                .let { RaidPlan(level, disks, STORAGE_NAME + it, MOUNT_POINT + it, kind) }
        }
    }
}
