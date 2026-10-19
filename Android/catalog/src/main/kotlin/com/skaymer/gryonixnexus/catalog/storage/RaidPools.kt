package com.skaymer.gryonixnexus.catalog.storage

import com.skaymer.gryonixnexus.catalog.Apt
/** ZFS pools and btrfs filesystems built from whole disks */
internal object RaidPools {
    private fun q(text: String) = FastStoragePlan.quoted(text)

    /** How `zpool create` lays the disks out */
    fun zfsLayout(plan: RaidPlan): String {
        val paths = plan.disks.map { q(it.path) }
        return when (plan.level) {
            RaidPlan.Level.RAID0 -> paths.joinToString(" ")
            RaidPlan.Level.RAID1 -> "mirror " + paths.joinToString(" ")
            RaidPlan.Level.RAID5 -> "raidz1 " + paths.joinToString(" ")
            RaidPlan.Level.RAID6 -> "raidz2 " + paths.joinToString(" ")
            RaidPlan.Level.RAID10 -> paths.chunked(2).filter { it.size == 2 }
                .joinToString(" ") { "mirror ${it[0]} ${it[1]}" }
        }
    }

    fun zfsScript(plan: RaidPlan): String {
        val members = plan.disks.joinToString(" ") { q(it.path) }
        return (
            listOf(
                "#!/bin/bash",
                "set -euo pipefail",
                "POOL=${q(plan.name)}",
                "MOUNT=${q(plan.mountPoint ?: RaidPlan.MOUNT_POINT)}",
            ) + ArrayScript.diskGuard(plan.disks.map { it.identity }) + ZfsTools.installLines() + listOf(
                "if ! modprobe zfs >/dev/null 2>&1; then",
                "  echo \"This kernel has no ZFS module. Install zfs-dkms, or pick another kind of array.\"",
                "  exit 3",
                "fi",
                "if ! zpool list -H \"\$POOL\" >/dev/null 2>&1; then",
            ) + ArrayScript.checkAll(members) + listOf(
                "  for disk in $members; do",
                "    wipefs -a -q \"\$disk\"",
                "  done",
                "  zpool create -f -o ashift=12 -O compression=lz4 -O atime=off -m \"\$MOUNT\" \"\$POOL\" ${zfsLayout(plan)}",
                "fi",
                "zpool set cachefile=/etc/zfs/zpool.cache \"\$POOL\" || true",
                "echo ${RaidPlan.DONE_MARKER}",
            )
            ).joinToString("\n") + "\n"
    }

    /** btrfs keeps metadata mirrored even under RAID 0 */
    fun btrfsProfiles(plan: RaidPlan): String = when (plan.level) {
        RaidPlan.Level.RAID10 -> "-d raid10 -m raid10"
        RaidPlan.Level.RAID0 -> "-d raid0 -m raid1"
        else -> "-d raid1 -m raid1"
    }

    fun btrfsScript(plan: RaidPlan): String {
        val members = plan.disks.joinToString(" ") { q(it.path) }
        return (
            listOf(
                "#!/bin/bash",
                "set -euo pipefail",
                "NAME=${q(plan.name)}",
                "MOUNT=${q(plan.mountPoint ?: RaidPlan.MOUNT_POINT)}",
                "FIRST=${q(plan.disks.firstOrNull()?.path.orEmpty())}",
            ) + ArrayScript.diskGuard(plan.disks.map { it.identity }) + btrfsInstallLines() + listOf(
                "if [ \"\$(blkid -s LABEL -o value \"\$FIRST\" || true)\" != \"\$NAME\" ]; then",
            ) + ArrayScript.checkAll(members) + listOf(
                "  for disk in $members; do",
                "    wipefs -a -q \"\$disk\"",
                "  done",
                "  mkfs.btrfs -q -f -L \"\$NAME\" ${btrfsProfiles(plan)} $members",
                "  udevadm settle",
                "fi",
                "btrfs device scan >/dev/null",
                "install -d \"\$MOUNT\"",
                "uuid=\"\$(blkid -s UUID -o value \"\$FIRST\")\"",
                "grep -q \"UUID=\$uuid \$MOUNT \" /etc/fstab || echo \"UUID=\$uuid \$MOUNT btrfs defaults,nofail 0 0\" >> /etc/fstab",
                "mountpoint -q \"\$MOUNT\" || mount \"\$MOUNT\"",
                "echo ${RaidPlan.DONE_MARKER}",
            )
            ).joinToString("\n") + "\n"
    }

    /** btrfs tools, installed when a btrfs array is built */
    fun btrfsInstallLines() = listOf(
        "if ! command -v mkfs.btrfs >/dev/null 2>&1; then",
        "  ${Apt.QUIET} install -y -q btrfs-progs",
        "fi",
    )
}
