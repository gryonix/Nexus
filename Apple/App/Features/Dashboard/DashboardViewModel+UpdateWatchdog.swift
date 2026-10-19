import AgentControl
import Foundation
import ServerControl
import ServiceCatalog

extension DashboardViewModel {
    typealias UpdateOutcome = ServiceUpdateRunRecord.Outcome

    /// The agent's ending, when the stream itself went silent
    func updateEndedOnServer(_ service: any ManagedService, since start: Date,
                             streamed: Task<ServiceUpdateRunRecord, Error>) async -> UpdateOutcome? {
        guard #available(macOS 15.0, *), deployment.usesAgent,
              let subject = AgentServiceMapping.agentID(for: service.id),
              let job = await RunningJobsWatcher.shared.endedJob(kind: .update, subject: subject,
                                                                 startedAfter: start, of: deployment)
        else { return nil }
        try? await Task.sleep(for: .seconds(5))
        switch job.outcome {
        case .succeeded: return .updated
        case .cancelled: return .failed(reason: UIL10n.string("Cancelled"))
        case .failed, .abandoned, .running, .unknown:
            return .failed(reason: job.failure.isEmpty ? UIL10n.string("The update failed.") : job.failure)
        }
    }

    /// Whichever ends first: the stream or the server's own record
    static func updateResult(of streamed: Task<ServiceUpdateRunRecord, Error>,
                             watchdog: Task<UpdateOutcome?, Never>) async throws -> UpdateOutcome? {
        let once = ResumeOnce()
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    let record = try await streamed.value
                    if once.claim() { continuation.resume(returning: record.outcome) }
                } catch {
                    if once.claim() { continuation.resume(throwing: error) }
                }
            }
            Task { @MainActor in
                guard let outcome = await watchdog.value, once.claim() else { return }
                streamed.cancel()
                continuation.resume(returning: outcome)
            }
        }
    }

    static func show(_ outcome: UpdateOutcome, in operation: LongOperationState) {
        switch outcome {
        case .updated:
            operation.progressText = UIL10n.string("Update finished.")
        case .rolledBack(let reason):
            operation.progressText = UIL10n.string("The update was rolled back: %@", reason)
        case .failed(let reason):
            operation.errorMessage = reason
        }
    }
}

/// Lets only the first of two racers resume a continuation
@MainActor
final class ResumeOnce {
    private var claimed = false

    func claim() -> Bool {
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
