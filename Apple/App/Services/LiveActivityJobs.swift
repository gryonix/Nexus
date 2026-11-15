import AgentClient
import AgentControl
import Foundation
import ServerControl

/// Ties each island to its agent job for background updates
@MainActor
final class LiveActivityJobs {
    static let shared = LiveActivityJobs()

    private struct Run {
        let deployment: Deployment
        let title: String
        let startedAt: Date
        var jobID: String?
        var token: String?
        var handedOver = false
        /// The agent confirmed it moves the card
        var serverLed = false
        /// The run shows the card the server opened
        var onServerCard = false
    }

    private var runs: [UUID: Run] = [:]
    /// Later jobs belong to some other operation
    private static let pairingWindow: TimeInterval = 120

    private init() {}

    func track(_ operation: UUID, title: String, on deployment: Deployment, jobID: String? = nil) {
        guard deployment.usesAgent else { return }
        runs[operation] = Run(deployment: deployment, title: title, startedAt: Date(), jobID: jobID)
    }

    /// The job paired with an operation, if any
    func jobID(of operation: UUID) -> String? {
        runs[operation]?.jobID
    }

    /// The open run that follows this job, if any
    func operation(following jobID: String) -> UUID? {
        runs.first { $0.value.jobID == jobID }?.key
    }

    /// Whether an open operation already follows this job
    func isFollowing(_ jobID: String) -> Bool {
        runs.values.contains { $0.jobID == jobID }
    }

    /// When the server last moved each card itself
    private var heardFromServer: [UUID: Date] = [:]
    /// Longer server silence hands the card back to the app
    nonisolated static let serverQuietLimit: TimeInterval = 45

    func serverMoved(_ operation: UUID, at time: Date = Date()) {
        if heardFromServer[operation] == nil {
            IslandJournal.shared.note("the server's updates reach the card", run: runs[operation]?.title ?? "")
        }
        heardFromServer[operation] = time
    }

    /// Whether the server leads and moves the card
    func serverIsMoving(_ operation: UUID, now: Date = Date()) -> Bool {
        Self.isMoving(led: isServerLed(operation), heard: heardFromServer[operation], now: now)
    }

    nonisolated static func isMoving(led: Bool, heard: Date?, now: Date) -> Bool {
        guard led, let heard else { return false }
        return now.timeIntervalSince(heard) < serverQuietLimit
    }

    func forget(_ operation: UUID) {
        runs[operation] = nil
        heardFromServer[operation] = nil
    }

    /// Whether the agent, not the app, now moves this card
    func isServerLed(_ operation: UUID) -> Bool {
        runs[operation]?.serverLed == true
    }

    /// The server's own record of this run's job
    func serverJob(of operation: UUID) async -> AgentJob? {
        guard #available(macOS 15.0, *), let run = runs[operation], let jobID = run.jobID else { return nil }
        return await RunningJobsWatcher.job(jobID, of: run.deployment)
    }

    /// Pairs the job with its server's newest waiting run
    func jobStarted(_ jobID: String, on deploymentID: UUID) {
        guard !runs.values.contains(where: { $0.jobID == jobID }) else { return }
        let waiting = runs.filter { $0.value.deployment.id == deploymentID && $0.value.jobID == nil
            && Date().timeIntervalSince($0.value.startedAt) < Self.pairingWindow }
        guard let newest = waiting.max(by: { $0.value.startedAt < $1.value.startedAt })?.key else {
            IslandJournal.shared.note("job \(IslandJournal.short(jobID)) started; no card waits for it")
            return
        }
        runs[newest]?.jobID = jobID
        IslandJournal.shared.note("job \(IslandJournal.short(jobID)) belongs to this card", run: runs[newest]?.title ?? "")
        #if os(iOS)
        if !OperationActivities.shared.hasOwnCard(newest) {
            OperationActivities.shared.adoptRemoteCard(of: jobID, for: newest)
        }
        guard LiveActivitySettings.shared.hiddenOperationKinds.isEmpty else {
            Task { await handOverUnlessHidden(newest) }
            return
        }
        #endif
        handOver(newest)
    }

