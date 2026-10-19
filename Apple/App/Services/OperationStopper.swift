import AgentControl
import Foundation
import ServerControl

@MainActor
final class OperationStopper {
    static let shared = OperationStopper()

    /// How long the question waits for the second tap
    static let armedSeconds: Double = 5

    func tapped(_ id: UUID) async {
        let activities = OperationActivities.shared
        guard activities.isStopArmed(id) else {
            activities.setStopArmed(true, id: id)
            try? await Task.sleep(for: .seconds(Self.armedSeconds))
            if activities.isStopArmed(id) { activities.setStopArmed(false, id: id) }
            return
        }
        activities.setStopArmed(false, id: id)
        activities.showStopping(id)
        await stop(id)
    }

    /// The stop button of a card a server started
    func tappedJob(_ job: String, server: String) async {
        #if os(iOS)
        let activities = OperationActivities.shared
        guard activities.jobCard(job)?.content.state.stopArmed == true else {
            activities.setJobStopArmed(true, job: job)
            try? await Task.sleep(for: .seconds(Self.armedSeconds))
            if activities.jobCard(job)?.content.state.stopArmed == true { activities.setJobStopArmed(false, job: job) }
            return
        }
        activities.showStopping(job: job)
        #endif
        guard #available(macOS 15.0, *), let deploymentID = RelayServers.deploymentID(of: server),
              let deployment = ((try? FileDeploymentStore().load()) ?? []).first(where: { $0.id == deploymentID })
        else { return }
        await cancel(job, on: deployment)
    }

    /// Cancels the job on the machine that runs it
    @available(macOS 15.0, *)
    private func cancel(_ job: String, on deployment: Deployment) async {
        guard let runner = try? DashboardSessionFactory.makeRunner(deployment: deployment) else { return }
        defer { Task { await runner.disconnect() } }
        for host in deployment.agentHosts {
            guard let client = try? await AgentConnection.client(deployment: deployment, runner: runner, host: host)
            else { continue }
            let operations = AgentJobOperations(client: client)
            guard ((try? await operations.jobs(runningOnly: true)) ?? []).contains(where: { $0.id == job }) else { continue }
            _ = try? await operations.cancel(jobID: job)
            return
        }
    }

    private func stop(_ id: UUID) async {
        if let install = InstallSessionRegistry.shared.existingSession(for: id), install.isInstalling {
            install.cancel()
            return
        }
        guard #available(macOS 15.0, *), let target = target(of: id), target.deployment.usesAgent,
              let session = try? await AgentConnection.open(deployment: target.deployment) else { return }
        let operations = AgentJobOperations(client: session.client)
        let running = (try? await operations.jobs(runningOnly: true)) ?? []
        let started = target.startedAt.addingTimeInterval(-5)
        let targets = running.filter { job in
            target.jobID.map { $0 == job.id } ?? (job.started >= started)
        }
        for job in targets {
            _ = try? await operations.cancel(jobID: job.id)
        }
    }

    /// Which server and job the stop applies to
    private func target(of id: UUID) -> (deployment: Deployment, jobID: String?, startedAt: Date)? {
        let entry = RunningOperationsRegistry.shared.entries.first { $0.id == id }
        if let entry, let deployment = entry.deployment {
            return (deployment, entry.jobID, entry.state.startedAt)
        }
        guard let card = OperationActivities.shared.stopTarget(of: id), let deploymentID = card.deploymentID,
              let deployment = ((try? FileDeploymentStore().load()) ?? []).first(where: { $0.id == deploymentID })
        else { return nil }
        return (deployment, card.jobID, card.startedAt)
    }
}
