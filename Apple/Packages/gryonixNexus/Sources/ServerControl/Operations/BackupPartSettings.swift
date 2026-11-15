import Foundation
import ServiceCatalog

/// Which parts regular and pre-update backups copy
public struct BackupPartChoice: Sendable, Hashable {
    /// Scheduled runs and the backup button
    public var regular: Set<BackupPart>
    /// The backup an update takes first
    public var beforeUpdate: Set<BackupPart>

    public static let defaultRegular = Set(BackupPart.allCases)
    public static let defaultBeforeUpdate: Set<BackupPart> = [.settings, .databases]

    public init(regular: Set<BackupPart> = defaultRegular,
                beforeUpdate: Set<BackupPart> = defaultBeforeUpdate) {
        self.regular = regular
        self.beforeUpdate = beforeUpdate
    }
}

/// Which kind of backup a choice is about
public enum BackupPartScope: Sendable, Hashable {
    case regular, beforeUpdate
}

extension BackupPartChoice {
    public subscript(scope: BackupPartScope) -> Set<BackupPart> {
        get { scope == .regular ? regular : beforeUpdate }
        set { if scope == .regular { regular = newValue } else { beforeUpdate = newValue } }
    }
}

/// The choice read back from the server
public struct BackupPartsState: Sendable, Hashable {
    /// The shared choice, for services without their own
    public var choice: BackupPartChoice
    /// Services with their own choice, by catalog id
    public var services: [String: BackupPartChoice]
    /// False when the server's wrapper predates parts
    public var supported: Bool

    public init(choice: BackupPartChoice = BackupPartChoice(), services: [String: BackupPartChoice] = [:],
                supported: Bool = true) {
        self.choice = choice
        self.services = services
        self.supported = supported
    }

    /// What one service copies
    public func choice(for service: String) -> BackupPartChoice {
        services[service] ?? choice
    }

    /// On when shared and every listed service have it
    public func sharedIsOn(_ part: BackupPart, _ scope: BackupPartScope, among listed: [String]) -> Bool {
        choice[scope].contains(part) && listed.allSatisfy { choice(for: $0)[scope].contains(part) }
    }

    /// Turning a shared switch sets it for every listed service
    public func settingShared(_ part: BackupPart, _ scope: BackupPartScope, on: Bool,
                              among listed: [String]) -> BackupPartsChange {
        var shared = choice
        shared[scope] = Self.toggled(shared[scope], part, on)
        var own: [String: BackupPartChoice] = [:]
        for service in listed {
            var next = choice(for: service)
            next[scope] = Self.toggled(next[scope], part, on)
            own[service] = next
        }
        return BackupPartsChange(shared: shared, services: own)
    }

    /// One service's switch, leaving the rest as they are
    public func settingService(_ service: String, _ part: BackupPart, _ scope: BackupPartScope,
                               on: Bool) -> BackupPartsChange {
        var next = choice(for: service)
        next[scope] = Self.toggled(next[scope], part, on)
        return BackupPartsChange(shared: nil, services: [service: next])
    }

    /// The state with a change applied
    public func applying(_ change: BackupPartsChange) -> BackupPartsState {
        var next = self
        if let shared = change.shared { next.choice = shared }
        next.services.merge(change.services) { _, new in new }
        return next
    }

    private static func toggled(_ parts: Set<BackupPart>, _ part: BackupPart, _ on: Bool) -> Set<BackupPart> {
        on ? parts.union([part]) : parts.subtracting([part])
    }
}

/// What to write: the shared choice and services' own
public struct BackupPartsChange: Sendable, Hashable {
    public var shared: BackupPartChoice?
    public var services: [String: BackupPartChoice]

    public init(shared: BackupPartChoice?, services: [String: BackupPartChoice] = [:]) {
        self.shared = shared
        self.services = services
    }
}

public enum BackupPartsParsing {
    /// Parts in the wrapper's own order
    public static func words(_ parts: Set<BackupPart>) -> [String] {
        BackupPart.allCases.filter(parts.contains).map(\.rawValue)
    }

    /// Reads `show-parts` output
    public static func parse(_ output: String) -> BackupPartChoice {
        state(output).choice
    }

    /// Reads `show-parts` output, services' own lines too
    public static func state(_ output: String) -> BackupPartsState {
        var choice = BackupPartChoice()
        var own: [String: [BackupPartScope: Set<BackupPart>]] = [:]
        for line in output.split(separator: "\n") {
            let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            let parts = Set(pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
                .split(separator: " ").compactMap { BackupPart(rawValue: String($0)) })
            switch pair[0] {
            case "BACKUP_PARTS": choice.regular = parts
            case "UPDATE_PARTS": choice.beforeUpdate = parts
            default:
                guard let (service, scope) = serviceKey(pair[0]) else { continue }
                own[service, default: [:]][scope] = parts
            }
        }
        let services = own.mapValues { scopes in
            BackupPartChoice(regular: scopes[.regular] ?? choice.regular,
                             beforeUpdate: scopes[.beforeUpdate] ?? choice.beforeUpdate)
        }
        return BackupPartsState(choice: choice, services: services)
    }

    /// A service id and scope from a config key
    static func serviceKey(_ key: String) -> (String, BackupPartScope)? {
        let prefixes: [(String, BackupPartScope)] = [("BACKUP_PARTS_", .regular), ("UPDATE_PARTS_", .beforeUpdate)]
        guard let (prefix, scope) = prefixes.first(where: { key.hasPrefix($0.0) }) else { return nil }
        let name = String(key.dropFirst(prefix.count))
        guard !name.isEmpty, name.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "_" }) else { return nil }
        return (name.replacingOccurrences(of: "_", with: "-"), scope)
    }
}
