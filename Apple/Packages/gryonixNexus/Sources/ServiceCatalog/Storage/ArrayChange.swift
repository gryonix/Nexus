import Foundation

/// One change to a running array
public struct ArrayChange: Sendable, Hashable {
    public enum Action: String, Sendable, CaseIterable, Identifiable {
        case addSpare = "add-spare"
        case grow
        case replace
        case detach
        case remove
        case changeLevel = "change-level"
        case check
        case delete

        public var id: String { rawValue }

        /// Disks it takes from the free ones
        public func newDisks(for array: StorageArray) -> Int {
            switch self {
            case .addSpare, .replace: return 1
            case .grow: return array.kind == .zfs && array.raidLevel == .raid10 ? 2 : 1
            case .changeLevel: return array.kind == .md ? 1 : 0
            case .detach, .remove, .check, .delete: return 0
            }
        }

        /// Whether the user picks a member to act on
        public var takesMember: Bool { [.replace, .detach, .remove].contains(self) }
    }

    public let action: Action
    public let array: StorageArray
    /// The member taken out or replaced
    public var member: String?
    /// New disks, erased and put in
    public var disks: [ServerDisk] = []
    /// The level after a level change
    public var level: RaidPlan.Level?

    public init(action: Action, array: StorageArray, member: String? = nil,
                disks: [ServerDisk] = [], level: RaidPlan.Level? = nil) {
        self.action = action
        self.array = array
        self.member = member
        self.disks = disks
        self.level = level
    }

    public static let doneMarker = "GRYONIXNEXUS_ARRAY_CHANGE_DONE"

    /// Arrays whose disks this app changes
    public static func manages(_ array: StorageArray) -> Bool {
        [.md, .zfs, .btrfs].contains(array.kind) && !array.isForeignSystemPool
            && array.state != .stopped && array.state != .unknown
            && (array.kind != .btrfs || array.mountpoint != nil)
    }

    /// What can be done to the array right now
    public static func actions(for array: StorageArray, in hardware: ServerHardware) -> [Action] {
        guard manages(array) else { return [] }
        let free = RaidPlan.candidates(in: hardware).count
        let healthy = array.state == .clean
        return Action.allCases.filter { action in
            guard free >= action.newDisks(for: array) else { return false }
            switch action {
            case .check: return healthy
            case .delete: return !array.isCacheMirror
            default: return healthy && ArrayRules.allows(action, on: array)
            }
        }
    }

    /// Levels a level change may go to
    public static func levels(for array: StorageArray) -> [RaidPlan.Level] {
        ArrayRules.levelTargets(of: array)
    }

    public var isReady: Bool {
        (!action.takesMember || member.map(array.members.contains) == true)
            && disks.count == action.newDisks(for: array)
            && (action != .changeLevel || level.map(Self.levels(for: array).contains) == true)
    }
}

extension StorageArray {
    /// The level in RAID terms, whatever tool built it
    public var raidLevel: RaidPlan.Level? {
        switch (kind, level) {
        case (.zfs, "stripe"): return .raid0
        case (.zfs, "mirror"): return groups > 1 ? .raid10 : .raid1
        case (.zfs, "raidz1"): return .raid5
        case (.zfs, "raidz2"): return .raid6
        case (.zfs, _): return nil
        default:
            return level.hasPrefix("raid") ? Int(level.dropFirst(4)).flatMap(RaidPlan.Level.init(rawValue:)) : nil
        }
    }
}

/// Which change each kind and level of array allows
enum ArrayRules {
    static func allows(_ action: ArrayChange.Action, on array: StorageArray) -> Bool {
        let level = array.raidLevel
        let count = array.members.count
        switch (array.kind, action) {
        case (.md, .addSpare), (.md, .replace): return level != .raid0 && level != nil
        case (.md, .grow): return [.raid1, .raid5, .raid6].contains(level)
        case (.md, .detach): return [.raid1, .raid5, .raid6, .raid10].contains(level)
        case (.md, .remove): return mdShrinks(array)
        case (.zfs, .addSpare): return level != .raid0 && level != nil
        case (.zfs, .grow): return level != nil
        case (.zfs, .replace): return true
        case (.zfs, .detach): return [.raid1, .raid5, .raid6, .raid10].contains(level)
        case (.zfs, .remove): return (level == .raid1 || level == .raid0) && count >= 2
        case (.btrfs, .grow), (.btrfs, .replace): return true
        case (.btrfs, .remove): return count - 1 >= (level?.minimumDisks ?? 1)
        case (_, .changeLevel): return !levelTargets(of: array).isEmpty
        default: return false
        }
    }

    /// Whether md can drop a member at this level
    private static func mdShrinks(_ array: StorageArray) -> Bool {
        let count = array.members.count
        switch array.raidLevel {
        case .raid1: return count >= 2
        case .raid5: return count >= 4 && array.filesystem == "ext4"
        case .raid6: return count >= 5 && array.filesystem == "ext4"
        default: return false
        }
    }

    static func levelTargets(of array: StorageArray) -> [RaidPlan.Level] {
        switch (array.kind, array.raidLevel) {
        case (.md, .raid1): return array.members.count == 2 ? [.raid5] : []
        case (.md, .raid5): return [.raid6]
        case (.btrfs, let current):
            return RaidPlan.levels(for: .btrfs).filter { $0 != current && array.members.count >= $0.minimumDisks }
        default: return []
        }
    }
}
