package com.skaymer.gryonixnexus.catalog.storage

import com.skaymer.gryonixnexus.catalog.Apt
/** Formats one free disk and mounts it under /srv */
data class DiskFormatPlan(
    val disk: String,
    val filesystem: Filesystem,
    val label: String,
    val mountPoint: String,
    val identity: DiskIdentity? = null,
) {
    enum class Filesystem(val raw: String) { EXT4("ext4"), XFS("xfs"), BTRFS("btrfs") }

    private val makeFilesystem: String
        get() = when (filesystem) {
            Filesystem.EXT4 -> "mkfs.ext4 -q -L \"\$LABEL\" \"\$part\""
            Filesystem.XFS -> "mkfs.xfs -f -q -L \"\$LABEL\" \"\$part\""
            Filesystem.BTRFS -> "mkfs.btrfs -f -q -L \"\$LABEL\" \"\$part\""
        }

    private val tools: List<String>
        get() = when (filesystem) {
            Filesystem.EXT4 -> emptyList()
            Filesystem.XFS -> install("mkfs.xfs", "xfsprogs")
            Filesystem.BTRFS -> RaidPools.btrfsInstallLines()
        }

    fun script(): String {
        val pass = if (filesystem == Filesystem.EXT4) "2" else "0"
        return (
            listOf(
                "#!/bin/bash",
                "set -euo pipefail",
                "DISK=${FastStoragePlan.quoted(disk)}",
                "LABEL=${FastStoragePlan.quoted(label)}",
                "MOUNT=${FastStoragePlan.quoted(mountPoint)}",
            ) + ArrayScript.diskGuard(listOfNotNull(identity)) + tools + listOf(
                "if ! lsblk -rno LABEL \"\$DISK\" | grep -qx -- \"\$LABEL\"; then",
                "  gnx_free \"\$DISK\"",
                "  for old in \$(lsblk -rnpo NAME,TYPE \"\$DISK\" | awk '\$2 == \"part\" {print \$1}'); do",
                "    zpool labelclear -f \"\$old\" >/dev/null 2>&1 || true",
                "    wipefs -a -q \"\$old\" || true",
                "  done",
                "  zpool labelclear -f \"\$DISK\" >/dev/null 2>&1 || true",
                "  wipefs -a -q \"\$DISK\"",
                "  size=\"\$(blockdev --getsz \"\$DISK\")\"",
                "  dd if=/dev/zero of=\"\$DISK\" bs=512 seek=\"\$((size - 8192))\" count=8192 conv=fsync status=none",
                "  printf 'label: gpt\\n,,L\\n' | sfdisk -q \"\$DISK\"",
                "  udevadm settle",
                "  part=\"\$(lsblk -rnpo NAME,TYPE \"\$DISK\" | awk '\$2 == \"part\" {print \$1; exit}')\"",
                "  $makeFilesystem",
                "  udevadm settle",
                "fi",
                "part=\"\$(lsblk -rnpo NAME,LABEL \"\$DISK\" | awk -v l=\"\$LABEL\" '\$2 == l {print \$1; exit}')\"",
                "install -d \"\$MOUNT\"",
                "uuid=\"\$(blkid -s UUID -o value \"\$part\")\"",
                "grep -q \"UUID=\$uuid \$MOUNT \" /etc/fstab || echo \"UUID=\$uuid \$MOUNT ${filesystem.raw} defaults,nofail 0 $pass\" >> /etc/fstab",
                "mountpoint -q \"\$MOUNT\" || mount \"\$MOUNT\"",
                "echo $DONE_MARKER",
            )
            ).joinToString("\n") + "\n"
    }

    companion object {
        const val DONE_MARKER = "GRYONIXNEXUS_DISK_FORMAT_DONE"

        /** Label and first free mount for `disk` */
        fun plan(disk: ServerDisk, filesystem: Filesystem, hardware: ServerHardware): DiskFormatPlan {
            val base = "/srv/disk-" + RaidImportPlan.safeName(disk.name)
            val mounts = (hardware.disks.flatMap { it.mountpoints } + hardware.volumes.mapNotNull { it.mountpoint }).toSet()
            val mount = (listOf(base) + (2..99).map { "$base-$it" }).firstOrNull { it !in mounts } ?: base
            return DiskFormatPlan(
                disk.path, filesystem, ("gnx-" + RaidImportPlan.safeName(disk.name)).take(12), mount, disk.identity,
            )
        }

        /** Disks that are not system, array members or mounted */
        fun candidates(hardware: ServerHardware): List<ServerDisk> = RaidPlan.candidates(hardware)

        internal fun install(command: String, pkg: String) = listOf(
            "if ! command -v $command >/dev/null 2>&1; then",
            "  ${Apt.QUIET} install -y -q $pkg",
            "fi",
        )
    }
}

/** Unmounts a data disk and drops its fstab line */
data class DiskReleasePlan(val mountPoint: String) {
    fun script(): String = (
        listOf("#!/bin/bash", "set -euo pipefail", "MOUNT=${FastStoragePlan.quoted(mountPoint)}") +
            ArrayScript.SERVICES_GUARD + listOf(
                "if mountpoint -q \"\$MOUNT\"; then",
                "  umount \"\$MOUNT\"",
                "fi",
            ) + ArrayScript.FORGET_MOUNT + "echo $DONE_MARKER"
        ).joinToString("\n") + "\n"

    companion object {
        const val DONE_MARKER = "GRYONIXNEXUS_DISK_RELEASE_DONE"

        /** Mounts under these may be released */
        val PREFIXES = listOf("/srv/", "/mnt/", "/media/")

        /** The disk's mount, when this app may release it */
        fun mount(disk: ServerDisk): String? = disk.dataMount?.takeIf { mount -> PREFIXES.any { mount.startsWith(it) } }
    }
}

/** Reads a disk briefly so its light blinks */
object DiskBlink {
    const val DONE_MARKER = "GRYONIXNEXUS_DISK_BLINK_DONE"

    fun script(disk: String): String = listOf(
        "#!/bin/bash",
        "set -uo pipefail",
        "DISK=${FastStoragePlan.quoted(disk)}",
        "if command -v ledctl >/dev/null 2>&1; then",
        "  ledctl locate=\"\$DISK\" >/dev/null 2>&1 || true",
        "fi",
        "timeout 30 dd if=\"\$DISK\" of=/dev/null bs=1M iflag=direct status=none || true",
        "if command -v ledctl >/dev/null 2>&1; then",
        "  ledctl locate_off=\"\$DISK\" >/dev/null 2>&1 || true",
        "fi",
        "echo $DONE_MARKER",
    ).joinToString("\n") + "\n"
}
