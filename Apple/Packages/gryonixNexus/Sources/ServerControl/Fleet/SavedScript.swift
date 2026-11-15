import Foundation

/// A saved shell snippet
public struct SavedScript: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var body: String
    /// Servers it is offered for; empty means every server
    public var deploymentIDs: [UUID]

    public init(id: UUID = UUID(), name: String, body: String, deploymentIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.body = body
        self.deploymentIDs = deploymentIDs
    }

    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func appliesTo(_ deploymentID: UUID) -> Bool {
        deploymentIDs.isEmpty || deploymentIDs.contains(deploymentID)
    }

    /// Text typed into a terminal, ending in a newline
    public var terminalInput: String {
        let trimmed = body.trimmingCharacters(in: .newlines)
        return trimmed + "\n"
    }

    /// The command run through the SSH exec path
    public var execCommand: String {
        "sh -c " + ShellQuoting.singleQuoted(body)
    }
}

/// Edits on the saved scripts
public enum SavedScriptList {
    public static func available(for deploymentID: UUID, in all: [SavedScript]) -> [SavedScript] {
        all.filter { $0.appliesTo(deploymentID) }
    }

    public static func upserting(_ script: SavedScript, into all: [SavedScript]) -> [SavedScript] {
        if let index = all.firstIndex(where: { $0.id == script.id }) {
            var copy = all
            copy[index] = script
            return copy
        }
        return all + [script]
    }

    public static func removing(_ id: UUID, from all: [SavedScript]) -> [SavedScript] {
        all.filter { $0.id != id }
    }

    /// Forgets a deleted server in every script
    public static func forgettingServer(_ id: UUID, in all: [SavedScript]) -> [SavedScript] {
        all.map { script in
            var copy = script
            copy.deploymentIDs.removeAll { $0 == id }
            return copy
        }
    }
}
