package com.skaymer.gryonixnexus.catalog.storage

/** Array changes for ZFS pools */
internal class ZfsChange(private val spec: ArrayChangeSpec) {
    fun steps(): ArraySteps = when (spec.action) {
        ArrayChange.Action.ADD_SPARE ->
            ArraySteps(unlessPresent(listOf("gnx_free \"\$NEW\"", "wipefs -a -q \"\$NEW\"", "zpool add -f \"\$POOL\" spare \"\$NEW\"")))
        ArrayChange.Action.GROW -> ArraySteps(unlessPresent(listOf("gnx_free \"\$NEW\"", "wipefs -a -q \"\$NEW\"") + grow))
        ArrayChange.Action.REPLACE ->
            ArraySteps(unlessPresent(listOf("gnx_free \"\$NEW\"", "wipefs -a -q \"\$NEW\"", "zpool replace -f \"\$POOL\" \"\$OLD\" \"\$NEW\"")))
        ArrayChange.Action.DETACH -> ArraySteps(healthy + "zpool offline \"\$POOL\" \"\$OLD\"")
        ArrayChange.Action.REMOVE ->
            if (spec.level == "mirror") ArraySteps(healthy + "zpool detach \"\$POOL\" \"\$OLD\"" + CLEAR_OLD)
            else ArraySteps(healthy + "zpool remove \"\$POOL\" \"\$OLD\"", listOf("zpool wait -t remove \"\$POOL\"") + CLEAR_OLD)
        ArrayChange.Action.CHECK -> ArraySteps(listOf("zpool scrub \"\$POOL\""))
        ArrayChange.Action.CHANGE_LEVEL -> ArraySteps(listOf("echo \"ZFS cannot change the level of a pool.\"", "exit 3"))
        ArrayChange.Action.DELETE -> ArraySteps(
            listOf("MOUNT=\"\$(zfs get -H -o value mountpoint \"\$POOL\" 2>/dev/null | grep '^/' || true)\"") +
                ArrayScript.SERVICES_GUARD +
                ArrayScript.requireMembers(spec.members, ArrayScript.ZFS_MEMBERS, "pool") +
                "zpool destroy -f \"\$POOL\"" +
                ArrayScript.wipe(spec.members, "zpool labelclear -f \"\$disk\" >/dev/null 2>&1 || true; wipefs -a -q \"\$disk\" || true"),
        )
    }

    private fun unlessPresent(body: List<String>) =
        listOf("if ! zpool status -LP \"\$POOL\" | grep -qw -- \"\$NEW\"; then") + body.map { "  $it" } + "fi"

    private val healthy = listOf(
        "if ! zpool status -x \"\$POOL\" | grep -q 'is healthy'; then",
        "  echo \"The pool is not healthy right now. Wait until it is, then try again.\"",
        "  exit 3",
        "fi",
    )

    private val grow: List<String>
        get() = when {
            spec.level == "mirror" && spec.disks.size == 2 ->
                listOf("gnx_free \"\$NEW2\"", "wipefs -a -q \"\$NEW2\"", "zpool add -f \"\$POOL\" mirror \"\$NEW\" \"\$NEW2\"")
            spec.level == "mirror" -> listOf("zpool attach -f \"\$POOL\" \"\$OLD\" \"\$NEW\"")
            spec.level == "stripe" -> listOf("zpool add -f \"\$POOL\" \"\$NEW\"")
            else -> listOf(
                "vdev=\"\$(zpool status -P \"\$POOL\" | awk '\$1 ~ /^raidz[123]-[0-9]+\$/ {print \$1; exit}')\"",
                "zpool attach -f \"\$POOL\" \"\$vdev\" \"\$NEW\"",
            )
        }

    private companion object {
        val CLEAR_OLD = listOf("zpool labelclear -f \"\$OLD\" >/dev/null 2>&1 || true")
    }
}

/** Array changes for multi-disk btrfs */
internal class BtrfsChange(private val spec: ArrayChangeSpec) {
    fun steps(): ArraySteps {
        val steps = actionSteps()
        return steps.copy(now = MOUNTED + steps.now)
    }

    private fun actionSteps(): ArraySteps = when (spec.action) {
        ArrayChange.Action.GROW -> ArraySteps(
            listOf(
                "if ! btrfs filesystem show \"\$MOUNT\" | grep -qw -- \"\$NEW\"; then",
                "  gnx_free \"\$NEW\"",
                "  wipefs -a -q \"\$NEW\"",
                "  btrfs device add -f \"\$NEW\" \"\$MOUNT\"",
                "fi",
            ),
            listOf("btrfs balance start --full-balance \"\$MOUNT\""),
        )
        ArrayChange.Action.REPLACE -> ArraySteps(
            PRESENT + "gnx_free \"\$NEW\"" + "wipefs -a -q \"\$NEW\"",
            listOf(
                "btrfs replace start -B -f \"\$OLD\" \"\$NEW\" \"\$MOUNT\"",
                "devid=\"\$(btrfs filesystem show \"\$MOUNT\" | awk -v d=\"\$NEW\" '\$NF == d {print \$2}')\"",
                "btrfs filesystem resize \"\$devid:max\" \"\$MOUNT\"",
            ),
        )
        ArrayChange.Action.REMOVE ->
            ArraySteps(PRESENT, listOf("btrfs device remove \"\$OLD\" \"\$MOUNT\"", "wipefs -a -q \"\$OLD\" || true"))
        ArrayChange.Action.CHANGE_LEVEL -> ArraySteps(emptyList(), listOf("btrfs balance start $profiles \"\$MOUNT\""))
        ArrayChange.Action.CHECK -> ArraySteps(listOf("btrfs scrub start \"\$MOUNT\" >/dev/null"))
        ArrayChange.Action.DELETE -> ArraySteps(
            ArrayScript.SERVICES_GUARD +
                ArrayScript.requireMembers(spec.members, ArrayScript.BTRFS_MEMBERS, "filesystem") +
                "umount \"\$MOUNT\"" + ArrayScript.FORGET_MOUNT +
                ArrayScript.wipe(spec.members, "wipefs -a -q \"\$disk\" || true"),
        )
        ArrayChange.Action.ADD_SPARE, ArrayChange.Action.DETACH ->
            ArraySteps(listOf("echo \"btrfs has no spare or offline disks.\"", "exit 3"))
    }

    /** Data and metadata profiles for the target level */
    private val profiles: String
        get() = when (spec.newLevel) {
            0 -> "-dconvert=raid0 -mconvert=raid1"
            10 -> "-dconvert=raid10 -mconvert=raid10"
            else -> "-dconvert=raid1 -mconvert=raid1"
        }

    private companion object {
        val MOUNTED = listOf(
            "if ! mountpoint -q \"\$MOUNT\"; then",
            "  echo \"\$MOUNT is not mounted.\"",
            "  exit 3",
            "fi",
        )
        val PRESENT = listOf(
            "if ! btrfs filesystem show \"\$MOUNT\" | grep -qw -- \"\$OLD\"; then",
            "  echo \"\$OLD is not in this filesystem.\"",
            "  exit 3",
            "fi",
        )
    }
}
