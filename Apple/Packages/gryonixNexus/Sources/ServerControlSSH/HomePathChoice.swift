import Foundation

/// How this device reaches a machine behind the VPS
public enum HomePathChoice: String, Sendable, CaseIterable, Codable {
    case automatic
    case throughVPS
    case localNetwork

    /// Which links the runner may try, in order
    public struct Plan: Sendable, Equatable {
        public let localFirst: Bool
        public let usesVPS: Bool
        public let localLastResort: Bool
    }

    public var plan: Plan {
        switch self {
        case .automatic: Plan(localFirst: true, usesVPS: true, localLastResort: true)
        case .throughVPS: Plan(localFirst: false, usesVPS: true, localLastResort: false)
        case .localNetwork: Plan(localFirst: true, usesVPS: false, localLastResort: false)
        }
    }

    private static let prefix = "home-path-"

    /// This device's choice for one server
    public static func load(for deploymentID: UUID, defaults: UserDefaults = .standard) -> HomePathChoice {
        defaults.string(forKey: prefix + deploymentID.uuidString).flatMap(Self.init(rawValue:)) ?? .automatic
    }

    public static func save(_ choice: HomePathChoice, for deploymentID: UUID,
                            defaults: UserDefaults = .standard) {
        let key = prefix + deploymentID.uuidString
        if choice == .automatic { defaults.removeObject(forKey: key) } else { defaults.set(choice.rawValue, forKey: key) }
    }
}
