import Foundation

extension ArrayChange {
    /// Space and protection before and after the change
    public struct Preview: Sendable, Hashable {
        public let usableBefore: Int64
        public let usableAfter: Int64
        public let failuresBefore: Int
        public let failuresAfter: Int
        /// Hours on big disks; the server keeps working
        public let takesLong: Bool
        /// The array's folder is offline for a few minutes
        public let goesOffline: Bool
    }

    public func preview(in hardware: ServerHardware) -> Preview {
        let size = { (path: String) -> Int64 in
            let disk = hardware.diskPath(containing: path)
            return hardware.disks.first { $0.path == disk }?.sizeBytes ?? 0
        }
        let before = array.members.map(size)
        let added = disks.map(\.sizeBytes)
        let after: [Int64]
        switch action {
        case .grow, .changeLevel: after = before + added
        case .remove: after = array.members.filter { $0 != member }.map(size)
        default: after = before
        }
        let kind = array.kind
        let current = array.raidLevel
        let next = action == .changeLevel ? level ?? current : current
        var failuresAfter = next?.survivableFailures(disks: after.count, kind: kind) ?? 0
        if action == .detach { failuresAfter = max((current?.survivableFailures(disks: before.count, kind: kind) ?? 0) - 1, 0) }
        return Preview(
            usableBefore: current?.usableBytes(of: before, kind: kind) ?? 0,
            usableAfter: next?.usableBytes(of: after, kind: kind) ?? 0,
            failuresBefore: current?.survivableFailures(disks: before.count, kind: kind) ?? 0,
            failuresAfter: failuresAfter,
            takesLong: takesLong,
            goesOffline: action == .remove && kind == .md && [.raid5, .raid6].contains(current))
    }

    var takesLong: Bool {
        switch action {
        case .grow, .replace, .changeLevel, .check: return true
        case .remove: return array.raidLevel != .raid1
        case .addSpare, .detach, .delete: return false
        }
    }

    /// The same change as flat fields for the agent
    public func spec(in hardware: ServerHardware) -> ArrayChangeSpec {
        let wholeDisks = Set(array.members.filter { $0 != member }.compactMap(hardware.diskPath(containing:)))
        return ArrayChangeSpec(
            action: action, kind: array.kind,
            address: array.kind == .zfs ? array.name : array.kind == .btrfs ? array.mountpoint ?? "" : array.address,
            name: RaidImportPlan.safeName(array.name), level: array.level,
            member: action == .grow && array.kind == .zfs && array.raidLevel == .raid1
                ? array.members.first ?? "" : member ?? "",
            disks: disks.map(\.path), devices: devicesAfter, newLevel: level?.rawValue ?? 0,
            members: action == .delete ? array.members + array.spares : [],
            checkDisks: takesLong && action != .check ? wholeDisks.sorted() : [],
            identities: disks.map(\.identity))
    }

    /// md member count once the change is done
    private var devicesAfter: Int {
        guard array.kind == .md else { return 0 }
        switch action {
        case .grow: return array.members.count + 1
        case .remove: return array.members.count - 1
        case .changeLevel: return level == .raid5 ? 3 : array.members.count + 1
        default: return 0
        }
    }
}
