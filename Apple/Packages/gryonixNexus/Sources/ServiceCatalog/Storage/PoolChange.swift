import Foundation

/// Array changes for ZFS pools
struct ZfsChange {
    let spec: ArrayChangeSpec

    func steps() -> ArraySteps {
        switch spec.action {
        case .addSpare: return ArraySteps(now: unless(present: "$NEW", ["gnx_free \"$NEW\"", "wipefs -a -q \"$NEW\"", "zpool add -f \"$POOL\" spare \"$NEW\""]))
        case .grow: return ArraySteps(now: unless(present: "$NEW", ["gnx_free \"$NEW\"", "wipefs -a -q \"$NEW\""] + grow))
        case .replace: return ArraySteps(now: unless(present: "$NEW", ["gnx_free \"$NEW\"", "wipefs -a -q \"$NEW\"", "zpool replace -f \"$POOL\" \"$OLD\" \"$NEW\""]))
        case .detach: return ArraySteps(now: healthy + ["zpool offline \"$POOL\" \"$OLD\""])
        case .remove:
            if spec.level == "mirror" {
                return ArraySteps(now: healthy + ["zpool detach \"$POOL\" \"$OLD\""] + clearOld)
            }
            return ArraySteps(now: healthy + ["zpool remove \"$POOL\" \"$OLD\""],
                              later: ["zpool wait -t remove \"$POOL\""] + clearOld)
        case .check: return ArraySteps(now: ["zpool scrub \"$POOL\""])
        case .changeLevel: return ArraySteps(now: ["echo \"ZFS cannot change the level of a pool.\"", "exit 3"])
        case .delete: return ArraySteps(now: [
            "MOUNT=\"$(zfs get -H -o value mountpoint \"$POOL\" 2>/dev/null | grep '^/' || true)\"",
        ] + ArrayScript.servicesGuard
            + ArrayScript.requireMembers(spec.members, listing: ArrayScript.zfsMembers, noun: "pool")
            + ["zpool destroy -f \"$POOL\""]
            + ArrayScript.wipe(spec.members, with: "zpool labelclear -f \"$disk\" >/dev/null 2>&1 || true; wipefs -a -q \"$disk\" || true"))
        }
    }

    private func unless(present disk: String, _ body: [String]) -> [String] {
        ["if ! zpool status -LP \"$POOL\" | grep -qw -- \"\(disk)\"; then"] + body.map { "  " + $0 } + ["fi"]
    }

    private var healthy: [String] {
        [
            "if ! zpool status -x \"$POOL\" | grep -q 'is healthy'; then",
            "  echo \"The pool is not healthy right now. Wait until it is, then try again.\"",
            "  exit 3",
            "fi",
        ]
    }

    private var grow: [String] {
        switch spec.level {
        case "mirror" where spec.disks.count == 2: return ["gnx_free \"$NEW2\"", "wipefs -a -q \"$NEW2\"", "zpool add -f \"$POOL\" mirror \"$NEW\" \"$NEW2\""]
        case "mirror": return ["zpool attach -f \"$POOL\" \"$OLD\" \"$NEW\""]
        case "stripe": return ["zpool add -f \"$POOL\" \"$NEW\""]
        default: return [
            "vdev=\"$(zpool status -P \"$POOL\" | awk '$1 ~ /^raidz[123]-[0-9]+$/ {print $1; exit}')\"",
            "zpool attach -f \"$POOL\" \"$vdev\" \"$NEW\"",
        ]
        }
    }

    private var clearOld: [String] { ["zpool labelclear -f \"$OLD\" >/dev/null 2>&1 || true"] }
}

/// Array changes for multi-disk btrfs
struct BtrfsChange {
    let spec: ArrayChangeSpec

    func steps() -> ArraySteps {
        var steps = actionSteps()
        steps.now = mounted + steps.now
        return steps
    }

    private var mounted: [String] {
        [
            "if ! mountpoint -q \"$MOUNT\"; then",
            "  echo \"$MOUNT is not mounted.\"",
            "  exit 3",
            "fi",
        ]
    }

    private func actionSteps() -> ArraySteps {
        switch spec.action {
        case .grow: return ArraySteps(now: [
            "if ! btrfs filesystem show \"$MOUNT\" | grep -qw -- \"$NEW\"; then",
            "  gnx_free \"$NEW\"",
            "  wipefs -a -q \"$NEW\"",
            "  btrfs device add -f \"$NEW\" \"$MOUNT\"",
            "fi",
        ], later: ["btrfs balance start --full-balance \"$MOUNT\""])
        case .replace: return ArraySteps(now: present + ["gnx_free \"$NEW\"", "wipefs -a -q \"$NEW\""], later: [
            "btrfs replace start -B -f \"$OLD\" \"$NEW\" \"$MOUNT\"",
            "devid=\"$(btrfs filesystem show \"$MOUNT\" | awk -v d=\"$NEW\" '$NF == d {print $2}')\"",
            "btrfs filesystem resize \"$devid:max\" \"$MOUNT\"",
        ])
        case .remove: return ArraySteps(now: present, later: [
            "btrfs device remove \"$OLD\" \"$MOUNT\"",
            "wipefs -a -q \"$OLD\" || true",
        ])
        case .changeLevel: return ArraySteps(now: [], later: ["btrfs balance start \(profiles) \"$MOUNT\""])
        case .check: return ArraySteps(now: ["btrfs scrub start \"$MOUNT\" >/dev/null"])
        case .delete: return ArraySteps(now: ArrayScript.servicesGuard
            + ArrayScript.requireMembers(spec.members, listing: ArrayScript.btrfsMembers, noun: "filesystem") + [
            "umount \"$MOUNT\"",
        ] + ArrayScript.forgetMount + ArrayScript.wipe(spec.members, with: "wipefs -a -q \"$disk\" || true"))
        case .addSpare, .detach: return ArraySteps(now: ["echo \"btrfs has no spare or offline disks.\"", "exit 3"])
        }
    }

    private var present: [String] {
        [
            "if ! btrfs filesystem show \"$MOUNT\" | grep -qw -- \"$OLD\"; then",
            "  echo \"$OLD is not in this filesystem.\"",
            "  exit 3",
            "fi",
        ]
    }

    /// Data and metadata profiles for the target level
    private var profiles: String {
        switch spec.newLevel {
        case 0: return "-dconvert=raid0 -mconvert=raid1"
        case 10: return "-dconvert=raid10 -mconvert=raid10"
        default: return "-dconvert=raid1 -mconvert=raid1"
        }
    }
}
