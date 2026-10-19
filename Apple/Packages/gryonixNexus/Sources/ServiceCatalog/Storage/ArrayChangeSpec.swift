import Foundation

/// An array change as flat fields, and its script
public struct ArrayChangeSpec: Sendable, Hashable {
    public var action: ArrayChange.Action
    public var kind: StorageArray.Kind
    /// md device, ZFS pool name, or btrfs mount point
    public var address: String
    /// Array name for the job log
    public var name: String
    /// Current level as the server reports it
    public var level: String
    /// The member acted on
    public var member: String
    /// New disks, erased first
    public var disks: [String]
    /// md member count once done
    public var devices: Int
    /// Level number after a level change
    public var newLevel: Int
    /// Members wiped when the array is deleted
    public var members: [String]
    /// Whole disks whose SMART verdict must not be failing
    public var checkDisks: [String]
    /// The new disks as the app saw them
    public var identities: [DiskIdentity]

    public init(action: ArrayChange.Action, kind: StorageArray.Kind, address: String, name: String,
                level: String, member: String = "", disks: [String] = [], devices: Int = 0,
                newLevel: Int = 0, members: [String] = [], checkDisks: [String] = [],
                identities: [DiskIdentity] = []) {
        self.action = action
        self.kind = kind
        self.address = address
        self.name = name
        self.level = level
        self.member = member
        self.disks = disks
        self.devices = devices
        self.newLevel = newLevel
        self.members = members
        self.checkDisks = checkDisks
        self.identities = identities
    }

    public func script() -> String {
        let steps: ArraySteps
        switch kind {
        case .zfs: steps = ZfsChange(spec: self).steps()
        case .btrfs: steps = BtrfsChange(spec: self).steps()
        default: steps = MdChange(spec: self).steps()
        }
        let busy = steps.later.isEmpty ? [] : DiskJob.busyGuard
        let guardLines = disks.isEmpty ? [] : ArrayScript.diskGuard(identities)
        var lines = ["#!/bin/bash", "set -euo pipefail"] + variables + guardLines + busy + healthLines + steps.now
        if !steps.later.isEmpty {
            lines += DiskJob.launchLines(action: action.rawValue, target: name, variables: variables, body: steps.later)
        }
        return (lines + ["echo \(ArrayChange.doneMarker)"]).joined(separator: "\n") + "\n"
    }

    var variables: [String] {
        let head: String
        switch kind {
        case .zfs: head = "POOL="
        case .btrfs: head = "MOUNT="
        default: head = "ARRAY="
        }
        var lines = [head + ShellQuoting.singleQuoted(address)]
        if !member.isEmpty { lines.append("OLD=" + ShellQuoting.singleQuoted(member)) }
        for (index, disk) in disks.enumerated() {
            lines.append("NEW\(index == 0 ? "" : String(index + 1))=" + ShellQuoting.singleQuoted(disk))
        }
        return lines
    }

    /// Refuses when a disk that stays is failing
    var healthLines: [String] {
        guard !checkDisks.isEmpty else { return [] }
        let quoted = checkDisks.map(ShellQuoting.singleQuoted).joined(separator: " ")
        return [
            "CHECK=(\(quoted))",
            "if command -v smartctl >/dev/null 2>&1; then",
            "  for disk in \"${CHECK[@]}\"; do",
            "    if smartctl -H \"$disk\" 2>/dev/null | grep -q FAILED; then",
            "      echo \"$disk reports that it is failing. Replace that disk first.\"",
            "      exit 3",
            "    fi",
            "  done",
            "fi",
        ]
    }
}

/// Lines run now, and lines left to the background job
struct ArraySteps {
    var now: [String]
    var later: [String] = []
}

