/// A USB drive that holds backup copies
public struct BackupDrive: Sendable, Hashable, Identifiable {
    public enum State: Sendable, Hashable {
        /// Plugged in, not prepared for backups yet
        case blank
        /// Prepared and mounted
        case ready
        /// Prepared and plugged in, not mounted
        case unmounted
        /// Chosen for backups, not plugged in
        case missing
    }

    /// The filesystem UUID, or the disk path while blank
    public let id: String
    public let name: String
    public let uuid: String?
    public let disk: ServerDisk?
    public let state: State

    public init(id: String, name: String, uuid: String?, disk: ServerDisk?, state: State) {
        self.id = id
        self.name = name
        self.uuid = uuid
        self.disk = disk
        self.state = state
    }

    public var sizeBytes: Int64 { disk?.sizeBytes ?? 0 }
}

/// Finds USB drives in the server's disk probe
public enum BackupDrives {
    /// Every removable drive plus the chosen ones that are missing
    public static func drives(in hardware: ServerHardware?, chosen: [String: String]) -> [BackupDrive] {
        let present = (hardware?.disks ?? []).filter(\.isBackupDriveCandidate).compactMap { disk in
            drive(on: disk, in: hardware)
        }
        let seen = Set(present.compactMap(\.uuid))
        let missing = chosen.keys.sorted().filter { !seen.contains($0) }.map { uuid in
            BackupDrive(id: uuid, name: chosen[uuid] ?? uuid, uuid: uuid, disk: nil, state: .missing)
        }
        return present + missing
    }

    private static func drive(on disk: ServerDisk, in hardware: ServerHardware?) -> BackupDrive? {
        let nodes = hardware?.blockNodes.filter { $0.disk == disk.path } ?? []
        if let own = nodes.first(where: { $0.label.hasPrefix(BackupDriveScripts.labelPrefix) && !$0.uuid.isEmpty }) {
            let name = String(own.label.dropFirst(BackupDriveScripts.labelPrefix.count))
            let mounted = own.mountpoint == BackupDriveScripts.mountPoint(name)
            return BackupDrive(id: own.uuid, name: name, uuid: own.uuid, disk: disk,
                               state: mounted ? .ready : .unmounted)
        }
        guard disk.mountpoints.isEmpty else { return nil }
        let title = disk.model.isEmpty ? disk.name : disk.model
        return BackupDrive(id: disk.path, name: title, uuid: nil, disk: disk, state: .blank)
    }

    /// The first free name of the form usbN
    public static func suggestedName(taken: [String]) -> String {
        (1...99).map { "usb\($0)" }.first { !taken.contains($0) } ?? "usb"
    }

    /// Lowercase letters, digits and dashes, at most 11
    public static func isValidName(_ name: String) -> Bool {
        guard (1...11).contains(name.count), let first = name.first,
              first.isLowercase || first.isNumber else { return false }
        return name.allSatisfy { ($0.isASCII && ($0.isLowercase || $0.isNumber)) || $0 == "-" }
    }
}

extension ServerDisk {
    /// Removable, and not the system or an array member
    public var isBackupDriveCandidate: Bool {
        removable && !isSystem && !raidMember
    }
}

/// What a drive check found
public struct BackupDriveCheck: Sendable, Hashable {
    public enum Smart: String, Sendable { case passed, failed, none }
    public enum Filesystem: String, Sendable { case clean, errors, busy, unknown }

    public var smart: Smart = .none
    public var filesystem: Filesystem = .unknown
    public var writeBytesPerSecond: Int64 = 0
    public var readBytesPerSecond: Int64 = 0

    public init() {}

    public static func parse(_ output: String) -> BackupDriveCheck {
        var check = BackupDriveCheck()
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count >= 2 else { continue }
            switch parts[0] {
            case "GRYONIXNEXUS_DRIVE_SMART": check.smart = Smart(rawValue: parts[1]) ?? .none
            case "GRYONIXNEXUS_DRIVE_FSCK": check.filesystem = Filesystem(rawValue: parts[1]) ?? .unknown
            case "GRYONIXNEXUS_DRIVE_SPEED" where parts.count >= 3:
                check.writeBytesPerSecond = Int64(parts[1]) ?? 0
                check.readBytesPerSecond = Int64(parts[2]) ?? 0
            default: continue
            }
        }
        return check
    }
}

