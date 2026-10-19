/// A software RAID array built from whole disks
public struct RaidPlan: Sendable, Hashable {
    public enum Level: Int, Sendable, CaseIterable, Identifiable {
        case raid0 = 0, raid1 = 1, raid5 = 5, raid6 = 6, raid10 = 10

        public var id: Int { rawValue }

        public var minimumDisks: Int {
            switch self {
            case .raid0, .raid1: return 2
            case .raid5: return 3
            case .raid6, .raid10: return 4
            }
        }

        /// Disks that may fail without losing data
        public func survivableFailures(disks: Int) -> Int {
            switch self {
            case .raid0: return 0
            case .raid1: return max(disks - 1, 0)
            case .raid5, .raid10: return 1
            case .raid6: return 2
            }
        }

        /// Failures survived when built as `kind`
        public func survivableFailures(disks: Int, kind: StorageArray.Kind) -> Int {
            if kind == .btrfs, self == .raid1 { return disks >= 2 ? 1 : 0 }
            return survivableFailures(disks: disks)
        }

        /// Space left for data when built as `kind`
        public func usableBytes(of sizes: [Int64], kind: StorageArray.Kind) -> Int64 {
            let total = sizes.reduce(0, +)
            switch (kind, self) {
            case (.zfs, .raid0), (.btrfs, .raid0): return total
            case (.btrfs, .raid1): return min(total / 2, total - (sizes.max() ?? 0))
            default: return usableBytes(of: sizes)
            }
        }

        public func usableBytes(of sizes: [Int64]) -> Int64 {
            guard let smallest = sizes.min() else { return 0 }
            let count = Int64(sizes.count)
            switch self {
            case .raid0: return smallest * count
            case .raid1: return smallest
            case .raid5: return smallest * (count - 1)
            case .raid6: return smallest * (count - 2)
            case .raid10: return smallest * (count / 2)
            }
        }
    }

    public let level: Level
    public let disks: [ServerDisk]
    /// What builds it: mdadm, ZFS or btrfs
    public let kind: StorageArray.Kind
    public let name: String
    /// Where it is mounted; nil leaves formatting to the caller
    public let mountPoint: String?

    public static let storageName = "gryonixnexus"
    public static let cacheName = "gnx-fast"
    public static let mountPoint = "/srv/gryonixnexus-storage"
    public static let doneMarker = "GRYONIXNEXUS_RAID_DONE"

    public init(level: Level, disks: [ServerDisk], kind: StorageArray.Kind = .md, name: String = storageName,
                mountPoint: String? = RaidPlan.mountPoint) {
        self.level = level
        self.disks = disks
        self.kind = kind
        self.name = name
        self.mountPoint = mountPoint
    }

    /// Kinds of array this app can build
    public static let buildableKinds: [StorageArray.Kind] = [.md, .zfs, .btrfs]

    /// Levels offered per kind, without btrfs RAID 5 and 6
    public static func levels(for kind: StorageArray.Kind) -> [Level] {
        kind == .btrfs ? [.raid0, .raid1, .raid10] : Level.allCases
    }

    /// Two fast disks mirrored for the cache
    public static func cacheMirror(_ disks: [ServerDisk]) -> RaidPlan {
        RaidPlan(level: .raid1, disks: disks, name: cacheName, mountPoint: nil)
    }

    public var device: String { "/dev/md/\(name)" }

    /// A storage array under the first free name and mount
    public static func storage(level: Level, disks: [ServerDisk], kind: StorageArray.Kind = .md,
                               in hardware: ServerHardware) -> RaidPlan {
        let names = Set(StorageArray.all(in: hardware).map(\.name))
        let mounts = Set(hardware.volumes.compactMap(\.mountpoint) + hardware.disks.flatMap(\.mountpoints))
        var index = 1
        while true {
            let suffix = index == 1 ? "" : String(index)
            if !names.contains(storageName + suffix), !mounts.contains(mountPoint + suffix) {
                return RaidPlan(level: level, disks: disks, kind: kind, name: storageName + suffix,
                                mountPoint: mountPoint + suffix)
            }
            index += 1
        }
    }

    /// Disks that may be wiped for an array
    public static func candidates(in hardware: ServerHardware) -> [ServerDisk] {
        hardware.disks.filter { !$0.isSystem && !$0.raidMember && $0.dataMount == nil }
    }

    public var isValid: Bool {
        Self.levels(for: kind).contains(level) && disks.count >= level.minimumDisks
            && (level != .raid10 || disks.count.isMultiple(of: 2))
    }

    public var usableBytes: Int64 { level.usableBytes(of: disks.map(\.sizeBytes), kind: kind) }

    public var survivableFailures: Int { level.survivableFailures(disks: disks.count, kind: kind) }

    public func script() -> String {
        switch kind {
        case .zfs: return zfsScript()
        case .btrfs: return btrfsScript()
        default: return mdScript()
        }
    }

    private func mdScript() -> String {
        let members = disks.map { ShellQuoting.singleQuoted($0.path) }.joined(separator: " ")
        var lines = ["#!/bin/bash", "set -euo pipefail", "ARRAY=\(ShellQuoting.singleQuoted(device))"]
        if let mountPoint { lines.append("MOUNT=\(ShellQuoting.singleQuoted(mountPoint))") }
        lines += ArrayScript.diskGuard(disks.map(\.identity)) + Self.installLines() + createLines(members: members)
        if mountPoint != nil { lines += Self.mountLines() }
        return (lines + ["echo \(Self.doneMarker)"]).joined(separator: "\n") + "\n"
    }

    static func installLines() -> [String] {
        [
            "if ! command -v mdadm >/dev/null 2>&1; then",
            "  \(Apt.quiet) install -y -q mdadm",
            "fi",
        ]
    }

    private func createLines(members: String) -> [String] {
        [
            "if [ ! -e \"$ARRAY\" ]; then",
        ] + ArrayScript.checkAll(members) + [
            "  for disk in \(members); do",
            "    wipefs -a -q \"$disk\"",
            "  done",
            "  mdadm --create \"$ARRAY\" --name=\(name) --metadata=1.2 --run "
                + "--level=\(level.rawValue) --raid-devices=\(disks.count) \(members)",
            "  wipefs -a -q \"$ARRAY\"",
        ] + (mountPoint == nil ? [] : ["  mkfs.ext4 -q -L gnx-storage \"$ARRAY\""]) + [
            "  install -d /etc/mdadm",
            "  mdadm --detail --brief \"$ARRAY\" >> /etc/mdadm/mdadm.conf",
            "  update-initramfs -u >/dev/null 2>&1 || true",
            "fi",
        ]
    }

    static func mountLines() -> [String] {
        [
            "install -d \"$MOUNT\"",
            "uuid=\"$(blkid -s UUID -o value \"$ARRAY\")\"",
            "grep -q \"UUID=$uuid $MOUNT \" /etc/fstab || echo \"UUID=$uuid $MOUNT ext4 defaults,nofail 0 2\" >> /etc/fstab",
            "mountpoint -q \"$MOUNT\" || mount \"$MOUNT\"",
        ]
    }
}
