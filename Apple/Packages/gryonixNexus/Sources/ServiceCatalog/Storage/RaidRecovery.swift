/// Brings an existing array back without touching its data
public struct RaidImportPlan: Sendable, Hashable {
    public let array: StorageArray
    /// nil only assembles; the cache step mounts a mirror
    public let mountPoint: String?

    public static let doneMarker = "GRYONIXNEXUS_RAID_IMPORT_DONE"

    public init(array: StorageArray) {
        self.array = array
        mountPoint = array.isCacheMirror || array.kind != .md ? nil
            : array.isStorage ? RaidPlan.mountPoint : "/srv/raid-\(Self.safeName(array.name))"
    }

    static func safeName(_ name: String) -> String {
        String(name.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" })
    }

    public func script() -> String {
        if array.kind == .zfs { return zfsScript() }
        var lines = ["#!/bin/bash", "set -euo pipefail",
                     "ARRAY=\(ShellQuoting.singleQuoted(array.address))"]
        if let mountPoint { lines.append("MOUNT=\(ShellQuoting.singleQuoted(mountPoint))") }
        lines += RaidPlan.installLines() + assembleLines()
        if mountPoint != nil { lines += filesystemCheck() + RaidPlan.mountLines() }
        return (lines + ["echo \(Self.doneMarker)"]).joined(separator: "\n") + "\n"
    }

    private func zfsScript() -> String {
        ([
            "#!/bin/bash",
            "set -euo pipefail",
            "POOL=\(ShellQuoting.singleQuoted(array.name))",
            "ID=\(ShellQuoting.singleQuoted(array.uuid ?? array.name))",
        ] + ZfsTools.installLines() + [
            "if ! zpool list -H \"$POOL\" >/dev/null 2>&1; then",
            "  zpool import -f \"$ID\"",
            "fi",
            "zpool set cachefile=/etc/zfs/zpool.cache \"$POOL\" || true",
            "echo \(Self.doneMarker)",
        ]).joined(separator: "\n") + "\n"
    }

    private func assembleLines() -> [String] {
        let uuid = ShellQuoting.singleQuoted(array.uuid ?? "")
        return [
            "if ! mdadm --detail \"$ARRAY\" >/dev/null 2>&1; then",
            "  mdadm --assemble \"$ARRAY\" --uuid=\(uuid) --run",
            "fi",
            "install -d /etc/mdadm",
            "grep -q \(uuid) /etc/mdadm/mdadm.conf 2>/dev/null || mdadm --detail --brief \"$ARRAY\" >> /etc/mdadm/mdadm.conf",
            "update-initramfs -u >/dev/null 2>&1 || true",
        ]
    }

    private func filesystemCheck() -> [String] {
        [
            "if [ -z \"$(blkid -s TYPE -o value \"$ARRAY\" || true)\" ]; then",
            "  echo \"The array holds no filesystem; nothing was formatted.\"",
            "  exit 3",
            "fi",
        ]
    }
}

/// Swaps a failed array member for a new disk
public struct RaidRepairPlan: Sendable, Hashable {
    public let array: StorageArray
    public let replacement: ServerDisk

    public static let doneMarker = "GRYONIXNEXUS_RAID_REPAIR_DONE"

    public init(array: StorageArray, replacement: ServerDisk) {
        self.array = array
        self.replacement = replacement
    }

    /// Disks that may take the failed one's place
    public static func candidates(in hardware: ServerHardware, for array: StorageArray) -> [ServerDisk] {
        RaidPlan.candidates(in: hardware).filter { !array.members.contains($0.path) }
    }

    public func script() -> String {
        if array.kind == .zfs { return zfsScript() }
        return ([
            "#!/bin/bash",
            "set -euo pipefail",
            "ARRAY=\(ShellQuoting.singleQuoted(array.address))",
            "NEW=\(ShellQuoting.singleQuoted(replacement.path))",
        ] + ArrayScript.diskGuard([replacement.identity]) + [
            "mdadm \"$ARRAY\" --remove failed >/dev/null 2>&1 || true",
            "mdadm \"$ARRAY\" --remove detached >/dev/null 2>&1 || true",
            "if ! mdadm --detail \"$ARRAY\" | grep -q \"$NEW\"; then",
            "  gnx_free \"$NEW\"",
            "  wipefs -a -q \"$NEW\"",
            "  mdadm \"$ARRAY\" --add \"$NEW\"",
            "fi",
            "echo \(Self.doneMarker)",
        ]).joined(separator: "\n") + "\n"
    }

    private func zfsScript() -> String {
        ([
            "#!/bin/bash",
            "set -euo pipefail",
            "POOL=\(ShellQuoting.singleQuoted(array.name))",
            "OLD=\(ShellQuoting.singleQuoted(array.failed.first ?? ""))",
            "NEW=\(ShellQuoting.singleQuoted(replacement.path))",
        ] + ArrayScript.diskGuard([replacement.identity]) + [
            "if ! zpool status -LP \"$POOL\" | grep -q \"$NEW\"; then",
            "  gnx_free \"$NEW\"",
            "  wipefs -a -q \"$NEW\"",
            "  zpool replace -f \"$POOL\" \"$OLD\" \"$NEW\"",
            "fi",
            "echo \(Self.doneMarker)",
        ]).joined(separator: "\n") + "\n"
    }
}

/// ZFS tools, installed only when a pool is brought back
enum ZfsTools {
    static func installLines() -> [String] {
        [
            "if ! command -v zpool >/dev/null 2>&1; then",
            "  export DEBIAN_FRONTEND=noninteractive",
            "  if ! { \(Apt.dropRetiredSources); \(Apt.quiet) update -qq && \(Apt.quiet) install -y -qq zfsutils-linux; } >/dev/null 2>&1; then",
            "    echo \"ZFS tools could not be installed here. On Debian they come from the contrib section.\"",
            "    exit 3",
            "  fi",
            "fi",
        ]
    }
}
