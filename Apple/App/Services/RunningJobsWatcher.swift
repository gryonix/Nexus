import AgentClient
import AgentControl
import Foundation
import ServerControl
import ServiceCatalog

@MainActor
final class RunningJobsWatcher {
    static let shared = RunningJobsWatcher()

    private var attached: Set<String> = []
    /// Whether the app is on screen and may connect
    var isAppActive = true
    /// Operations to follow again once the app is back
    private var waiting: [Waiting] = []

    private struct Waiting {
        let state: LongOperationState
        let kind: AgentJobKind
        let subject: String
        let deployment: Deployment
    }
    /// One sweep at a time
    private var sweeping = false

    private init() {}

    func sweep() async {
        guard !sweeping else { return }
        sweeping = true
        defer { sweeping = false }
        guard #available(macOS 15.0, *) else { return }
        await resumeWaiting()
        let fleet = (try? FileDeploymentStore().load()) ?? []
        for deployment in fleet where !DemoServer.isDemo(deployment) {
            if InstallSessionRegistry.shared.existingSession(for: deployment.id)?.isInstalling == true { continue }
            await adoptJobs(of: deployment)
            await adoptDetachedJobs(of: deployment)
        }
        OperationActivities.shared.endUnclaimed()
    }

    /// Opens the run a push named
    func follow(jobID: String) async {
        if RunningOperationsRegistry.shared.present(jobID: jobID) { return }
        await sweep()
        RunningOperationsRegistry.shared.present(jobID: jobID)
    }

    /// The machines whose detached-job journals are worth reading
    static func journalHosts(of deployment: Deployment) -> [SSHHostID] {
        deployment.workerHosts
    }

    @available(macOS 15.0, *)
    private func adoptJobs(of deployment: Deployment) async {
        guard let session = try? await AgentConnection.open(deployment: deployment, shared: true) else {
            return
        }
        let operations = AgentJobOperations(client: session.client)
        guard let jobs = try? await operations.jobs(runningOnly: true) else { return }
        for job in jobs where Self.isShownAlone(job) && !attached.contains(job.id)
            && !LiveActivityJobs.shared.isFollowing(job.id) {
            attach(job, of: deployment, using: operations)
        }
    }

    /// A service run inside a plan shows there
    static func isShownAlone(_ job: AgentJob) -> Bool {
        job.partOf.isEmpty
    }

    private func adoptDetachedJobs(of deployment: Deployment) async {
        guard let runner = try? await DashboardSessionFactory
            .makeRunnerDetached(deployment: deployment, shared: true) else { return }
        for host in Self.journalHosts(of: deployment) {
            guard let jobs = try? await DetachedJobs.list(
                on: host, runner: runner,
                timeout: deployment.timeouts.duration(for: .quick)) else { continue }
            for job in jobs where job.isRunning && !attached.contains(job.id) {
                attachDetached(job, of: deployment, on: host, runner: runner)
            }
        }
    }

    private func attachDetached(_ job: DetachedJobs.Job, of deployment: Deployment,
                                on host: SSHHostID, runner: any SSHCommandRunner) {
        attached.insert(job.id)
        let state = LongOperationState(title: Self.title(for: job, on: deployment),
                                       progressText: UIL10n.string("Reattaching…"))
        RunningOperationsRegistry.shared.adopt(state, serverName: deployment.name)
        Task { [weak self] in
            do {
                try await DetachedJobs.follow(jobID: job.id, from: 1, on: host, runner: runner,
                                              runTimeout: deployment.timeouts.duration(for: .long)) { line in
                    Task { @MainActor in
                        state.log += line
                        Self.show(line, in: state)
                    }
                }
                state.progressText = UIL10n.string("Done")
            } catch {
                state.errorMessage = AgentOutdated.describe(error)
            }
            state.isFinished = true
            self?.attached.remove(job.id)
        }
    }

    /// A stage headline, never a raw English line
    private static func show(_ line: String, in state: LongOperationState) {
        let readable = WrapperLogText.readable(line).trimmingCharacters(in: .whitespacesAndNewlines)
        if let headline = WrapperLogText.headline(readable) {
            state.progressText = headline
        } else if !readable.isEmpty, state.progressText == UIL10n.string("Reattaching…") {
            state.progressText = UIL10n.string("Running on the server…")
        }
    }

    static func title(for job: DetachedJobs.Job, on deployment: Deployment) -> String {
        let subject = displaySubject(job.subject)
        switch job.kind {
        case .update: return UIL10n.string("Updating %@", subject)
        case .backup: return UIL10n.string("Backing up %@", subject)
        case .restore: return UIL10n.string("Restoring %@", subject)
        case .uninstall: return UIL10n.string("Removing %@", subject)
        case .control: return UIL10n.string("Working on %@", subject)
        }
    }

