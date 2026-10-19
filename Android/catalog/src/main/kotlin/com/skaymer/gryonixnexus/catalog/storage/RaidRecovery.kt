package com.skaymer.gryonixnexus.catalog.storage

import com.skaymer.gryonixnexus.catalog.Apt

/** Brings an existing array back without touching its data */
data class RaidImportPlan(val array: StorageArray) {
    /** null only assembles; the cache step mounts a mirror */
    val mountPoint: String? = when {
        array.isCacheMirror || array.kind != StorageArray.Kind.MD -> null
        array.isStorage -> RaidPlan.MOUNT_POINT
        else -> "/srv/raid-" + safeName(array.name)
    }

    fun script(): String {
        if (array.kind == StorageArray.Kind.ZFS) return zfsScript()
        val lines = mutableListOf("#!/bin/bash", "set -euo pipefail", "ARRAY=${FastStoragePlan.quoted(array.address)}")
        mountPoint?.let { lines += "MOUNT=${FastStoragePlan.quoted(it)}" }
        lines += RaidPlan.installLines() + assembleLines()
        if (mountPoint != null) lines += filesystemCheck() + RaidPlan.mountLines()
        lines += "echo $DONE_MARKER"
        return lines.joinToString("\n") + "\n"
    }

    private fun zfsScript(): String = (
        listOf(
            "#!/bin/bash",
            "set -euo pipefail",
            "POOL=${FastStoragePlan.quoted(array.name)}",
            "ID=${FastStoragePlan.quoted(array.uuid ?: array.name)}",
        ) + ZfsTools.installLines() + listOf(
            "if ! zpool list -H \"\$POOL\" >/dev/null 2>&1; then",
            "  zpool import -f \"\$ID\"",
            "fi",
            "zpool set cachefile=/etc/zfs/zpool.cache \"\$POOL\" || true",
            "echo $DONE_MARKER",
        )
    ).joinToString("\n") + "\n"

    private fun assembleLines(): List<String> {
        val uuid = FastStoragePlan.quoted(array.uuid.orEmpty())
        return listOf(
            "if ! mdadm --detail \"\$ARRAY\" >/dev/null 2>&1; then",
            "  mdadm --assemble \"\$ARRAY\" --uuid=$uuid --run",
            "fi",
            "install -d /etc/mdadm",
            "grep -q $uuid /etc/mdadm/mdadm.conf 2>/dev/null || mdadm --detail --brief \"\$ARRAY\" >> /etc/mdadm/mdadm.conf",
            "update-initramfs -u >/dev/null 2>&1 || true",
        )
    }

    private fun filesystemCheck() = listOf(
        "if [ -z \"\$(blkid -s TYPE -o value \"\$ARRAY\" || true)\" ]; then",
        "  echo \"The array holds no filesystem; nothing was formatted.\"",
        "  exit 3",
        "fi",
    )

    companion object {
        const val DONE_MARKER = "GRYONIXNEXUS_RAID_IMPORT_DONE"

        /** Letters, digits and dashes only */
        fun safeName(name: String): String = name.map { if (it.isLetterOrDigit() || it == '-') it else '-' }.joinToString("")
    }
}

/** Swaps a failed array member for a new disk */
data class RaidRepairPlan(val array: StorageArray, val replacement: ServerDisk) {
    fun script(): String = if (array.kind == StorageArray.Kind.ZFS) zfsScript() else mdScript()

    private fun zfsScript(): String = (listOf(
        "#!/bin/bash",
        "set -euo pipefail",
        "POOL=${FastStoragePlan.quoted(array.name)}",
        "OLD=${FastStoragePlan.quoted(array.failed.firstOrNull().orEmpty())}",
        "NEW=${FastStoragePlan.quoted(replacement.path)}",
    ) + ArrayScript.diskGuard(listOf(replacement.identity)) + listOf(
        "if ! zpool status -LP \"\$POOL\" | grep -q \"\$NEW\"; then",
        "  gnx_free \"\$NEW\"",
        "  wipefs -a -q \"\$NEW\"",
        "  zpool replace -f \"\$POOL\" \"\$OLD\" \"\$NEW\"",
        "fi",
        "echo $DONE_MARKER",
    )).joinToString("\n") + "\n"

    private fun mdScript(): String = (listOf(
        "#!/bin/bash",
        "set -euo pipefail",
        "ARRAY=${FastStoragePlan.quoted(array.address)}",
        "NEW=${FastStoragePlan.quoted(replacement.path)}",
    ) + ArrayScript.diskGuard(listOf(replacement.identity)) + listOf(
        "mdadm \"\$ARRAY\" --remove failed >/dev/null 2>&1 || true",
        "mdadm \"\$ARRAY\" --remove detached >/dev/null 2>&1 || true",
        "if ! mdadm --detail \"\$ARRAY\" | grep -q \"\$NEW\"; then",
        "  gnx_free \"\$NEW\"",
        "  wipefs -a -q \"\$NEW\"",
        "  mdadm \"\$ARRAY\" --add \"\$NEW\"",
        "fi",
        "echo $DONE_MARKER",
    )).joinToString("\n") + "\n"

    companion object {
        const val DONE_MARKER = "GRYONIXNEXUS_RAID_REPAIR_DONE"

        /** Disks that may take the failed one's place */
        fun candidates(hardware: ServerHardware, array: StorageArray): List<ServerDisk> =
            RaidPlan.candidates(hardware).filter { it.path !in array.members }
    }
}

/** ZFS tools, installed only when a pool is brought back */
internal object ZfsTools {
    fun installLines() = listOf(
        "if ! command -v zpool >/dev/null 2>&1; then",
        "  export DEBIAN_FRONTEND=noninteractive",
        "  if ! { ${Apt.DROP_RETIRED_SOURCES}; ${Apt.QUIET} update -qq && ${Apt.QUIET} install -y -qq zfsutils-linux; } >/dev/null 2>&1; then",
        "    echo \"ZFS tools could not be installed here. On Debian they come from the contrib section.\"",
        "    exit 3",
        "  fi",
        "fi",
    )
}
