package com.skaymer.gryonixnexus.catalog.storage

import com.skaymer.gryonixnexus.catalog.ComposeFile

/** Puts databases, caches and Docker's data on a fast disk */
data class FastStoragePlan(
    val target: Target,
    /** Service directories that move onto the fast disk */
    val hotPaths: List<String>,
) {
    sealed interface Target {
        /** A whole device, formatted only if it has no filesystem */
        data class Device(val path: String) : Target
        /** A folder on a filesystem that is already mounted */
        data class Folder(val on: String) : Target
    }

    constructor(disk: ServerDisk, hotPaths: List<String>) : this(
        if (disk.isBlank || disk.isEarlierCache) Target.Device(disk.path)
        else Target.Folder(disk.dataMount ?: MOUNT_POINT),
        hotPaths,
    )

    /** Where fast data lives on the server */
    val root: String
        get() = when (val t = target) {
            is Target.Device -> MOUNT_POINT
            is Target.Folder -> t.on + "/gryonixnexus-fast"
        }

    fun script(): String {
        val lines = mutableListOf("#!/bin/bash", "set -euo pipefail", "FAST=${quoted(root)}")
        lines += when (val t = target) {
            is Target.Device -> formatLines(t.path)
            is Target.Folder -> listOf("install -d \"\$FAST\"")
        }
        lines += dockerLines() + bindFunction()
        lines += hotPaths.map { "bind_fast ${quoted(it)}" }
        lines += "echo $DONE_MARKER"
        return lines.joinToString("\n") + "\n"
    }

    private fun dockerLines() = listOf(
        "if ! command -v docker >/dev/null 2>&1 && [ ! -s /etc/docker/daemon.json ]; then",
        "  install -d /etc/docker \"\$FAST/docker\"",
        "  printf '{\\n  \"data-root\": \"%s/docker\"\\n}\\n' \"\$FAST\" > /etc/docker/daemon.json",
        "fi",
    )

    private fun bindFunction() = listOf(
        "bind_fast() {",
        "  local target=\"\$1\" source=\"\$FAST/binds\$1\"",
        "  install -d \"\$source\" \"\$target\"",
        "  mountpoint -q \"\$target\" && return 0",
        "  if [ -n \"\$(ls -A \"\$target\")\" ]; then",
        "    echo \"\$target already holds data, left in place\"",
        "    return 0",
        "  fi",
        "  grep -qF \" \$target none bind\" /etc/fstab || echo \"\$source \$target none bind,nofail,x-systemd.requires-mounts-for=\$FAST 0 0\" >> /etc/fstab",
        "  mount \"\$target\"",
        "}",
    )

    companion object {
        const val MOUNT_POINT = "/srv/gryonixnexus-fast"
        const val LABEL = "gnx-fast"
        const val DONE_MARKER = "GRYONIXNEXUS_STORAGE_DONE"

        /** Last path components that hold databases or caches */
        private val HOT_NAMES = setOf("db", "postgres", "redis", "cache", "ml-cache", "webmail-db", "storage")

        /** Fast disks usable without losing anything on them */
        fun candidates(hardware: ServerHardware): List<ServerDisk> = hardware.disks.filter {
            it.isFast && !it.isSystem && !it.raidMember &&
                (it.isBlank || it.dataMount != null || it.isEarlierCache)
        }

        /** Hot bind-mounted directories named in the compose files */
        fun hotPaths(composeFiles: List<ComposeFile>): List<String> =
            hotPathsInText(composeFiles.joinToString("\n") { it.composeContents })

        /** Hot host directories in compose volume lines */
        fun hotPathsInText(text: String): List<String> {
            val result = LinkedHashSet<String>()
            for (line in text.split("\n")) {
                val trimmed = line.trim()
                if (!trimmed.startsWith("- /")) continue
                val volume = trimmed.removePrefix("- ")
                val colon = volume.indexOf(':').takeIf { it >= 0 } ?: continue
                if (!volume.startsWith("/", colon + 1)) continue
                val source = volume.substring(0, colon)
                if (source.substringAfterLast('/') in HOT_NAMES) result += source
            }
            return result.toList()
        }

        internal fun formatLines(path: String) = listOf(
            "DISK=${quoted(path)}",
            "if ! mountpoint -q \"\$FAST\"; then",
            "  if [ -z \"\$(lsblk -nro FSTYPE \"\$DISK\" | tr -d '[:space:]')\" ] && [ \"\$(lsblk -nro NAME \"\$DISK\" | wc -l)\" -eq 1 ]; then",
            "    mkfs.ext4 -q -L gnx-fast \"\$DISK\"",
            "  fi",
            "  install -d \"\$FAST\"",
            "  uuid=\"\$(blkid -s UUID -o value \"\$DISK\")\"",
            "  grep -q \"UUID=\$uuid \$FAST \" /etc/fstab || echo \"UUID=\$uuid \$FAST ext4 defaults,noatime,nofail 0 2\" >> /etc/fstab",
            "  mount \"\$FAST\"",
            "fi",
        )

        internal fun bindLine(source: String, target: String) =
            "grep -qF \" $target none bind\" /etc/fstab || echo \"$source $target none bind,nofail,x-systemd.requires-mounts-for=\$FAST 0 0\" >> /etc/fstab"

        internal fun quoted(value: String) = "'" + value.replace("'", "'\\''") + "'"
    }
}
