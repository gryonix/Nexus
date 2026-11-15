import AgentControl
import Foundation
import ServerControl

/// One long action shown in the Dynamic Island
@MainActor
final class IslandRun {
    private let id = UUID()
    private let title: String
    private var grace: BackgroundGrace?
    private var lastUpdate = Date.distantPast
    private var isFinished = false
    /// The newest state, waiting for the next redraw
    private var pending: (text: String, progress: Double?)?
    private var flush: Task<Void, Never>?

    static let updateSeconds: TimeInterval = 2

    /// A deployment lets its agent job update the card
    init(title: String, serverName: String, progressText: String, progress: Double? = nil,
         deployment: Deployment? = nil, jobID: String? = nil) {
        self.title = title
        if let deployment { LiveActivityJobs.shared.track(id, title: title, on: deployment, jobID: jobID) }
        OperationActivities.shared.start(id: id, title: title, serverName: serverName,
                                         progressText: progressText, progress: progress)
        let movedByAppOnly = deployment == nil
        grace = BackgroundGrace { [weak self] in
            if movedByAppOnly { self?.showPaused() }
        }
    }

    /// The card says the run waits for the app
    private func showPaused() {
        guard !isFinished else { return }
        flush?.cancel()
        flush = nil
        OperationActivities.shared.update(id: id, progressText: UIL10n.string("Paused. Open the app to continue."),
                                          progress: pending?.progress)
        IslandJournal.shared.note("paused: only the app moves this card", run: title)
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
        guard error != nil, LiveActivityJobs.shared.isServerLed(id) else { return end(text, error: error) }
        Task { await settleWithServer(text, error: error) }
    }

    /// Leaves a running job's card to the server
    private func settleWithServer(_ text: String, error: String?) async {
        await LiveActivityJobs.shared.settle(id, text: text, error: error)
        grace?.end()
    }

    private func end(_ text: String, error: String?) {
        OperationActivities.shared.end(id: id, progressText: text, errorMessage: error)
        LiveActivityJobs.shared.forget(id)
        grace?.end()
    }
}
