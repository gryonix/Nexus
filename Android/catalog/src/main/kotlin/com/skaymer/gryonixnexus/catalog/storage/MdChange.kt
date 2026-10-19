package com.skaymer.gryonixnexus.catalog.storage

/** Array changes for Linux software RAID, done with mdadm */
internal class MdChange(private val spec: ArrayChangeSpec) {
    fun steps(): ArraySteps = when (spec.action) {
        ArrayChange.Action.ADD_SPARE -> ArraySteps(add)
        ArrayChange.Action.GROW ->
            ArraySteps(healthy + add + growTo(spec.devices), if (spec.level == "raid1") emptyList() else wait + resize)
        ArrayChange.Action.REPLACE -> ArraySteps(
            present + healthy + add + "mdadm \"\$ARRAY\" --replace \"\$OLD\" --with \"\$NEW\"",
            wait + "mdadm \"\$ARRAY\" --remove \"\$OLD\"" + forget,
        )
        ArrayChange.Action.DETACH -> ArraySteps(healthy + takeOut + forget)
        ArrayChange.Action.REMOVE ->
            if (spec.level == "raid1") ArraySteps(healthy + takeOut + shrinkMirror + forget)
            else ArraySteps(present + healthy + MdShrink.check(spec), MdShrink.job(spec))
        ArrayChange.Action.CHANGE_LEVEL -> changeLevel()
        ArrayChange.Action.CHECK -> ArraySteps(
            listOf(
                "md=\"\$(basename \"\$(readlink -f \"\$ARRAY\")\")\"",
                "echo check > \"/sys/block/\$md/md/sync_action\"",
            ),
        )
        ArrayChange.Action.DELETE -> ArraySteps(delete)
    }

    private val present = listOf(
        "if ! mdadm --detail \"\$ARRAY\" | grep -qw -- \"\$OLD\"; then",
        "  echo \"\$OLD is not in this array.\"",
        "  exit 3",
        "fi",
    )

    private val healthy = listOf(
        "if mdadm --detail \"\$ARRAY\" | grep -Eq 'State : .*(degraded|recovering|resyncing|reshaping)'; then",
        "  echo \"The array is not healthy right now. Wait until it is, then try again.\"",
        "  exit 3",
        "fi",
    )

    private val add = listOf(
        "if ! mdadm --detail \"\$ARRAY\" | grep -qw -- \"\$NEW\"; then",
        "  gnx_free \"\$NEW\"",
        "  wipefs -a -q \"\$NEW\"",
        "  mdadm \"\$ARRAY\" --add \"\$NEW\"",
        "fi",
    )

    private fun growTo(devices: Int) = listOf(
        "if [ \"$RAID_DEVICES\" -lt $devices ]; then",
        "  mdadm --grow \"\$ARRAY\" --raid-devices=$devices",
        "fi",
    )

    private val takeOut = listOf(
        "if mdadm --detail \"\$ARRAY\" | grep -qw -- \"\$OLD\"; then",
        "  mdadm \"\$ARRAY\" --fail \"\$OLD\"",
        "  mdadm \"\$ARRAY\" --remove \"\$OLD\"",
        "fi",
    )

    private val forget = listOf("mdadm --zero-superblock \"\$OLD\" >/dev/null 2>&1 || true")

    private val wait = listOf("mdadm --wait \"\$ARRAY\" || true", "sleep 5")

    /** Grows the filesystem to the array's new size */
    private val resize = listOf(
        "target=\"\$(findmnt -no TARGET \"\$ARRAY\" | head -n 1 || true)\"",
        "case \"\$(blkid -s TYPE -o value \"\$ARRAY\" || true)\" in",
        "  ext2|ext3|ext4) resize2fs \"\$ARRAY\" ;;",
        "  xfs) xfs_growfs \"\$target\" ;;",
        "  btrfs) btrfs filesystem resize max \"\$target\" ;;",
        "esac",
    )

    private val shrinkMirror: List<String>
        get() {
            val force = if (spec.devices == 1) " --force" else ""
            return listOf(
                "if [ \"$RAID_DEVICES\" -gt ${spec.devices} ]; then",
                "  mdadm --grow \"\$ARRAY\" --raid-devices=${spec.devices}$force",
                "fi",
            )
        }

    private fun changeLevel(): ArraySteps {
        if (spec.newLevel == 5) {
            return ArraySteps(
                healthy + listOf(
                    "if mdadm --detail \"\$ARRAY\" | grep -q 'Raid Level : raid1'; then",
                    "  mdadm --grow \"\$ARRAY\" --level=5",
                    "fi",
                ) + add + growTo(spec.devices),
                wait + resize,
            )
        }
        return ArraySteps(
            healthy + add + listOf(
                "if mdadm --detail \"\$ARRAY\" | grep -q 'Raid Level : raid5'; then",
                "  mdadm --grow \"\$ARRAY\" --level=6 --raid-devices=${spec.devices} --backup-file=$RESHAPE_BACKUP",
                "fi",
            ),
            wait + "rm -f $RESHAPE_BACKUP",
        )
    }

    private val delete: List<String>
        get() = listOf("MOUNT=\"\$(findmnt -no TARGET \"\$ARRAY\" | head -n 1 || true)\"") +
            ArrayScript.SERVICES_GUARD + listOf(
                "uuid=\"\$(mdadm --detail \"\$ARRAY\" | awk '/UUID :/ {print \$3}')\"",
                "members=\"\$(mdadm --detail \"\$ARRAY\" | awk '\$NF ~ /^\\/dev\\// && NF > 4 {print \$NF}')\"",
                "if [ -n \"\$MOUNT\" ]; then",
                "  umount \"\$MOUNT\"",
            ) + ArrayScript.FORGET_MOUNT.map { "  $it" } + listOf(
                "fi",
                "mdadm --stop \"\$ARRAY\"",
                "for disk in \$members; do",
                "  mdadm --zero-superblock \"\$disk\" || true",
                "  wipefs -a -q \"\$disk\" || true",
                "done",
                "if [ -f /etc/mdadm/mdadm.conf ]; then",
                "  sed -i \"/UUID=\$uuid/d\" /etc/mdadm/mdadm.conf",
                "fi",
                "update-initramfs -u >/dev/null 2>&1 || true",
            )

    companion object {
        const val RESHAPE_BACKUP = "/var/lib/gryonixnexus-md-reshape.backup"
        const val RAID_DEVICES = "\$(mdadm --detail \"\$ARRAY\" | awk '/Raid Devices :/ {print \$4}')"
    }
}