/// Pieces every kind of array shares
enum ArrayScript {
    /// Refuses a disk that is missing, changed or in use
    static func diskGuard(_ identities: [DiskIdentity] = []) -> [String] {
        let known = identities.filter { $0.sizeBytes > 0 }
        return expectedTable(known) + [
            "gnx_free() {",
            "  if [ ! -b \"$1\" ]; then",
            "    echo \"$1 is not a disk on this server.\"",
            "    exit 3",
            "  fi",
        ] + (known.isEmpty ? [] : identityCheck) + [
            "  if [ -n \"$(lsblk -rno MOUNTPOINT \"$1\" | tr -d '[:space:]')\" ] || lsblk -rno TYPE \"$1\" | grep -E '^(raid|lvm|crypt)' >/dev/null; then",
            "    echo \"$1 is in use. Nothing was erased.\"",
            "    exit 3",
            "  fi",
            "}",
        ]
    }

    private static func expectedTable(_ identities: [DiskIdentity]) -> [String] {
        guard !identities.isEmpty else { return [] }
        let rows = identities.map {
            "    \(ShellQuoting.singleQuoted($0.path))) echo \(ShellQuoting.singleQuoted("\($0.sizeBytes)|\($0.serial)")) ;;"
        }
        return ["gnx_expect() {", "  case \"$1\" in"] + rows + ["  esac", "}"]
    }

    private static let identityCheck = [
        "  local want size serial",
        "  want=\"$(gnx_expect \"$1\")\"",
        "  if [ -n \"$want\" ]; then",
        "    size=\"$(lsblk -dnbo SIZE \"$1\" | tr -d '[:space:]')\"",
        "    serial=\"$(lsblk -dno SERIAL \"$1\" | tr -d '[:space:]')\"",
        "    if [ \"${want%%|*}\" != \"$size\" ] || { [ -n \"${want#*|}\" ] && [ -n \"$serial\" ] && [ \"${want#*|}\" != \"$serial\" ]; }; then",
        "      echo \"$1 is not the disk the app listed. Nothing was erased.\"",
        "      exit 3",
        "    fi",
        "  fi",
    ]

    /// Checks every disk before the first one is wiped
    static func checkAll(_ members: String) -> [String] {
        ["  for disk in \(members); do", "    gnx_free \"$disk\"", "  done"]
    }

    /// Refuses while services keep data under `$MOUNT`
    static let servicesGuard = [
        "if [ -n \"$MOUNT\" ] && command -v docker >/dev/null 2>&1; then",
        "  for c in $(docker ps -aq); do",
        "    if docker inspect -f '{{range .Mounts}}{{println .Source}}{{end}}' \"$c\" | grep -qF -- \"$MOUNT\"; then",
        "      echo \"Services keep their data here. Move or remove them first.\"",
        "      exit 3",
        "    fi",
        "  done",
        "fi",
    ]

    /// Drops the `$MOUNT` line from /etc/fstab
    static let forgetMount = [
        "awk -v m=\"$MOUNT\" '$2 != m' /etc/fstab > /etc/fstab.gryonixnexus",
        "cat /etc/fstab.gryonixnexus > /etc/fstab",
        "rm -f /etc/fstab.gryonixnexus",
    ]

    /// Stops unless every disk is in the array
    static func requireMembers(_ members: [String], listing: String, noun: String) -> [String] {
        [
            "REAL=\"$(\(listing))\"",
            "for disk in \(members.map(ShellQuoting.singleQuoted).joined(separator: " ")); do",
            "  if ! printf '%s\\n' \"$REAL\" | grep -qxF -- \"$disk\"; then",
            "    echo \"$disk is not in this \(noun).\"",
            "    exit 3",
            "  fi",
            "done",
        ]
    }

    static let zfsMembers = "zpool status -LP \"$POOL\" | awk '$1 ~ /^\\/dev\\// {print $1}'"
    static let btrfsMembers = "btrfs filesystem show \"$MOUNT\" | awk '$NF ~ /^\\/dev\\// {print $NF}'"

    static func wipe(_ members: [String], with command: String) -> [String] {
        [
            "WIPE=(\(members.map(ShellQuoting.singleQuoted).joined(separator: " ")))",
            "for disk in \"${WIPE[@]}\"; do",
            "  \(command)",
            "done",
        ]
    }
}