    #if os(iOS) || os(tvOS)
    /// Drops the card of a kind switched off in Settings
    private func handOverUnlessHidden(_ operation: UUID) async {
        if let job = await serverJob(of: operation), !LiveActivitySettings.shared.shows(Self.kind(of: job.kind)) {
            runs[operation]?.handedOver = true
            IslandJournal.shared.note("not shown: switched off in the app's settings", run: runs[operation]?.title ?? "")
            OperationActivities.shared.dismissCard(of: operation)
            return
        }
        handOver(operation)
    }
    #endif

    /// A job's card kind, named as the agent names it
    nonisolated static func kind(of job: AgentJobKind) -> OperationKind {
        switch job {
        case .install, .repair, .reinstall: return .install
        case .update, .containerUpdate, .agentUpdate: return .update
        case .backup, .containerBackup: return .backup
        case .restore: return .restore
        case .move: return .move
        case .uninstall, .containerRemoval: return .removal
        case .serviceControl, .containerControl, .modelPull, .securityControl, .unknown: return .other
        }
    }

    /// The server moves the card it opened for this job
    func serverMoves(_ operation: UUID) {
        heardFromServer[operation] = Date()
        runs[operation]?.serverLed = true
        runs[operation]?.handedOver = true
        runs[operation]?.onServerCard = true
    }

    /// Ends a card the server leads, as its job ended
    func settle(_ operation: UUID, text: String, error: String?, canRetry: Bool = false) async {
        defer { forget(operation) }
        guard let job = await serverJob(of: operation), !job.isRunning else {
            OperationActivities.shared.leaveToServer(operation)
            return
        }
        switch job.outcome {
        case .succeeded:
            OperationActivities.shared.end(id: operation, progressText: text.isEmpty ? UIL10n.string("Done") : text,
                                           errorMessage: nil)
        case .cancelled:
            OperationActivities.shared.end(id: operation, progressText: UIL10n.string("Cancelled"), errorMessage: nil)
        default:
            OperationActivities.shared.end(id: operation, progressText: text,
                                           errorMessage: job.failure.isEmpty ? error : job.failure, canRetry: canRetry)
        }
    }

    func tokenArrived(_ token: String, for operation: UUID) {
        guard let run = runs[operation], !run.onServerCard else { return }
        runs[operation]?.token = token
        runs[operation]?.handedOver = false
        handOver(operation)
    }

    private func handOver(_ operation: UUID) {
        guard let run = runs[operation], !run.handedOver,
              let jobID = run.jobID, let token = run.token else { return }
        runs[operation]?.handedOver = true
        OperationActivities.shared.remember(operation, followsJob: jobID)
        Task { await ask(run.deployment, toMove: jobID, with: token, title: run.title, for: operation) }
    }

    /// Pauses before asking the agent again
    static let handOverPauses: [Duration] = [.zero, .seconds(5), .seconds(15)]

    /// The agent moves the card; refusals go to the log
    private func ask(_ deployment: Deployment, toMove jobID: String, with token: String,
                     title: String, for operation: UUID) async {
        guard #available(macOS 15.0, *) else { return }
        var reason = UIL10n.string("the server did not answer")
        for pause in Self.handOverPauses {
            try? await Task.sleep(for: pause)
            do {
                let session = try await AgentConnection.open(deployment: deployment, shared: true)
                let answer = try await session.client.watchLiveActivity(jobID: jobID, token: token, title: title)
                if answer.ok {
                    runs[operation]?.serverLed = true
                    IslandJournal.shared.note("the server moves the card from now on", run: title)
                    return
                }
                reason = answer.message
                break
            } catch {
                reason = DashboardViewModel.message(for: error)
            }
        }
        runs[operation]?.handedOver = false
        IslandJournal.shared.note("the server did not take the card: \(reason)", run: title)
        RunningOperationsRegistry.shared.note(
            UIL10n.string("The Dynamic Island follows this only while the app is open: %@", reason), on: operation)
    }
}
