import Foundation

/// ZFS pools and btrfs filesystems built from whole disks
extension RaidPlan {
    /// How `zpool create` lays the disks out
    var zfsLayout: String {
        let paths = disks.map { ShellQuoting.singleQuoted($0.path) }
        switch level {
        case .raid0: return paths.joined(separator: " ")
        case .raid1: return "mirror " + paths.joined(separator: " ")
        case .raid5: return "raidz1 " + paths.joined(separator: " ")
        case .raid6: return "raidz2 " + paths.joined(separator: " ")
        case .raid10:
            return stride(from: 0, to: paths.count - 1, by: 2)
                .map { "mirror \(paths[$0]) \(paths[$0 + 1])" }.joined(separator: " ")
        }
    }

    func zfsScript() -> String {
        let members = disks.map { ShellQuoting.singleQuoted($0.path) }.joined(separator: " ")
        return ([
            "#!/bin/bash",
            "set -euo pipefail",
            "POOL=\(ShellQuoting.singleQuoted(name))",
            "MOUNT=\(ShellQuoting.singleQuoted(mountPoint ?? RaidPlan.mountPoint))",
        ] + ArrayScript.diskGuard(disks.map(\.identity)) + ZfsTools.installLines() + [
            "if ! modprobe zfs >/dev/null 2>&1; then",
            "  echo \"This kernel has no ZFS module. Install zfs-dkms, or pick another kind of array.\"",
            "  exit 3",
            "fi",
            "if ! zpool list -H \"$POOL\" >/dev/null 2>&1; then",
        ] + ArrayScript.checkAll(members) + [
            "  for disk in \(members); do",
            "    wipefs -a -q \"$disk\"",
            "  done",
            "  zpool create -f -o ashift=12 -O compression=lz4 -O atime=off -m \"$MOUNT\" \"$POOL\" \(zfsLayout)",
            "fi",
            "zpool set cachefile=/etc/zfs/zpool.cache \"$POOL\" || true",
            "echo \(Self.doneMarker)",
        ]).joined(separator: "\n") + "\n"
    }

    /// btrfs keeps metadata mirrored even under RAID 0
    var btrfsProfiles: String {
        switch level {
        case .raid10: return "-d raid10 -m raid10"
        case .raid0: return "-d raid0 -m raid1"
        default: return "-d raid1 -m raid1"
        }
    }

    func btrfsScript() -> String {
        let members = disks.map { ShellQuoting.singleQuoted($0.path) }.joined(separator: " ")
        return ([
            "#!/bin/bash",
            "set -euo pipefail",
            "NAME=\(ShellQuoting.singleQuoted(name))",
            "MOUNT=\(ShellQuoting.singleQuoted(mountPoint ?? RaidPlan.mountPoint))",
            "FIRST=\(ShellQuoting.singleQuoted(disks.first?.path ?? ""))",
        ] + ArrayScript.diskGuard(disks.map(\.identity)) + BtrfsTools.installLines() + [
            "if [ \"$(blkid -s LABEL -o value \"$FIRST\" || true)\" != \"$NAME\" ]; then",
        ] + ArrayScript.checkAll(members) + [
            "  for disk in \(members); do",
            "    wipefs -a -q \"$disk\"",
            "  done",
            "  mkfs.btrfs -q -f -L \"$NAME\" \(btrfsProfiles) \(members)",
            "  udevadm settle",
            "fi",
            "btrfs device scan >/dev/null",
            "install -d \"$MOUNT\"",
            "uuid=\"$(blkid -s UUID -o value \"$FIRST\")\"",
            "grep -q \"UUID=$uuid $MOUNT \" /etc/fstab || echo \"UUID=$uuid $MOUNT btrfs defaults,nofail 0 0\" >> /etc/fstab",
            "mountpoint -q \"$MOUNT\" || mount \"$MOUNT\"",
            "echo \(Self.doneMarker)",
        ]).joined(separator: "\n") + "\n"
    }
}

/// btrfs tools, installed when a btrfs array is built
enum BtrfsTools {
    static func installLines() -> [String] {
        [
            "if ! command -v mkfs.btrfs >/dev/null 2>&1; then",
            "  \(Apt.quiet) install -y -q btrfs-progs",
            "fi",
        ]
    }
}
