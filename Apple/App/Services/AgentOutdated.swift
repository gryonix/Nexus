import AgentClient
import Foundation

/// Recognises what an older agent answers to newer requests
enum AgentOutdated {
    /// Replies of agents that predate the request
    private static let markers = [
        "unknown service '", "has no installer for '", "unknown method",
        "choose a disk task", "choose a channel"
    ]

    static func matches(_ error: Error) -> Bool {
        guard case AgentError.rpc(_, let message) = error else { return false }
        return markers.contains { message.contains($0) }
    }

    /// The error as the person reads it
    static func describe(_ error: Error) -> String {
        if matches(error) {
            return UIL10n.string("This server's agent is older than this app and does not know this action yet. Tap “Update the agent” on the server's General tab, then try again.")
        }
        return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
