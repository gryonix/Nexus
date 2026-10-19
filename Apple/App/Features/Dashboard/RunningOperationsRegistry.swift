import Combine
import ServerControl
import SwiftUI

@MainActor
final class RunningOperationsRegistry: ObservableObject {
    static let shared = RunningOperationsRegistry()

    struct Entry: Identifiable {
        let state: LongOperationState
        let downloadBackup: ((String) async throws -> Data)?
        var jobID: String?
        var deployment: Deployment?
        var id: UUID { state.id }
    }

    @Published private(set) var entries: [Entry] = []
    @Published var presented: LongOperationState?

    private init() {}

    func start(_ state: LongOperationState,
               serverName: String = "",
               deployment: Deployment? = nil,
               opensSheet: Bool = true,
               downloadBackup: ((String) async throws -> Data)? = nil) {
        if let deployment {
            LiveActivityJobs.shared.track(state.id, title: state.title, on: deployment)
            RunningJobsWatcher.shared.settleWhenServerEnds(state, on: deployment)
        }
        entries.append(Entry(state: state, downloadBackup: downloadBackup, deployment: deployment))
        if opensSheet { presented = state }
        putOnLockScreen(state, serverName: serverName, deploymentID: deployment?.id,
                        canStop: deployment?.usesAgent == true)
    }

    func adopt(_ state: LongOperationState, serverName: String = "",
               deployment: Deployment? = nil, jobID: String? = nil) {
        guard !entries.contains(where: { $0.id == state.id }) else { return }
        if let deployment {
            LiveActivityJobs.shared.track(state.id, title: state.title, on: deployment, jobID: jobID)
        }
        entries.append(Entry(state: state, downloadBackup: nil, jobID: jobID, deployment: deployment))
        putOnLockScreen(state, serverName: serverName, jobID: jobID, deploymentID: deployment?.id,
                        canStop: deployment?.usesAgent == true)
    }

    /// Opens the sheet of a server run by job id
    @discardableResult
    func present(jobID: String) -> Bool {
        guard let entry = entries.first(where: { $0.jobID == jobID }) else { return false }
        presented = entry.state
        return true
    }

    /// Reopens an operation's sheet from the banner
    func present(_ state: LongOperationState) { presented = state }

    /// Runs a failed operation again from its card
    func retry(cardOf id: UUID) {
        let current = OperationActivities.shared.operation(showingCardOf: id) ?? id
        guard let state = entries.first(where: { $0.id == current })?.state,
              let retry = state.retry else { return }
        OperationActivities.shared.dismissCard(of: id)
        discard(state.id)
        retry()
    }

    @discardableResult
    func present(cardOf id: UUID) -> Bool {
        let current = OperationActivities.shared.operation(showingCardOf: id) ?? id
        guard let state = entries.first(where: { $0.id == current })?.state else { return false }
        presented = state
        return true
    }

    nonisolated static let doneLingerSeconds: Double = 5

    func dismiss(_ id: UUID) {
        guard let entry = entries.first(where: { $0.id == id }), entry.state.isFinished,
              presented?.id != id else { return }
        entries.removeAll { $0.id == id }
        takeOffLockScreen(id)
    }

    /// Drops a row another one already shows
    func discard(_ id: UUID) {
        entries.removeAll { $0.id == id }
        if presented?.id == id { presented = nil }
        takeOffLockScreen(id)
    }

    func scheduleDismissal(of id: UUID, after seconds: Double = doneLingerSeconds) {
        guard let entry = entries.first(where: { $0.id == id }), entry.state.isFinished,
              !dismissing.contains(id) else { return }
        dismissing.insert(id)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self else { return }
            self.dismissing.remove(id)
            guard entry.state.errorMessage == nil, entry.state.notice == nil, entry.state.dnsUpdate == nil else { return }
            self.dismiss(id)
        }
    }

    /// Operations with a countdown already running
    private var dismissing: Set<UUID> = []

    /// Shows a question unless another window is up
    func bringUp(_ state: LongOperationState) {
        guard presented == nil, entries.contains(where: { $0.id == state.id }) else { return }
        presented = state
    }

    func dismissPresented() {
        if let presented,
           let entry = entries.first(where: { $0.id == presented.id }),
           entry.state.isFinished {
            entries.removeAll { $0.id == presented.id }
        }
        presented = nil
    }

    func downloadBackup(for state: LongOperationState) -> ((String) async throws -> Data)? {
        entries.first { $0.id == state.id }?.downloadBackup
    }

    // MARK: - The lock screen

    private var lockScreenWatchers: [UUID: Set<AnyCancellable>] = [:]
    /// Extra background time for each running operation
    private var graces: [UUID: BackgroundGrace] = [:]

    private static let lockScreenUpdateSeconds: Double = 2

    private func putOnLockScreen(_ state: LongOperationState, serverName: String, jobID: String? = nil,
                                 deploymentID: UUID? = nil, canStop: Bool = false) {
        guard !state.isFinished else { return }
        PendingAgentInstalls.shared.yieldLockScreen(matching: state.title)
        graces[state.id] = BackgroundGrace()
        OperationActivities.shared.start(id: state.id,
                                         title: state.title,
                                         serverName: serverName,
                                         progressText: state.progressText,
                                         progress: state.progress,
                                         jobID: jobID,
                                         deploymentID: deploymentID,
                                         canStop: canStop)

        var watchers: Set<AnyCancellable> = []
        Publishers.CombineLatest(state.$progressText, state.$progress)
            .dropFirst()
            .throttle(for: .seconds(Self.lockScreenUpdateSeconds),
                      scheduler: DispatchQueue.main, latest: true)
            .sink { text, progress in
                OperationActivities.shared.update(id: state.id, progressText: text,
                                                  progress: progress)
            }
            .store(in: &watchers)

        Publishers.CombineLatest(state.$isFinished, state.$errorMessage)
            .dropFirst()
            .filter { $0 || $1 != nil }
            .first()
            .sink { [weak self] _, error in
                OperationActivities.shared.end(id: state.id,
                                               progressText: state.progressText,
                                               errorMessage: error,
                                               canRetry: state.retry != nil)
                self?.lockScreenWatchers[state.id] = nil
                self?.graces.removeValue(forKey: state.id)?.end()
                LiveActivityJobs.shared.forget(state.id)
            }
            .store(in: &watchers)

        lockScreenWatchers[state.id] = watchers
    }

    private func takeOffLockScreen(_ id: UUID) {
        graces.removeValue(forKey: id)?.end()
        guard lockScreenWatchers.removeValue(forKey: id) != nil else { return }
        OperationActivities.shared.end(id: id, progressText: "", errorMessage: nil)
    }
}
