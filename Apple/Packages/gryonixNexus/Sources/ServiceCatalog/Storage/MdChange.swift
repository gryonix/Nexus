import Foundation

/// Array changes for Linux software RAID, done with mdadm
struct MdChange {
    let spec: ArrayChangeSpec

    static let reshapeBackup = "/var/lib/gryonixnexus-md-reshape.backup"
    static let raidDevices = "$(mdadm --detail \"$ARRAY\" | awk '/Raid Devices :/ {print $4}')"

    func steps() -> ArraySteps {
        switch spec.action {
        case .addSpare: return ArraySteps(now: add)
        case .grow: return ArraySteps(now: healthy + add + growTo(spec.devices),
                                      later: spec.level == "raid1" ? [] : wait + resize)
        case .replace: return ArraySteps(now: present + healthy + add + ["mdadm \"$ARRAY\" --replace \"$OLD\" --with \"$NEW\""],
                                         later: wait + ["mdadm \"$ARRAY\" --remove \"$OLD\""] + forget)
        case .detach: return ArraySteps(now: healthy + takeOut + forget)
        case .remove: return spec.level == "raid1" ? ArraySteps(now: healthy + takeOut + shrinkMirror + forget)
            : ArraySteps(now: present + healthy + shrinkCheck, later: shrinkJob)
        case .changeLevel: return changeLevel()
        case .check: return ArraySteps(now: [
            "md=\"$(basename \"$(readlink -f \"$ARRAY\")\")\"",
            "echo check > \"/sys/block/$md/md/sync_action\"",
        ])
        case .delete: return ArraySteps(now: delete)
        }
    }

    var present: [String] {
        [
            "if ! mdadm --detail \"$ARRAY\" | grep -qw -- \"$OLD\"; then",
            "  echo \"$OLD is not in this array.\"",
            "  exit 3",
            "fi",
        ]
    }

    var healthy: [String] {
        [
            "if mdadm --detail \"$ARRAY\" | grep -Eq 'State : .*(degraded|recovering|resyncing|reshaping)'; then",
            "  echo \"The array is not healthy right now. Wait until it is, then try again.\"",
            "  exit 3",
            "fi",
        ]
    }

    private var add: [String] {
        [
            "if ! mdadm --detail \"$ARRAY\" | grep -qw -- \"$NEW\"; then",
            "  gnx_free \"$NEW\"",
            "  wipefs -a -q \"$NEW\"",
            "  mdadm \"$ARRAY\" --add \"$NEW\"",
            "fi",
        ]
    }

    private func growTo(_ devices: Int) -> [String] {
        [
            "if [ \"\(Self.raidDevices)\" -lt \(devices) ]; then",
            "  mdadm --grow \"$ARRAY\" --raid-devices=\(devices)",
            "fi",
        ]
    }

    private var takeOut: [String] {
        [
            "if mdadm --detail \"$ARRAY\" | grep -qw -- \"$OLD\"; then",
            "  mdadm \"$ARRAY\" --fail \"$OLD\"",
            "  mdadm \"$ARRAY\" --remove \"$OLD\"",
            "fi",
        ]
    }

    private var forget: [String] { ["mdadm --zero-superblock \"$OLD\" >/dev/null 2>&1 || true"] }

    private var wait: [String] { ["mdadm --wait \"$ARRAY\" || true", "sleep 5"] }

    /// Grows the filesystem to the array's new size
    private var resize: [String] {
        [
            "target=\"$(findmnt -no TARGET \"$ARRAY\" | head -n 1 || true)\"",
            "case \"$(blkid -s TYPE -o value \"$ARRAY\" || true)\" in",
            "  ext2|ext3|ext4) resize2fs \"$ARRAY\" ;;",
            "  xfs) xfs_growfs \"$target\" ;;",
            "  btrfs) btrfs filesystem resize max \"$target\" ;;",
            "esac",
        ]
    }

    private var shrinkMirror: [String] {
        let force = spec.devices == 1 ? " --force" : ""
        return [
            "if [ \"\(Self.raidDevices)\" -gt \(spec.devices) ]; then",
            "  mdadm --grow \"$ARRAY\" --raid-devices=\(spec.devices)\(force)",
            "fi",
        ]
    }

    private func changeLevel() -> ArraySteps {
        if spec.newLevel == 5 {
            return ArraySteps(now: healthy + [
                "if mdadm --detail \"$ARRAY\" | grep -q 'Raid Level : raid1'; then",
                "  mdadm --grow \"$ARRAY\" --level=5",
                "fi",
            ] + add + growTo(spec.devices), later: wait + resize)
        }
        return ArraySteps(now: healthy + add + [
            "if mdadm --detail \"$ARRAY\" | grep -q 'Raid Level : raid5'; then",
            "  mdadm --grow \"$ARRAY\" --level=6 --raid-devices=\(spec.devices) --backup-file=\(Self.reshapeBackup)",
            "fi",
        ], later: wait + ["rm -f \(Self.reshapeBackup)"])
    }

    private var delete: [String] {
        [
            "MOUNT=\"$(findmnt -no TARGET \"$ARRAY\" | head -n 1 || true)\"",
        ] + ArrayScript.servicesGuard + [
            "uuid=\"$(mdadm --detail \"$ARRAY\" | awk '/UUID :/ {print $3}')\"",
            "members=\"$(mdadm --detail \"$ARRAY\" | awk '$NF ~ /^\\/dev\\// && NF > 4 {print $NF}')\"",
            "if [ -n \"$MOUNT\" ]; then",
            "  umount \"$MOUNT\"",
        ] + ArrayScript.forgetMount.map { "  " + $0 } + [
            "fi",
            "mdadm --stop \"$ARRAY\"",
            "for disk in $members; do",
            "  mdadm --zero-superblock \"$disk\" || true",
            "  wipefs -a -q \"$disk\" || true",
            "done",
            "if [ -f /etc/mdadm/mdadm.conf ]; then",
            "  sed -i \"/UUID=$uuid/d\" /etc/mdadm/mdadm.conf",
            "fi",
            "update-initramfs -u >/dev/null 2>&1 || true",
        ]
    }
}
