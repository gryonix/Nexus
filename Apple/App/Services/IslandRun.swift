import Foundation
import ServerControl

/// One long action shown in the Dynamic Island
@MainActor
final class IslandRun {
    private let id = UUID()
    private let grace = BackgroundGrace()
    private var lastUpdate = Date.distantPast
    private var isFinished = false
    /// The newest state, waiting for the next redraw
    private var pending: (text: String, progress: Double?)?
    private var flush: Task<Void, Never>?

    static let updateSeconds: TimeInterval = 2

    /// A deployment lets its agent job update the card
    init(title: String, serverName: String, progressText: String, progress: Double? = nil,
         deployment: Deployment? = nil) {
        if let deployment { LiveActivityJobs.shared.track(id, title: title, on: deployment) }
        OperationActivities.shared.start(id: id, title: title, serverName: serverName,
                                         progressText: progressText, progress: progress)
    }

    /// Redraws at most every two seconds, the newest state last
    func update(_ text: String, progress: Double? = nil) {
        guard !isFinished else { return }
        pending = (text, progress)
        let wait = Self.updateSeconds - Date().timeIntervalSince(lastUpdate)
        guard wait > 0 else { return send() }
        guard flush == nil else { return }
        flush = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            self?.flush = nil
            self?.send()
        }
    }

    private func send() {
        guard !isFinished, let next = pending else { return }
        pending = nil
        lastUpdate = Date()
        OperationActivities.shared.update(id: id, progressText: next.text, progress: next.progress)
    }

    func finish(_ text: String, error: String? = nil) {
        guard !isFinished else { return }
        isFinished = true
        flush?.cancel()
        OperationActivities.shared.end(id: id, progressText: text, errorMessage: error)
        LiveActivityJobs.shared.forget(id)
        grace.end()
    }
}
