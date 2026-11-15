import Foundation

/// The terminal sessions kept across app restarts, in order.

public struct SavedTerminalSession: Codable, Hashable, Sendable {
    public var profileID: UUID
    public var deploymentID: UUID
    public var nodeID: UUID?
    public var username: String

    public init(profileID: UUID, deploymentID: UUID, nodeID: UUID?, username: String) {
        self.profileID = profileID
        self.deploymentID = deploymentID
        self.nodeID = nodeID
        self.username = username
    }
}

public struct SavedTerminalSessions: Codable, Equatable, Sendable {
    public private(set) var records: [SavedTerminalSession] = []
    public private(set) var selected: UUID?

    public init() {}

    public mutating func open(_ record: SavedTerminalSession) {
        if let index = records.firstIndex(where: { $0.profileID == record.profileID }) {
            records[index] = record
        } else {
            records.append(record)
        }
        selected = record.profileID
    }

    public mutating func select(_ profileID: UUID) {
        guard records.contains(where: { $0.profileID == profileID }) else { return }
        selected = profileID
    }

    public mutating func close(profileID: UUID) {
        records.removeAll { $0.profileID == profileID }
        if selected == profileID { selected = records.last?.profileID }
    }

    public mutating func closeAll(deploymentID: UUID) {
        records.removeAll { $0.deploymentID == deploymentID }
        if let selected, !records.contains(where: { $0.profileID == selected }) {
            self.selected = records.last?.profileID
        }
    }

    public var selectedRecord: SavedTerminalSession? {
        records.first { $0.profileID == selected }
    }
}

/// Device-only storage for the saved sessions.
public struct SavedTerminalSessionsStore {
    private let defaults: UserDefaults
    private let key = "terminal.savedSessions"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> SavedTerminalSessions {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(SavedTerminalSessions.self, from: data)
        else { return SavedTerminalSessions() }
        return decoded
    }

    public func save(_ sessions: SavedTerminalSessions) {
        defaults.set(try? JSONEncoder().encode(sessions), forKey: key)
    }
}

public enum TerminalTmux {
    /// The command that joins or creates the profile's tmux session.
    public static func launchCommand(profileID: UUID) -> String {
        let name = "gryonix-" + profileID.uuidString.prefix(8).lowercased()
        return "command -v tmux >/dev/null 2>&1 && exec tmux new -A -s \(name)\r"
    }
}
