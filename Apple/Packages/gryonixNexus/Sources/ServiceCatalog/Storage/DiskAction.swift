import Foundation

/// Formats one free disk and mounts it under /srv
public struct DiskFormatPlan: Sendable, Hashable {
    public enum Filesystem: String, Sendable, CaseIterable, Identifiable {
        case ext4, xfs, btrfs
        public var id: String { rawValue }
    }

    public let disk: String
    public let filesystem: Filesystem
    public let label: String
    public let mountPoint: String
    public let identity: DiskIdentity?

    public static let doneMarker = "GRYONIXNEXUS_DISK_FORMAT_DONE"

    public init(disk: String, filesystem: Filesystem, label: String, mountPoint: String,
                identity: DiskIdentity? = nil) {
        self.disk = disk
        self.filesystem = filesystem
        self.label = label
        self.mountPoint = mountPoint
        self.identity = identity
    }

    /// Label and first free mount for `disk`
    public static func plan(for disk: ServerDisk, filesystem: Filesystem, in hardware: ServerHardware) -> DiskFormatPlan {
        let base = "/srv/disk-" + RaidImportPlan.safeName(disk.name)
        let mounts = Set(hardware.disks.flatMap(\.mountpoints) + hardware.volumes.compactMap(\.mountpoint))
        let mount = ([base] + (2...99).map { base + "-\($0)" }).first { !mounts.contains($0) } ?? base
        return DiskFormatPlan(disk: disk.path, filesystem: filesystem,
                              label: String(("gnx-" + RaidImportPlan.safeName(disk.name)).prefix(12)), mountPoint: mount,
                              identity: disk.identity)
    }

    /// Disks that are not system, array members or mounted
    public static func candidates(in hardware: ServerHardware) -> [ServerDisk] {
        RaidPlan.candidates(in: hardware)
    }

    private var makeFilesystem: String {
        switch filesystem {
        case .ext4: return "mkfs.ext4 -q -L \"$LABEL\" \"$part\""
        case .xfs: return "mkfs.xfs -f -q -L \"$LABEL\" \"$part\""
        case .btrfs: return "mkfs.btrfs -f -q -L \"$LABEL\" \"$part\""
        }
    }

    private var tools: [String] {
        switch filesystem {
        case .ext4: return []
        case .xfs: return DiskFormatPlan.install(command: "mkfs.xfs", package: "xfsprogs")
        case .btrfs: return BtrfsTools.installLines()
        }
    }

    static func install(command: String, package: String) -> [String] {
        [
            "if ! command -v \(command) >/dev/null 2>&1; then",
            "  \(Apt.quiet) install -y -q \(package)",
            "fi",
        ]
    }

    public func script() -> String {
        let pass = filesystem == .ext4 ? "2" : "0"
        return ([
            "#!/bin/bash",
            "set -euo pipefail",
            "DISK=\(ShellQuoting.singleQuoted(disk))",
            "LABEL=\(ShellQuoting.singleQuoted(label))",
            "MOUNT=\(ShellQuoting.singleQuoted(mountPoint))",
        ] + ArrayScript.diskGuard(identity.map { [$0] } ?? []) + tools + [
            "if ! lsblk -rno LABEL \"$DISK\" | grep -qx -- \"$LABEL\"; then",
            "  gnx_free \"$DISK\"",
            "  for old in $(lsblk -rnpo NAME,TYPE \"$DISK\" | awk '$2 == \"part\" {print $1}'); do",
            "    zpool labelclear -f \"$old\" >/dev/null 2>&1 || true",
            "    wipefs -a -q \"$old\" || true",
            "  done",
            "  zpool labelclear -f \"$DISK\" >/dev/null 2>&1 || true",
            "  wipefs -a -q \"$DISK\"",
            "  size=\"$(blockdev --getsz \"$DISK\")\"",
            "  dd if=/dev/zero of=\"$DISK\" bs=512 seek=\"$((size - 8192))\" count=8192 conv=fsync status=none",
            "  printf 'label: gpt\\n,,L\\n' | sfdisk -q \"$DISK\"",
            "  udevadm settle",
            "  part=\"$(lsblk -rnpo NAME,TYPE \"$DISK\" | awk '$2 == \"part\" {print $1; exit}')\"",
            "  \(makeFilesystem)",
            "  udevadm settle",
            "fi",
            "part=\"$(lsblk -rnpo NAME,LABEL \"$DISK\" | awk -v l=\"$LABEL\" '$2 == l {print $1; exit}')\"",
            "install -d \"$MOUNT\"",
            "uuid=\"$(blkid -s UUID -o value \"$part\")\"",
            "grep -q \"UUID=$uuid $MOUNT \" /etc/fstab || echo \"UUID=$uuid $MOUNT \(filesystem.rawValue) defaults,nofail 0 \(pass)\" >> /etc/fstab",
            "mountpoint -q \"$MOUNT\" || mount \"$MOUNT\"",
            "echo \(Self.doneMarker)",
        ]).joined(separator: "\n") + "\n"
    }
}

/// Unmounts a data disk and drops its fstab line
public struct DiskReleasePlan: Sendable, Hashable {
    public let mountPoint: String

    public static let doneMarker = "GRYONIXNEXUS_DISK_RELEASE_DONE"
    /// Mounts under these may be released
    public static let prefixes = ["/srv/", "/mnt/", "/media/"]

    public init(mountPoint: String) {
        self.mountPoint = mountPoint
    }

    /// The disk's mount, when this app may release it
    public static func mount(of disk: ServerDisk) -> String? {
        disk.dataMount.flatMap { mount in prefixes.contains(where: mount.hasPrefix) ? mount : nil }
    }

    public func script() -> String {
        (["#!/bin/bash", "set -euo pipefail", "MOUNT=\(ShellQuoting.singleQuoted(mountPoint))"]
            + ArrayScript.servicesGuard + [
                "if mountpoint -q \"$MOUNT\"; then",
                "  umount \"$MOUNT\"",
                "fi",
            ] + ArrayScript.forgetMount + ["echo \(Self.doneMarker)"]).joined(separator: "\n") + "\n"
    }
}

/// Reads a disk briefly so its light blinks
public enum DiskBlink {
    public static let doneMarker = "GRYONIXNEXUS_DISK_BLINK_DONE"

    public static func script(disk: String) -> String {
        ([
            "#!/bin/bash",
            "set -uo pipefail",
            "DISK=\(ShellQuoting.singleQuoted(disk))",
            "if command -v ledctl >/dev/null 2>&1; then",
            "  ledctl locate=\"$DISK\" >/dev/null 2>&1 || true",
            "fi",
            "timeout 30 dd if=\"$DISK\" of=/dev/null bs=1M iflag=direct status=none || true",
            "if command -v ledctl >/dev/null 2>&1; then",
            "  ledctl locate_off=\"$DISK\" >/dev/null 2>&1 || true",
            "fi",
            "echo \(doneMarker)",
        ]).joined(separator: "\n") + "\n"
    }
}
