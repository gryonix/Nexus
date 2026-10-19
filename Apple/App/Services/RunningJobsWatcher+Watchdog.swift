import AgentControl
import Foundation
import ServerControl

extension RunningJobsWatcher {
    @available(macOS 15.0, *)
    func endedJob(kind: AgentJobKind, subject: String, startedAfter start: Date,
                  of deployment: Deployment, every interval: Duration = .seconds(20)) async -> AgentJob? {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard isAppActive, !Task.isCancelled else { continue }
            if let job = await Self.latestJob(kind: kind, subject: subject, after: start, of: deployment),
               !job.isRunning {
                return job
            }
        }
        return nil
    }

    @available(macOS 15.0, *)
    private static func latestJob(kind: AgentJobKind, subject: String, after start: Date,
                                  of deployment: Deployment) async -> AgentJob? {
        await withTaskGroup(of: AgentJob?.self) { group in
            group.addTask {
                guard let session = try? await AgentConnection.open(deployment: deployment) else { return nil }
                let jobs = try? await AgentJobOperations(client: session.client).jobs()
                return jobs?
                    .filter { $0.kind == kind && $0.subject == subject && $0.started >= start.addingTimeInterval(-5) }
                    .max { $0.started < $1.started }
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
