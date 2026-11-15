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
        guard #available(macOS 15.0, *) else { return }
        do {
            try await cancel(job, on: try deployment(of: server))
        } catch {
            StopRefusal.report(error, title: StopRefusal.jobTitle(job), card: .job(job))
        }
    }

    /// The saved server behind a relay id
    private func deployment(of server: String) throws -> Deployment {
        guard let id = RelayServers.deploymentID(of: server),
              let deployment = ((try? FileDeploymentStore().load()) ?? []).first(where: { $0.id == id })
        else { throw StopMiss.serverGone }
        return deployment
    }

    /// Cancels the job on the machine that runs it
    @available(macOS 15.0, *)
    private func cancel(_ job: String, on deployment: Deployment) async throws {
        let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: deployment, shared: false)
        defer { Task { await runner.disconnect() } }
        var lastError: Error?
        for host in deployment.agentHosts {
            do {
                let client = try await AgentConnection.client(deployment: deployment, runner: runner, host: host)
                let operations = AgentJobOperations(client: client)
                guard try await operations.jobs(runningOnly: true).contains(where: { $0.id == job }) else { continue }
                try await operations.cancel(jobID: job)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? StopMiss.nothingRunning
    }

    private func stop(_ id: UUID) async {
        if let install = InstallSessionRegistry.shared.existingSession(for: id), install.isInstalling {
            install.cancel()
            return
        }
        guard #available(macOS 15.0, *) else { return }
        let target = target(of: id)
        do {
            guard let target else { throw StopMiss.serverGone }
            guard target.deployment.usesAgent else { throw StopMiss.nothingRunning }
            try await cancelRuns(of: target)
        } catch {
            StopRefusal.report(error, title: target?.title ?? "", card: .operation(id))
        }
    }

    /// Cancels every run the operation started; throws the last refusal
    @available(macOS 15.0, *)
    private func cancelRuns(of target: StopTarget) async throws {
        let session = try await AgentConnection.open(deployment: target.deployment)
        defer { Task { await session.runner.disconnect() } }
        let operations = AgentJobOperations(client: session.client)
        let running = try await operations.jobs(runningOnly: true)
        let started = target.startedAt.addingTimeInterval(-5)
        let targets = running.filter { job in
            target.jobID.map { $0 == job.id } ?? (job.started >= started)
        }
        guard !targets.isEmpty else { throw StopMiss.nothingRunning }
        var lastError: Error?
        for job in targets {
            do { try await operations.cancel(jobID: job.id) } catch { lastError = error }
        }
        if let lastError { throw lastError }
    }

    private struct StopTarget {
        let deployment: Deployment
        let jobID: String?
        let startedAt: Date
        let title: String
    }

    /// Which server and job the stop applies to
    private func target(of id: UUID) -> StopTarget? {
        let entry = RunningOperationsRegistry.shared.entries.first { $0.id == id }
        if let entry, let deployment = entry.deployment {
            return StopTarget(deployment: deployment, jobID: entry.jobID,
                              startedAt: entry.state.startedAt, title: entry.state.title)
        }
        guard let card = OperationActivities.shared.stopTarget(of: id), let deploymentID = card.deploymentID,
              let deployment = ((try? FileDeploymentStore().load()) ?? []).first(where: { $0.id == deploymentID })
        else { return nil }
        return StopTarget(deployment: deployment, jobID: card.jobID, startedAt: card.startedAt, title: card.title)
    }
}
