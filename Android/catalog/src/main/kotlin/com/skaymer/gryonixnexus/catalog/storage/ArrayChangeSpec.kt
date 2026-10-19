package com.skaymer.gryonixnexus.catalog.storage

/** An array change as flat fields, and its script */
data class ArrayChangeSpec(
    val action: ArrayChange.Action,
    val kind: StorageArray.Kind,
    /** md device, ZFS pool name, or btrfs mount point */
    val address: String,
    /** Array name for the job log */
    val name: String,
    /** Current level as the server reports it */
    val level: String,
    /** The member acted on */
    val member: String = "",
    /** New disks, erased first */
    val disks: List<String> = emptyList(),
    /** md member count once done */
    val devices: Int = 0,
    /** Level number after a level change */
    val newLevel: Int = 0,
    /** Members wiped when the array is deleted */
    val members: List<String> = emptyList(),
    /** Whole disks whose SMART verdict must not be failing */
    val checkDisks: List<String> = emptyList(),
    /** The new disks as the app saw them */
    val identities: List<DiskIdentity> = emptyList(),
) {
    fun script(): String {
        val steps = when (kind) {
            StorageArray.Kind.ZFS -> ZfsChange(this).steps()
            StorageArray.Kind.BTRFS -> BtrfsChange(this).steps()
            else -> MdChange(this).steps()
        }
        val busy = if (steps.later.isEmpty()) emptyList() else DiskJob.BUSY_GUARD
        val guard = if (disks.isEmpty()) emptyList() else ArrayScript.diskGuard(identities)
        val lines = mutableListOf("#!/bin/bash", "set -euo pipefail") + variables + guard + busy + healthLines + steps.now
        val job = if (steps.later.isEmpty()) emptyList()
        else DiskJob.launchLines(action.raw, name, variables, steps.later)
        return (lines + job + "echo ${ArrayChange.DONE_MARKER}").joinToString("\n") + "\n"
    }

    val variables: List<String>
        get() {
            val head = when (kind) {
                StorageArray.Kind.ZFS -> "POOL="
                StorageArray.Kind.BTRFS -> "MOUNT="
                else -> "ARRAY="
            }
            val lines = mutableListOf(head + FastStoragePlan.quoted(address))
            if (member.isNotEmpty()) lines += "OLD=" + FastStoragePlan.quoted(member)
            disks.forEachIndexed { index, disk ->
                lines += "NEW${if (index == 0) "" else (index + 1).toString()}=" + FastStoragePlan.quoted(disk)
            }
            return lines
        }

    /** Refuses when a disk that stays is failing */
    private val healthLines: List<String>
        get() {
            if (checkDisks.isEmpty()) return emptyList()
            val quoted = checkDisks.joinToString(" ") { FastStoragePlan.quoted(it) }
            return listOf(
                "CHECK=($quoted)",
                "if command -v smartctl >/dev/null 2>&1; then",
                "  for disk in \"\${CHECK[@]}\"; do",
                "    if smartctl -H \"\$disk\" 2>/dev/null | grep -q FAILED; then",
                "      echo \"\$disk reports that it is failing. Replace that disk first.\"",
                "      exit 3",
                "    fi",
                "  done",
                "fi",
            )
        }
}

/** Lines run now, and lines left to the background job */
internal data class ArraySteps(val now: List<String>, val later: List<String> = emptyList())

/** Pieces every kind of array shares */
internal object ArrayScript {
    /** Refuses a disk that is missing, changed or in use */
    fun diskGuard(identities: List<DiskIdentity> = emptyList()): List<String> {
        val known = identities.filter { it.sizeBytes > 0 }
        return expectedTable(known) + listOf(
            "gnx_free() {",
            "  if [ ! -b \"\$1\" ]; then",
            "    echo \"\$1 is not a disk on this server.\"",
            "    exit 3",
            "  fi",
        ) + (if (known.isEmpty()) emptyList() else IDENTITY_CHECK) + listOf(
            "  if [ -n \"\$(lsblk -rno MOUNTPOINT \"\$1\" | tr -d '[:space:]')\" ] || lsblk -rno TYPE \"\$1\" | grep -E '^(raid|lvm|crypt)' >/dev/null; then",
            "    echo \"\$1 is in use. Nothing was erased.\"",
            "    exit 3",
            "  fi",
            "}",
        )
    }

