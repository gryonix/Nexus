package com.skaymer.gryonixnexus.catalog.storage

import com.skaymer.gryonixnexus.catalog.ShellQuoting

/** A USB drive that holds backup copies */
data class BackupDrive(
    /** The filesystem UUID, or the disk path while blank */
    val id: String,
    val name: String,
    val uuid: String?,
    val disk: ServerDisk?,
    val state: State,
) {
    enum class State { BLANK, READY, UNMOUNTED, MISSING }

    val sizeBytes: Long get() = disk?.sizeBytes ?: 0
}

/** Removable, and not the system or an array member */
val ServerDisk.isBackupDriveCandidate: Boolean get() = removable && !isSystem && !raidMember

/** Finds USB drives in the server's disk probe */
object BackupDrives {
    /** Every removable drive plus the chosen ones that are missing */
    fun drives(hardware: ServerHardware?, chosen: Map<String, String>): List<BackupDrive> {
        val present = hardware?.disks.orEmpty().filter { it.isBackupDriveCandidate }.mapNotNull { drive(it, hardware) }
        val seen = present.mapNotNull { it.uuid }.toSet()
        val missing = chosen.keys.sorted().filter { it !in seen }.map { uuid ->
            BackupDrive(uuid, chosen[uuid] ?: uuid, uuid, null, BackupDrive.State.MISSING)
        }
        return present + missing
    }

    private fun drive(disk: ServerDisk, hardware: ServerHardware?): BackupDrive? {
        val nodes = hardware?.blockNodes.orEmpty().filter { it.disk == disk.path }
        val own = nodes.firstOrNull { it.label.startsWith(BackupDriveScripts.LABEL_PREFIX) && it.uuid.isNotEmpty() }
        if (own != null) {
            val name = own.label.removePrefix(BackupDriveScripts.LABEL_PREFIX)
            val mounted = own.mountpoint == BackupDriveScripts.mountPoint(name)
            val state = if (mounted) BackupDrive.State.READY else BackupDrive.State.UNMOUNTED
            return BackupDrive(own.uuid, name, own.uuid, disk, state)
        }
        if (disk.mountpoints.isNotEmpty()) return null
        return BackupDrive(disk.path, disk.model.ifEmpty { disk.name }, null, disk, BackupDrive.State.BLANK)
    }

    /** The first free name of the form usbN */
    fun suggestedName(taken: List<String>): String = (1..99).map { "usb$it" }.firstOrNull { it !in taken } ?: "usb"

    /** Lowercase letters, digits and dashes, at most 11 */
    fun isValidName(name: String): Boolean =
        name.length in 1..11 && (name[0] in 'a'..'z' || name[0] in '0'..'9') &&
            name.all { it in 'a'..'z' || it in '0'..'9' || it == '-' }
}

/** What a drive check found */
data class BackupDriveCheck(
    val smart: Smart = Smart.NONE,
    val filesystem: Filesystem = Filesystem.UNKNOWN,
    val writeBytesPerSecond: Long = 0,
    val readBytesPerSecond: Long = 0,
) {
    enum class Smart { PASSED, FAILED, NONE }
    enum class Filesystem { CLEAN, ERRORS, BUSY, UNKNOWN }

    companion object {
        fun parse(output: String): BackupDriveCheck = output.lines().fold(BackupDriveCheck()) { check, line ->
            val parts = line.split(" ")
            when {
                parts.size < 2 -> check
                parts[0] == "GRYONIXNEXUS_DRIVE_SMART" ->
                    check.copy(smart = Smart.entries.firstOrNull { it.name.lowercase() == parts[1] } ?: Smart.NONE)
                parts[0] == "GRYONIXNEXUS_DRIVE_FSCK" -> check.copy(
                    filesystem = Filesystem.entries.firstOrNull { it.name.lowercase() == parts[1] } ?: Filesystem.UNKNOWN,
                )
                parts[0] == "GRYONIXNEXUS_DRIVE_SPEED" && parts.size >= 3 -> check.copy(
                    writeBytesPerSecond = parts[1].toLongOrNull() ?: 0,
                    readBytesPerSecond = parts[2].toLongOrNull() ?: 0,
                )
                else -> check
            }
        }
    }
}

