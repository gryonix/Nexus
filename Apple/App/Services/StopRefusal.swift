import AgentClient
import Foundation
import UserNotifications

/// A stop that found nothing to act on
enum StopMiss: Error {
    case serverGone
    case nothingRunning
}

/// Tells the user a server did not stop an operation
@MainActor
enum StopRefusal {
    enum Card {
        case operation(UUID)
        case job(String)
    }

    /// The refusal in the user's words
    static func reason(of error: Error) -> String {
        if case AgentError.rpc(let code, _) = error, code == "failed_precondition" {
            return UIL10n.string("The server can't stop this step once it has started.")
        }
        switch error as? StopMiss {
        case .serverGone: return UIL10n.string("This server is no longer in the app.")
        case .nothingRunning: return UIL10n.string("The server is no longer running this.")
        case nil: return UIL10n.string("Couldn't stop: %@", error.localizedDescription)
        }
    }

    /// The title of the server's card for a job
    static func jobTitle(_ job: String) -> String {
        #if os(iOS)
        return OperationActivities.shared.jobCard(job)?.attributes.title ?? ""
        #else
        return ""
        #endif
    }

    static func report(_ error: Error, title: String, card: Card) {
        let reason = reason(of: error)
        #if os(iOS)
        switch card {
        case .operation(let id): OperationActivities.shared.showStopRefused(reason, id: id)
        case .job(let job): OperationActivities.shared.showStopRefused(reason, job: job)
        }
        #endif
        Task { await post(reason, title: title) }
    }

    private static func post(_ reason: String, title: String) async {
        #if !os(tvOS)
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? UIL10n.string("Couldn't stop") : title
        content.body = reason
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
        #endif
    }
}
