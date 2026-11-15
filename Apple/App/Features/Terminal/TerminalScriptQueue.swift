import Foundation

/// Script text waiting for a server's terminal
@MainActor
final class TerminalScriptQueue {
    static let shared = TerminalScriptQueue()
    private var pending: [UUID: String] = [:]

    func queue(_ text: String, for deploymentID: UUID) {
        pending[deploymentID] = text
    }

    func take(for deploymentID: UUID) -> String? {
        pending.removeValue(forKey: deploymentID)
    }

    var hasPending: Bool { !pending.isEmpty }
}
