import AgentClientSSH
import Foundation

/// Plain words for a connection that went away
enum LinkDropText {
    /// The reason to show, never a library's error code
    static func reason(_ error: Error) -> String {
        if SSHLinkDrop.isDropped(error) {
            return UIL10n.string("The connection to the server was cut.")
        }
        return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