/** Root scripts for USB drives, identical to the agent's */
object BackupDriveScripts {
    const val ROOT = "/srv/gryonix-backup"
    const val LABEL_PREFIX = "gnxb-"
    const val FORMAT_DONE = "GRYONIXNEXUS_DRIVE_FORMAT_DONE"
    const val ATTACH_DONE = "GRYONIXNEXUS_DRIVE_ATTACH_DONE"
    const val CHECK_DONE = "GRYONIXNEXUS_DRIVE_CHECK_DONE"
    const val EJECT_DONE = "GRYONIXNEXUS_DRIVE_EJECT_DONE"
    const val FORGET_DONE = "GRYONIXNEXUS_DRIVE_FORGET_DONE"
    const val UUID_MARKER = "GRYONIXNEXUS_DRIVE_UUID"

    fun mountPoint(name: String): String = "$ROOT/$name"

    /** Whether a backup path lies on a USB drive */
    fun isDriveCopy(path: String): Boolean = path.startsWith("$ROOT/") && ".." !in path

    /** The new filesystem's UUID, from a format's output */
    fun formattedUuid(output: String): String? =
        output.lines().lastOrNull { it.startsWith("$UUID_MARKER ") }?.removePrefix("$UUID_MARKER ")?.trim()

    private fun join(lines: List<String>): String = lines.joinToString("\n") + "\n"

    private val removableGuard = listOf(
        "removable=\"\$(lsblk -dno TRAN,RM,HOTPLUG \"\$DISK\" | tr -s ' ')\"",
        "case \" \$removable \" in",
        "  *\" usb \"*|*\" 1 \"*) ;;",
        "  *) echo \"\$DISK is not a removable drive. Nothing was erased.\"; exit 3 ;;",
        "esac",
    )

    private val attachLines = listOf(
        "install -d -m 700 \"\$MOUNT\"",
        "awk -v m=\"\$MOUNT\" -v u=\"UUID=\$uuid\" '\$1 != u && \$2 != m' /etc/fstab > /etc/fstab.gryonixnexus",
        "cat /etc/fstab.gryonixnexus > /etc/fstab",
        "rm -f /etc/fstab.gryonixnexus",
        "device=\"\$(systemd-escape -p --suffix=device \"/dev/disk/by-uuid/\$uuid\")\"",
        "echo \"UUID=\$uuid \$MOUNT ext4 nofail,noatime,x-systemd.device-timeout=5s,x-systemd.wanted-by=\$device 0 2\" >> /etc/fstab",
        "systemctl daemon-reload >/dev/null 2>&1 || true",
        "mountpoint -q \"\$MOUNT\" || mount \"\$MOUNT\"",
        "chmod 700 \"\$MOUNT\"",
        "printf '%s\\n' \"\$uuid\" > \"\$MOUNT/.gryonix-backup-drive\"",
        "echo \"GRYONIXNEXUS_DRIVE_UUID \$uuid\"",
    )

    private fun header(uuid: String, name: String, strict: Boolean): List<String> = listOf(
        "#!/bin/bash",
        if (strict) "set -euo pipefail" else "set -uo pipefail",
        "DRIVE=${ShellQuoting.singleQuoted(uuid)}",
        "MOUNT=${ShellQuoting.singleQuoted(mountPoint(name))}",
    )

    private val pluggedIn = listOf(
        "part=\"/dev/disk/by-uuid/\$DRIVE\"",
        "if [ ! -b \"\$part\" ]; then",
        "  echo \"The drive is not plugged in.\"",
        "  exit 3",
        "fi",
    )

    private val unmountOrRefuse = listOf(
        "if mountpoint -q \"\$MOUNT\" && ! umount \"\$MOUNT\"; then",
        "  echo \"The drive is busy. A backup may be writing to it.\"",
        "  exit 3",
        "fi",
    )

    fun format(disk: String, name: String, identity: DiskIdentity?): String = join(
        listOf(
            "#!/bin/bash",
            "set -euo pipefail",
            "DISK=${ShellQuoting.singleQuoted(disk)}",
            "LABEL=${ShellQuoting.singleQuoted(LABEL_PREFIX + name)}",
            "MOUNT=${ShellQuoting.singleQuoted(mountPoint(name))}",
        ) + ArrayScript.diskGuard(listOfNotNull(identity)) + removableGuard + listOf(
            "for held in \$(lsblk -rno MOUNTPOINT \"\$DISK\" | grep '^/srv/gryonix-backup/' || true); do",
            "  umount \"\$held\"",
            "done",
            "gnx_free \"\$DISK\"",
            "for old in \$(lsblk -rnpo NAME,TYPE \"\$DISK\" | awk '\$2 == \"part\" {print \$1}'); do",
            "  wipefs -a -q \"\$old\" || true",
            "done",
            "wipefs -a -q \"\$DISK\"",
            "printf 'label: gpt\\n,,L\\n' | sfdisk -q \"\$DISK\"",
            "udevadm settle",
            "part=\"\$(lsblk -rnpo NAME,TYPE \"\$DISK\" | awk '\$2 == \"part\" {print \$1; exit}')\"",
            "mkfs.ext4 -q -F -L \"\$LABEL\" \"\$part\"",
            "udevadm settle",
            "uuid=\"\$(blkid -s UUID -o value \"\$part\")\"",
        ) + attachLines + listOf("echo $FORMAT_DONE"),
    )