/// Root scripts for USB drives, identical to the agent's
public enum BackupDriveScripts {
    public static let root = "/srv/gryonix-backup"
    public static let labelPrefix = "gnxb-"
    public static let formatDone = "GRYONIXNEXUS_DRIVE_FORMAT_DONE"
    public static let attachDone = "GRYONIXNEXUS_DRIVE_ATTACH_DONE"
    public static let checkDone = "GRYONIXNEXUS_DRIVE_CHECK_DONE"
    public static let ejectDone = "GRYONIXNEXUS_DRIVE_EJECT_DONE"
    public static let forgetDone = "GRYONIXNEXUS_DRIVE_FORGET_DONE"
    /// Printed after formatting: `<marker> <uuid>`
    public static let uuidMarker = "GRYONIXNEXUS_DRIVE_UUID"

    public static func mountPoint(_ name: String) -> String { "\(root)/\(name)" }

    /// Whether a backup path lies on a USB drive
    public static func isDriveCopy(_ path: String) -> Bool {
        path.hasPrefix(root + "/") && !path.contains("..")
    }

    /// The new filesystem's UUID, from a format's output
    public static func formattedUUID(_ output: String) -> String? {
        output.split(separator: "\n").last { $0.hasPrefix(uuidMarker + " ") }
            .map { String($0.dropFirst(uuidMarker.count + 1)).trimmingCharacters(in: .whitespaces) }
    }

    private static func join(_ lines: [String]) -> String {
        lines.joined(separator: "\n") + "\n"
    }

    private static let removableGuard = [
        "removable=\"$(lsblk -dno TRAN,RM,HOTPLUG \"$DISK\" | tr -s ' ')\"",
        "case \" $removable \" in",
        "  *\" usb \"*|*\" 1 \"*) ;;",
        "  *) echo \"$DISK is not a removable drive. Nothing was erased.\"; exit 3 ;;",
        "esac",
    ]

    private static let attachLines = [
        "install -d -m 700 \"$MOUNT\"",
        "awk -v m=\"$MOUNT\" -v u=\"UUID=$uuid\" '$1 != u && $2 != m' /etc/fstab > /etc/fstab.gryonixnexus",
        "cat /etc/fstab.gryonixnexus > /etc/fstab",
        "rm -f /etc/fstab.gryonixnexus",
        "device=\"$(systemd-escape -p --suffix=device \"/dev/disk/by-uuid/$uuid\")\"",
        "echo \"UUID=$uuid $MOUNT ext4 nofail,noatime,x-systemd.device-timeout=5s,x-systemd.wanted-by=$device 0 2\" >> /etc/fstab",
        "systemctl daemon-reload >/dev/null 2>&1 || true",
        "mountpoint -q \"$MOUNT\" || mount \"$MOUNT\"",
        "chmod 700 \"$MOUNT\"",
        "printf '%s\\n' \"$uuid\" > \"$MOUNT/.gryonix-backup-drive\"",
        "echo \"GRYONIXNEXUS_DRIVE_UUID $uuid\"",
    ]

    private static func header(uuid: String, name: String, strict: Bool) -> [String] {
        ["#!/bin/bash", strict ? "set -euo pipefail" : "set -uo pipefail",
         "DRIVE=\(ShellQuoting.singleQuoted(uuid))",
         "MOUNT=\(ShellQuoting.singleQuoted(mountPoint(name)))"]
    }

    private static let pluggedIn = [
        "part=\"/dev/disk/by-uuid/$DRIVE\"",
        "if [ ! -b \"$part\" ]; then",
        "  echo \"The drive is not plugged in.\"",
        "  exit 3",
        "fi",
    ]

    private static let unmountOrRefuse = [
        "if mountpoint -q \"$MOUNT\" && ! umount \"$MOUNT\"; then",
        "  echo \"The drive is busy. A backup may be writing to it.\"",
        "  exit 3",
        "fi",
    ]

    public static func format(disk: String, name: String, identity: DiskIdentity?) -> String {
        join(["#!/bin/bash", "set -euo pipefail",
              "DISK=\(ShellQuoting.singleQuoted(disk))",
              "LABEL=\(ShellQuoting.singleQuoted(labelPrefix + name))",
              "MOUNT=\(ShellQuoting.singleQuoted(mountPoint(name)))"]
             + ArrayScript.diskGuard(identity.map { [$0] } ?? []) + removableGuard + [
                "for held in $(lsblk -rno MOUNTPOINT \"$DISK\" | grep '^/srv/gryonix-backup/' || true); do",
                "  umount \"$held\"",
                "done",
                "gnx_free \"$DISK\"",
                "for old in $(lsblk -rnpo NAME,TYPE \"$DISK\" | awk '$2 == \"part\" {print $1}'); do",
                "  wipefs -a -q \"$old\" || true",
                "done",
                "wipefs -a -q \"$DISK\"",
                "printf 'label: gpt\\n,,L\\n' | sfdisk -q \"$DISK\"",
                "udevadm settle",
                "part=\"$(lsblk -rnpo NAME,TYPE \"$DISK\" | awk '$2 == \"part\" {print $1; exit}')\"",
                "mkfs.ext4 -q -F -L \"$LABEL\" \"$part\"",
                "udevadm settle",
                "uuid=\"$(blkid -s UUID -o value \"$part\")\"",
             ] + attachLines + ["echo \(formatDone)"])
    }

