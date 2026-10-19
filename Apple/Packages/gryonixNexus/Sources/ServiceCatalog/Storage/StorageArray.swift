import Foundation

/// An md device as lsblk shows it under its members
public struct ArrayVolume: Sendable, Hashable {
    public let name: String
    public let level: String
    public let mountpoint: String?
    public let filesystem: String?
    public let label: String?
}

/// One RAID array or pool and how healthy it is
public struct StorageArray: Sendable, Hashable, Identifiable {
    public enum State: Sendable, Hashable {
        case clean
        case degraded
        case rebuilding(percent: Double)
        /// Reading every block for errors
        case checking(percent: Double)
        /// Found on the disks but not running
        case stopped
        /// Nothing this account can read says
        case unknown
    }

    /// What keeps the array together
    public enum Kind: String, Sendable, Hashable {
        case md, zfs, btrfs, lvm, hardware
    }

    public var kind: Kind = .md
    public let name: String
    public let uuid: String?
    /// `/dev/md127` while running, nil while stopped
    public let device: String?
    public let level: String
    public let members: [String]
    public let failed: [String]
    /// Standby disks that take over a failed member
    public var spares: [String] = []
    /// Top-level groups of a ZFS pool, such as mirror pairs
    public var groups = 1
    public let slots: Int
    public let working: Int
    public let state: State
    public let mountpoint: String?
    public let filesystem: String?

    public var id: String { kind == .md ? uuid ?? name : "\(kind.rawValue):\(uuid ?? name)" }

    /// Arrays this product builds for data or cache
    public var isStorage: Bool { name == RaidPlan.storageName }
    public var isCacheMirror: Bool { name == RaidPlan.cacheName }

    /// Where assembling and mounting address it
    public var address: String { device ?? "/dev/md/\(name)" }

    /// A TrueNAS system pool: never imported on this machine
    public var isForeignSystemPool: Bool {
        kind == .zfs && ["boot-pool", "freenas-boot"].contains(name)
    }

    public var needsAttention: Bool {
        if isForeignSystemPool { return false }
        switch state {
        case .degraded, .stopped: return true
        case .clean, .rebuilding, .checking, .unknown: return false
        }
    }

    public var repairsHere: Bool { (kind == .md || kind == .zfs) && !isForeignSystemPool }

    public static func all(in hardware: ServerHardware) -> [StorageArray] {
        mdArrays(in: hardware) + PoolReader.zfs(in: hardware) + PoolReader.btrfs(in: hardware)
            + PoolReader.lvm(in: hardware) + PoolReader.controllers(in: hardware)
    }

    private static func mdArrays(in hardware: ServerHardware) -> [StorageArray] {
        let active = MdstatReader.arrays(hardware.mdstat).map { entry in array(entry, hardware: hardware) }
        let claimed = Set((active.flatMap(\.members) + active.flatMap(\.failed) + active.flatMap(\.spares))
            .compactMap(hardware.diskPath(containing:)))
        let running = Set(active.compactMap(\.uuid))
        let stopped = Dictionary(grouping: hardware.disks.filter { disk in
            guard let uuid = disk.raidUUID else { return false }
            return !claimed.contains(disk.path) && !running.contains(uuid)
        }, by: { $0.raidUUID ?? "" })
        return active + stopped.values.compactMap(stoppedArray).sorted { $0.name < $1.name }
    }

    private static func array(_ entry: MdstatReader.Entry, hardware: ServerHardware) -> StorageArray {
        let volume = hardware.volumes.first { $0.name == entry.device }
        let memberDisks = Set(entry.members.compactMap(hardware.diskPath(containing:)))
        let memberDisk = hardware.disks.first { memberDisks.contains($0.path) }
        var array = StorageArray(
            name: memberDisk?.raidName ?? entry.device, uuid: memberDisk?.raidUUID,
            device: "/dev/\(entry.device)", level: entry.level, members: entry.members,
            failed: entry.failed, slots: entry.slots, working: entry.working,
            state: entry.state, mountpoint: volume?.mountpoint, filesystem: volume?.filesystem)
        array.spares = entry.spares
        return array
    }

    private static func stoppedArray(_ disks: [ServerDisk]) -> StorageArray? {
        guard let first = disks.first else { return nil }
        return StorageArray(
            name: first.raidName ?? "md", uuid: first.raidUUID, device: nil, level: "",
            members: disks.map(\.path), failed: [], slots: disks.count, working: disks.count,
            state: .stopped, mountpoint: nil, filesystem: nil)
    }
}

/// Reads running arrays out of /proc/mdstat
enum MdstatReader {
    struct Entry {
        var device: String
        var level: String
        var members: [String] = []
        var failed: [String] = []
        var spares: [String] = []
        var slots = 0
        var working = 0
        var state = StorageArray.State.clean
    }

    static func arrays(_ text: String) -> [Entry] {
        var entries: [Entry] = []
        for line in text.split(separator: "\n").map(String.init) {
            if let entry = header(line) {
                entries.append(entry)
            } else if !entries.isEmpty {
                detail(line, into: &entries[entries.count - 1])
            }
        }
        return entries
    }

    private static func header(_ line: String) -> Entry? {
        let parts = line.split(separator: " ").map(String.init)
        guard parts.count >= 3, parts[0].hasPrefix("md"), parts[1] == ":" else { return nil }
        var entry = Entry(device: parts[0], level: "")
        for word in parts.dropFirst(2) {
            if word.hasPrefix("raid") { entry.level = word; continue }
            guard let bracket = word.firstIndex(of: "[") else { continue }
            let path = "/dev/" + word[..<bracket]
            if word.hasSuffix("(F)") { entry.failed.append(path) }
            else if word.hasSuffix("(S)") { entry.spares.append(path) }
            else { entry.members.append(path) }
        }
        if parts[2] == "inactive" { entry.state = .stopped }
        entry.slots = entry.members.count
        entry.working = entry.members.count
        return entry
    }

    private static func detail(_ line: String, into entry: inout Entry) {
        if let counts = line.range(of: #"\[(\d+)/(\d+)\]"#, options: .regularExpression) {
            let numbers = line[counts].dropFirst().dropLast().split(separator: "/").compactMap { Int($0) }
            if numbers.count == 2 {
                entry.slots = numbers[0]
                entry.working = numbers[1]
                if entry.working < entry.slots, entry.state == .clean { entry.state = .degraded }
            }
        }
        if let match = line.range(of: #"(recovery|resync|reshape|check) = +[0-9.]+%"#, options: .regularExpression) {
            let number = Double(line[match].split(separator: "=").last?
                .trimmingCharacters(in: .whitespaces).dropLast() ?? "") ?? 0
            entry.state = line[match].hasPrefix("check") ? .checking(percent: number) : .rebuilding(percent: number)
        }
    }
}
