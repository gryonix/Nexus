import Foundation

/// A tapped alert about a problem, shown over its server
struct AlertCard: Identifiable, Equatable, Sendable {
    let title: String
    let body: String
    let kind: String

    var id: String { kind + title + body }

    /// Only a problem with advice gets a card
    init?(gnx: [String: Any], title: String, body: String) {
        let kind = gnx["kind"] as? String ?? ""
        guard Self.advice(forKind: kind) != nil, !title.isEmpty else { return nil }
        self.title = title
        self.body = body
        self.kind = kind
    }

    var advice: String? { Self.advice(forKind: kind) }

    static func advice(forKind kind: String) -> String? {
        switch kind {
        case "gnx.alert.raid":
            return UIL10n.string("A disk in the array has failed or dropped out. Open “%@” to see which one, and replace it.", UIL10n.string("Storage"))
        case "gnx.alert.smart":
            return UIL10n.string("A disk reports errors or wear. Open “%@” to check it, and plan to replace it.", UIL10n.string("Storage"))
        case "gnx.alert.space":
            return UIL10n.string("The disk is almost full. Remove old backups or unused Docker images, or move data to another disk.")
        case "gnx.alert.backup":
            return UIL10n.string("The last backup did not finish. Open “%@” to see why, then run it again.", UIL10n.string("Backups"))
        case "gnx.alert.drive_stale":
            return UIL10n.string("The backup drive has not been seen for a while. Plug it in, or check its cable and power.")
        case "gnx.alert.drive_readonly":
            return UIL10n.string("The backup drive accepts no writes. Check it for errors, or replace it.")
        case "gnx.alert.load":
            return UIL10n.string("The processor has been busy for a long time. Open “%@” to see what is using it.", UIL10n.string("Top processes"))
        case "gnx.alert.memory":
            return UIL10n.string("The machine is running out of memory. Open “%@” to see what is using it.", UIL10n.string("Top processes"))
        default:
            return nil
        }
    }
}