    public static func attach(uuid: String, name: String) -> String {
        join(header(uuid: uuid, name: name, strict: true) + pluggedIn + [
            "if [ \"$(blkid -s TYPE -o value \"$part\")\" != ext4 ]; then",
            "  echo \"The drive is not prepared for backups. Format it first.\"",
            "  exit 3",
            "fi",
            "uuid=\"$DRIVE\"",
        ] + attachLines + ["echo \(attachDone)"])
    }

    private static let smartAndFsck = [
        "disk=\"/dev/$(lsblk -no PKNAME \"$part\" | head -n 1)\"",
        "case \"$(smartctl -d sat -H \"$disk\" 2>/dev/null || true)\" in",
        "  *PASSED*) echo \"GRYONIXNEXUS_DRIVE_SMART passed\" ;;",
        "  *FAILED*) echo \"GRYONIXNEXUS_DRIVE_SMART failed\" ;;",
        "  *) echo \"GRYONIXNEXUS_DRIVE_SMART none\" ;;",
        "esac",
        "remount=0",
        "if mountpoint -q \"$MOUNT\"; then",
        "  sync",
        "  if umount \"$MOUNT\" 2>/dev/null; then remount=1; fi",
        "fi",
        "if mountpoint -q \"$MOUNT\"; then",
        "  echo \"GRYONIXNEXUS_DRIVE_FSCK busy\"",
        "elif e2fsck -fn \"$part\" >/dev/null 2>&1; then",
        "  echo \"GRYONIXNEXUS_DRIVE_FSCK clean\"",
        "else",
        "  echo \"GRYONIXNEXUS_DRIVE_FSCK errors\"",
        "fi",
        "if [ \"$remount\" -eq 1 ]; then mount \"$MOUNT\" || true; fi",
    ]

    private static let speedLines = [
        "if mountpoint -q \"$MOUNT\"; then",
        "  probe=\"$MOUNT/.gnx-speed\"",
        "  start=\"$(date +%s%N)\"",
        "  if dd if=/dev/zero of=\"$probe\" bs=1M count=64 oflag=direct status=none 2>/dev/null; then",
        "    mid=\"$(date +%s%N)\"",
        "    dd if=\"$probe\" of=/dev/null bs=1M iflag=direct status=none 2>/dev/null || true",
        "    end=\"$(date +%s%N)\"",
        "    echo \"GRYONIXNEXUS_DRIVE_SPEED $((67108864 * 1000000000 / (mid - start + 1))) $((67108864 * 1000000000 / (end - mid + 1)))\"",
        "  else",
        "    echo \"GRYONIXNEXUS_DRIVE_SPEED 0 0\"",
        "  fi",
        "  rm -f \"$probe\"",
        "fi",
    ]

    public static func check(uuid: String, name: String) -> String {
        join(header(uuid: uuid, name: name, strict: false) + pluggedIn + smartAndFsck + speedLines
             + ["echo \(checkDone)"])
    }

    public static func eject(uuid: String, name: String) -> String {
        join(header(uuid: uuid, name: name, strict: true) + ["sync"] + unmountOrRefuse + [
            "part=\"/dev/disk/by-uuid/$DRIVE\"",
            "if [ -b \"$part\" ] && command -v udisksctl >/dev/null 2>&1; then",
            "  udisksctl power-off -b \"/dev/$(lsblk -no PKNAME \"$part\" | head -n 1)\" >/dev/null 2>&1 || true",
            "fi",
            "echo \(ejectDone)",
        ])
    }

    public static func forget(uuid: String, name: String) -> String {
        join(header(uuid: uuid, name: name, strict: true) + unmountOrRefuse + [
            "awk -v m=\"$MOUNT\" -v u=\"UUID=$DRIVE\" '$1 != u && $2 != m' /etc/fstab > /etc/fstab.gryonixnexus",
            "cat /etc/fstab.gryonixnexus > /etc/fstab",
            "rm -f /etc/fstab.gryonixnexus",
            "systemctl daemon-reload >/dev/null 2>&1 || true",
            "rmdir \"$MOUNT\" 2>/dev/null || true",
            "echo \(forgetDone)",
        ])
    }
}
