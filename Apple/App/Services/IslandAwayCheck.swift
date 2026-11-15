#if os(iOS)
import ActivityKit
import Foundation

/// Journals whether cards moved while the app is away
@MainActor
enum IslandAwayCheck {
    private static var left: (at: Date, shown: [String: String])?
    /// Shorter absences fit in the app's own background time
    static let worthNoting: TimeInterval = 40

    static func leaving() {
        let active = Activity<OperationActivityAttributes>.activities.filter { $0.activityState == .active }
        let shown = Dictionary(active.map { ($0.id, $0.content.state.progressText) }, uniquingKeysWith: { a, _ in a })
        left = shown.isEmpty ? nil : (Date(), shown)
    }

    static func back() {
        guard let left else { return }
        self.left = nil
        let away = Int(Date().timeIntervalSince(left.at))
        guard TimeInterval(away) >= worthNoting else { return }
        for (id, before) in left.shown { note(card: id, showed: before, away: away) }
    }

    private static func note(card id: String, showed before: String, away: Int) {
        let prefix = "away \(away) s:"
        guard let card = Activity<OperationActivityAttributes>.activities.first(where: { $0.id == id }) else {
            IslandJournal.shared.note("\(prefix) the card is gone")
            return
        }
        let now = card.content.state
        let title = card.attributes.title
        if card.activityState != .active || now.isFinished {
            IslandJournal.shared.note("\(prefix) the card was finished: \(now.errorMessage ?? now.progressText)", run: title)
        } else if now.progressText != before {
            IslandJournal.shared.note("\(prefix) the server moved the card: «\(before)» → «\(now.progressText)»", run: title)
        } else {
            IslandJournal.shared.note("\(prefix) the card did not move from «\(before)»", run: title)
        }
    }
}
#endif
