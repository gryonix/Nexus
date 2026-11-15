import Foundation

/// The kinds of trouble the dashboard counts
public enum ServerProblem: String, CaseIterable, Sendable, Hashable {
    case unreachable
    case diskAlmostFull
    case serviceDown
    case updatesPending
}

/// What is known about one server's health
public struct ServerHealthFacts: Equatable, Sendable {
    public let id: UUID
    public var unreachable: Bool
    /// Fraction of the disk in use, when known
    public var diskFraction: Double?
    public var servicesDown: Int?
    public var updatesPending: Int?

    public init(id: UUID, unreachable: Bool = false, diskFraction: Double? = nil,
                servicesDown: Int? = nil, updatesPending: Int? = nil) {
        self.id = id
        self.unreachable = unreachable
        self.diskFraction = diskFraction
        self.servicesDown = servicesDown
        self.updatesPending = updatesPending
    }

    public var problems: Set<ServerProblem> {
        var found: Set<ServerProblem> = []
        if unreachable { found.insert(.unreachable) }
        if let disk = diskFraction, disk >= ServerProblems.diskThreshold { found.insert(.diskAlmostFull) }
        if let down = servicesDown, down > 0 { found.insert(.serviceDown) }
        if let pending = updatesPending, pending > 0 { found.insert(.updatesPending) }
        return found
    }
}

/// Counts and filters over the fleet
public enum ServerProblems {
    public static let diskThreshold = 0.9

    public static func counts(_ facts: [ServerHealthFacts]) -> [ServerProblem: Int] {
        var counts: [ServerProblem: Int] = [:]
        for fact in facts {
            for problem in fact.problems { counts[problem, default: 0] += 1 }
        }
        return counts
    }

    public static func ids(with problem: ServerProblem, in facts: [ServerHealthFacts]) -> Set<UUID> {
        Set(facts.filter { $0.problems.contains(problem) }.map(\.id))
    }
}

/// Offline servers last, the rest in the user's order
public enum ServerListOrdering {
    public static func ordered<T>(_ items: [T], isOffline: (T) -> Bool) -> [T] {
        items.filter { !isOffline($0) } + items.filter(isOffline)
    }
}