    private fun expectedTable(identities: List<DiskIdentity>): List<String> {
        if (identities.isEmpty()) return emptyList()
        val rows = identities.map {
            "    ${FastStoragePlan.quoted(it.path)}) echo ${FastStoragePlan.quoted("${it.sizeBytes}|${it.serial}")} ;;"
        }
        return listOf("gnx_expect() {", "  case \"\$1\" in") + rows + listOf("  esac", "}")
    }

    private val IDENTITY_CHECK = listOf(
        "  local want size serial",
        "  want=\"\$(gnx_expect \"\$1\")\"",
        "  if [ -n \"\$want\" ]; then",
        "    size=\"\$(lsblk -dnbo SIZE \"\$1\" | tr -d '[:space:]')\"",
        "    serial=\"\$(lsblk -dno SERIAL \"\$1\" | tr -d '[:space:]')\"",
        "    if [ \"\${want%%|*}\" != \"\$size\" ] || { [ -n \"\${want#*|}\" ] && [ -n \"\$serial\" ] && [ \"\${want#*|}\" != \"\$serial\" ]; }; then",
        "      echo \"\$1 is not the disk the app listed. Nothing was erased.\"",
        "      exit 3",
        "    fi",
        "  fi",
    )

    /** Checks every disk before the first one is wiped */
    fun checkAll(members: String) =
        listOf("  for disk in $members; do", "    gnx_free \"\$disk\"", "  done")

    /** Refuses while services keep data under `$MOUNT` */
    val SERVICES_GUARD = listOf(
        "if [ -n \"\$MOUNT\" ] && command -v docker >/dev/null 2>&1; then",
        "  for c in \$(docker ps -aq); do",
        "    if docker inspect -f '{{range .Mounts}}{{println .Source}}{{end}}' \"\$c\" | grep -qF -- \"\$MOUNT\"; then",
        "      echo \"Services keep their data here. Move or remove them first.\"",
        "      exit 3",
        "    fi",
        "  done",
        "fi",
    )

    /** Drops the `$MOUNT` line from /etc/fstab */
    val FORGET_MOUNT = listOf(
        "awk -v m=\"\$MOUNT\" '\$2 != m' /etc/fstab > /etc/fstab.gryonixnexus",
        "cat /etc/fstab.gryonixnexus > /etc/fstab",
        "rm -f /etc/fstab.gryonixnexus",
    )

    /** Stops unless every disk is in the array */
    fun requireMembers(members: List<String>, listing: String, noun: String) = listOf(
        "REAL=\"\$($listing)\"",
        "for disk in ${members.joinToString(" ") { FastStoragePlan.quoted(it) }}; do",
        "  if ! printf '%s\\n' \"\$REAL\" | grep -qxF -- \"\$disk\"; then",
        "    echo \"\$disk is not in this $noun.\"",
        "    exit 3",
        "  fi",
        "done",
    )

    const val ZFS_MEMBERS = "zpool status -LP \"\$POOL\" | awk '\$1 ~ /^\\/dev\\// {print \$1}'"
    const val BTRFS_MEMBERS = "btrfs filesystem show \"\$MOUNT\" | awk '\$NF ~ /^\\/dev\\// {print \$NF}'"

    fun wipe(members: List<String>, command: String) = listOf(
        "WIPE=(${members.joinToString(" ") { FastStoragePlan.quoted(it) }})",
        "for disk in \"\${WIPE[@]}\"; do",
        "  $command",
        "done",
    )
}
