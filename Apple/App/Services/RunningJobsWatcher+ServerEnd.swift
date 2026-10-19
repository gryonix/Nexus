import AgentClient
import AgentControl
import Foundation
import ServerControl

extension RunningJobsWatcher {
    /// Returns once the app is on screen again
    func untilActive() async {
        while !isAppActive {
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Closes a run once its server job has ended
    func settleWhenServerEnds(_ state: LongOperationState, on deployment: Deployment,
                              every interval: Duration = .seconds(20)) {
        guard #available(macOS 15.0, *), deployment.usesAgent else { return }
        Task { @MainActor in
            var endSeen = false
            while !state.isFinished {
                try? await Task.sleep(for: interval)
                guard isAppActive, !state.isFinished,
                      let jobID = LiveActivityJobs.shared.jobID(of: state.id),
                      let job = await Self.job(jobID, of: deployment) else { continue }
                if job.isRunning || !endSeen {
                    endSeen = !job.isRunning
                    continue
                }
                Self.settle(state, with: job)
            }
        }
    }

    /// Writes the server's own outcome into the run
    static func settle(_ state: LongOperationState, with job: AgentJob) {
        guard !state.isFinished else { return }
        switch job.outcome {
        case .succeeded:
            state.settle(progressText: UIL10n.string("Done"), errorMessage: nil)
        case .cancelled:
            state.settle(progressText: UIL10n.string("Cancelled"), errorMessage: nil)
        case .failed, .abandoned, .running, .unknown:
            state.settle(progressText: state.progressText,
                         errorMessage: job.failure.isEmpty ? UIL10n.string("Failed") : job.failure)
        }
    }

    @available(macOS 15.0, *)
    private static func job(_ jobID: String, of deployment: Deployment) async -> AgentJob? {
        await withTaskGroup(of: AgentJob?.self) { group in
            group.addTask {
                guard let session = try? await AgentConnection.open(deployment: deployment, shared: true) else {
                    return nil
                }
                return try? await AgentJobOperations(client: session.client).jobs().first { $0.id == jobID }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(15))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