    @available(macOS 15.0, *)
    func resume(_ state: LongOperationState, kind: AgentJobKind, subject: String,
                of deployment: Deployment) async -> Bool {
        guard let session = try? await AgentConnection.open(deployment: deployment, shared: true) else {
            return false
        }
        let operations = AgentJobOperations(client: session.client)
        guard let job = try? await operations.jobs()
            .filter({ $0.kind == kind && $0.subject == subject })
            .max(by: { $0.started < $1.started }) else { return false }
        if attached.contains(job.id) {
            RunningOperationsRegistry.shared.discard(state.id)
            return true
        }
        attached.insert(job.id)
        state.errorMessage = nil
        state.progressText = UIL10n.string("Connected again. The server kept working.")
        follow(job, state: state, using: operations, of: deployment)
        return true
    }

    /// Keeps the run open until the app is back
    func resumeWhenBack(_ state: LongOperationState, kind: AgentJobKind, subject: String,
                        of deployment: Deployment) {
        state.errorMessage = nil
        state.progressText = UIL10n.string("The server keeps working. Open the app to follow it.")
        waiting.append(Waiting(state: state, kind: kind, subject: subject, deployment: deployment))
    }

    @available(macOS 15.0, *)
    private func resumeWaiting() async {
        let due = waiting
        waiting = []
        for item in due where !item.state.isFinished {
            guard await resume(item.state, kind: item.kind, subject: item.subject, of: item.deployment) else {
                item.state.errorMessage = UIL10n.string("The connection to the server was lost.")
                item.state.isFinished = true
                continue
            }
        }
    }

    private func attach(_ job: AgentJob, of deployment: Deployment,
                        using operations: AgentJobOperations) {
        attached.insert(job.id)
        let state = LongOperationState(title: Self.title(for: job, on: deployment),
                                       progressText: UIL10n.string("Reattaching…"))
        if job.kind == .install && job.planPurpose == .setup {
            state.reattachDeployment = deployment
        }
        RunningOperationsRegistry.shared.adopt(state, serverName: deployment.name,
                                               deployment: deployment, jobID: job.id)
        follow(job, state: state, using: operations, of: deployment)
    }

    private func follow(_ job: AgentJob, state: LongOperationState, using operations: AgentJobOperations,
                        of deployment: Deployment) {
        Task { [weak self] in
            do {
                try await operations.watch(jobID: job.id, from: 0, onChunk: { line in
                    Task { @MainActor in
                        state.log += line
                        Self.show(line, in: state)
                    }
                })
                state.progressText = UIL10n.string("Done")
            } catch {
                if let self, !self.isAppActive {
                    self.attached.remove(job.id)
                    self.resumeWhenBack(state, kind: job.kind, subject: job.subject, of: deployment)
                    return
                }
                if let resolved = try? await operations.jobs().first(where: { $0.id == job.id }) {
                    switch resolved.outcome {
                    case .succeeded:
                        state.progressText = UIL10n.string("Done")
                    case .cancelled:
                        state.progressText = UIL10n.string("Cancelled")
                    case .failed, .abandoned:
                        state.errorMessage = resolved.failure.isEmpty ? AgentOutdated.describe(error) : resolved.failure
                    case .running, .unknown:
                        state.errorMessage = AgentOutdated.describe(error)
                    }
                } else {
                    state.errorMessage = AgentOutdated.describe(error)
                }
            }
            state.isFinished = true
            self?.attached.remove(job.id)
        }
    }

    /// What the strip calls this run
    static func title(for job: AgentJob, on deployment: Deployment) -> String {
        let subject = displaySubject(job.subject)
        switch job.kind {
        case .install: return UIL10n.string("Installing %@", subject)
        case .repair: return UIL10n.string("Repairing %@", deployment.name)
        case .reinstall: return UIL10n.string("Reinstalling %@", deployment.name)
        case .update: return UIL10n.string("Updating %@", subject)
        case .backup, .containerBackup: return UIL10n.string("Backing up %@", subject)
        case .restore: return UIL10n.string("Restoring %@", subject)
        case .uninstall, .containerRemoval: return UIL10n.string("Removing %@", subject)
        case .containerUpdate: return UIL10n.string("Updating %@", subject)
        case .serviceControl, .containerControl: return UIL10n.string("Working on %@", subject)
        case .modelPull: return UIL10n.string("Fetching %@", subject)
        case .securityControl: return UIL10n.string("Protection on %@", deployment.name)
        case .agentUpdate: return UIL10n.string("Updating the agent")
        case .move: return UIL10n.string("Moving %@", subject)
        case .unknown:
            return UIL10n.string("Working on %@", deployment.name)
        }
    }

    /// Service names for a subject; a plan names several
    static func displaySubject(_ subject: String) -> String {
        let parts = subject.components(separatedBy: " +")
        let names = parts[0].components(separatedBy: ", ").map(displayName).joined(separator: ", ")
        return parts.count == 2 ? "\(names) +\(parts[1])" : names
    }

    private static func displayName(_ id: String) -> String {
        guard let service = AgentServiceMapping.serviceIDs(forAgentIDs: [id]).first,
              let managed = ServiceRegistry.service(service) else { return id }
        return managed.displayName
    }
}
