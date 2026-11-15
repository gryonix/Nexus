import AgentClient
import AgentControl
import Foundation
import ServerControl

extension RunningJobsWatcher {
    /// Opens a listed install's window; false if none
    @discardableResult
    func open(pending row: PendingAgentInstalls.Pending) async -> Bool {
        let store = InstallJobStore()
        guard let jobID = store.job(deployment: row.deploymentID, service: row.serviceID)?.jobID,
              !jobID.isEmpty else { return false }
        if RunningOperationsRegistry.shared.present(jobID: jobID) { return true }
        guard #available(macOS 15.0, *),
              let deployment = (try? FileDeploymentStore().load())?.first(where: { $0.id == row.deploymentID }),
              let session = try? await AgentConnection.open(deployment: deployment, shared: true) else { return false }
        let operations = AgentJobOperations(client: session.client)
        guard let job = try? await operations.jobs().first(where: { $0.id == jobID }) else {
            store.forget(deployment: row.deploymentID, service: row.serviceID)
            PendingAgentInstalls.shared.refresh()
            return false
        }
        attach(job, of: deployment, using: operations)
        if !job.isRunning {
            store.forget(deployment: row.deploymentID, service: row.serviceID)
            PendingAgentInstalls.shared.refresh()
        }
        return RunningOperationsRegistry.shared.present(jobID: jobID)
    }

    /// Opens the run a tapped alert names; false if gone
    @discardableResult
    func open(jobID: String, on deploymentID: UUID?) async -> Bool {
        if RunningOperationsRegistry.shared.present(jobID: jobID) { return true }
        await sweep()
        if RunningOperationsRegistry.shared.present(jobID: jobID) { return true }
        guard #available(macOS 15.0, *), let deploymentID,
              let deployment = (try? FileDeploymentStore().load())?.first(where: { $0.id == deploymentID }),
              let session = try? await AgentConnection.open(deployment: deployment, shared: true) else { return false }
        let operations = AgentJobOperations(client: session.client)
        guard let listed = try? await operations.jobs(), let job = Self.job(named: jobID, among: listed) else { return false }
        attach(job, of: deployment, using: operations)
        return RunningOperationsRegistry.shared.present(jobID: jobID)
    }

    /// The listed run with this id, running or ended
    static func job(named jobID: String, among jobs: [AgentJob]) -> AgentJob? {
        jobs.first { $0.id == jobID }
    }
}
