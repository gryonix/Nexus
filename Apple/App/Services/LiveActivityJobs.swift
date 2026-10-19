import AgentClient
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

    func forget(_ operation: UUID) {
        runs[operation] = nil
    }

    /// Pairs the job with its server's newest waiting run
    func jobStarted(_ jobID: String, on deploymentID: UUID) {
        guard !runs.values.contains(where: { $0.jobID == jobID }) else { return }
        let waiting = runs.filter { $0.value.deployment.id == deploymentID && $0.value.jobID == nil
            && Date().timeIntervalSince($0.value.startedAt) < Self.pairingWindow }
        guard let newest = waiting.max(by: { $0.value.startedAt < $1.value.startedAt })?.key else { return }
        runs[newest]?.jobID = jobID
        #if os(iOS)
        OperationActivities.shared.adoptRemoteCard(of: jobID, for: newest)
        #endif
        handOver(newest)
    }

    func tokenArrived(_ token: String, for operation: UUID) {
        guard runs[operation] != nil else { return }
        runs[operation]?.token = token
        runs[operation]?.handedOver = false
        handOver(operation)
    }

    private func handOver(_ operation: UUID) {
        guard let run = runs[operation], !run.handedOver,
              let jobID = run.jobID, let token = run.token else { return }
        runs[operation]?.handedOver = true
        OperationActivities.shared.remember(operation, followsJob: jobID)
        Task {
            guard #available(macOS 15.0, *),
                  let session = try? await AgentConnection.open(deployment: run.deployment, shared: true)
            else { return }
            _ = try? await session.client.watchLiveActivity(jobID: jobID, token: token, title: run.title)
        }
    }
}