    fun attach(uuid: String, name: String): String = join(
        header(uuid, name, strict = true) + pluggedIn + listOf(
            "if [ \"\$(blkid -s TYPE -o value \"\$part\")\" != ext4 ]; then",
            "  echo \"The drive is not prepared for backups. Format it first.\"",
            "  exit 3",
            "fi",
            "uuid=\"\$DRIVE\"",
        ) + attachLines + listOf("echo $ATTACH_DONE"),
    )

    private val smartAndFsck = listOf(
        "disk=\"/dev/\$(lsblk -no PKNAME \"\$part\" | head -n 1)\"",
        "case \"\$(smartctl -d sat -H \"\$disk\" 2>/dev/null || true)\" in",
        "  *PASSED*) echo \"GRYONIXNEXUS_DRIVE_SMART passed\" ;;",
        "  *FAILED*) echo \"GRYONIXNEXUS_DRIVE_SMART failed\" ;;",
        "  *) echo \"GRYONIXNEXUS_DRIVE_SMART none\" ;;",
        "esac",
        "remount=0",
        "if mountpoint -q \"\$MOUNT\"; then",
        "  sync",
        "  if umount \"\$MOUNT\" 2>/dev/null; then remount=1; fi",
        "fi",
        "if mountpoint -q \"\$MOUNT\"; then",
        "  echo \"GRYONIXNEXUS_DRIVE_FSCK busy\"",
        "elif e2fsck -fn \"\$part\" >/dev/null 2>&1; then",
        "  echo \"GRYONIXNEXUS_DRIVE_FSCK clean\"",
        "else",
        "  echo \"GRYONIXNEXUS_DRIVE_FSCK errors\"",
        "fi",
        "if [ \"\$remount\" -eq 1 ]; then mount \"\$MOUNT\" || true; fi",
    )

    private val speedLines = listOf(
        "if mountpoint -q \"\$MOUNT\"; then",
        "  probe=\"\$MOUNT/.gnx-speed\"",
        "  start=\"\$(date +%s%N)\"",
        "  if dd if=/dev/zero of=\"\$probe\" bs=1M count=64 oflag=direct status=none 2>/dev/null; then",
        "    mid=\"\$(date +%s%N)\"",
        "    dd if=\"\$probe\" of=/dev/null bs=1M iflag=direct status=none 2>/dev/null || true",
        "    end=\"\$(date +%s%N)\"",
        "    echo \"GRYONIXNEXUS_DRIVE_SPEED \$((67108864 * 1000000000 / (mid - start + 1))) \$((67108864 * 1000000000 / (end - mid + 1)))\"",
        "  else",
        "    echo \"GRYONIXNEXUS_DRIVE_SPEED 0 0\"",
        "  fi",
        "  rm -f \"\$probe\"",
        "fi",
    )

    fun check(uuid: String, name: String): String =
        join(header(uuid, name, strict = false) + pluggedIn + smartAndFsck + speedLines + listOf("echo $CHECK_DONE"))

    fun eject(uuid: String, name: String): String = join(
        header(uuid, name, strict = true) + listOf("sync") + unmountOrRefuse + listOf(
            "part=\"/dev/disk/by-uuid/\$DRIVE\"",
            "if [ -b \"\$part\" ] && command -v udisksctl >/dev/null 2>&1; then",
            "  udisksctl power-off -b \"/dev/\$(lsblk -no PKNAME \"\$part\" | head -n 1)\" >/dev/null 2>&1 || true",
            "fi",
            "echo $EJECT_DONE",
        ),
    )

    fun forget(uuid: String, name: String): String = join(
        header(uuid, name, strict = true) + unmountOrRefuse + listOf(
            "awk -v m=\"\$MOUNT\" -v u=\"UUID=\$DRIVE\" '\$1 != u && \$2 != m' /etc/fstab > /etc/fstab.gryonixnexus",
            "cat /etc/fstab.gryonixnexus > /etc/fstab",
            "rm -f /etc/fstab.gryonixnexus",
            "systemctl daemon-reload >/dev/null 2>&1 || true",
            "rmdir \"\$MOUNT\" 2>/dev/null || true",
            "echo $FORGET_DONE",
        ),
    )
}
