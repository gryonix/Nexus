import AgentClient
import Foundation
import ServerControl
import ServiceCatalog

/// Disk health as control user; repairs as root
@MainActor
final class StorageViewModel: ObservableObject {
    let deployment: Deployment
    let host: SSHHostID

    @Published private(set) var hardware: ServerHardware?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var username: String
    @Published var secret = SSHSecretDraft()
    @Published private(set) var runningStep: String?
    @Published private(set) var stepFailure: String?
    /// Repairs over the server's own account, not a root sign-in
    @Published var usesServerAccount: Bool
    private var island: IslandRun?

    init(deployment: Deployment, host: SSHHostID) {
        self.deployment = deployment
        self.host = host
        let installUser = InstallAddressStore.installUser(deploymentID: deployment.id, host: host)
        username = installUser ?? "root"
        usesServerAccount = installUser == nil || deployment.usesAgent
    }

    /// The server's own sign-in account
    var serverAccount: String { endpoint?.user ?? deployment.entry.user }

    var arrays: [StorageArray] { hardware.map(StorageArray.all(in:)) ?? [] }

    private var endpoint: HostEndpoint? {
        deployment.nodes.first { $0.sshHost == host }?.endpoint
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        #if DEBUG
        if DemoFleet.covers(deployment) {
            hardware = ServerHardware.parse(DemoHardware.degradedProbe)
            return
        }
        #endif
        do {
            let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: deployment)
            let result = try await runner.run(ServerHardware.probeCommand, on: host, timeout: .seconds(20))
            hardware = ServerHardware.parse(result.stdout)
            errorMessage = hardware == nil ? UIL10n.string("The server did not answer the disk check.") : nil
        } catch {
            errorMessage = AgentOutdated.describe(error)
        }
    }

    /// Re-reads the disks while a job, rebuild or check runs
    func follow() async {
        while !Task.isCancelled, isBusy {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { break }
            await load()
            island?.update(busyLine.text, progress: busyLine.progress)
        }
        finishIsland()
    }

    /// What the array is doing now, for the island
    private var busyLine: (text: String, progress: Double?) {
        for array in arrays {
            switch array.state {
            case .rebuilding(let percent):
                return (UIL10n.string("Rebuilding %@", array.name), percent / 100)
            case .checking(let percent):
                return (UIL10n.string("Checking %@", array.name), percent / 100)
            default: continue
            }
        }
        return (runningStep ?? UIL10n.string("Working on the disks…"), nil)
    }

    private func finishIsland() {
        guard let island else { return }
        if isBusy {
            island.finish(UIL10n.string("Continues on the server."))
        } else {
            island.finish(stepFailure == nil ? UIL10n.string("The disks are ready.") : "", error: stepFailure)
        }
        self.island = nil
    }

    /// A job, rebuild or check is under way
    var isBusy: Bool {
        if hardware?.diskJob?.outcome == .running { return true }
        return arrays.contains { array in
            switch array.state {
            case .rebuilding, .checking: return true
            default: return false
            }
        }
    }

    func loadStoredSecret() async {
        let deploymentID = deployment.id
        let slot = host
        let stored = await Task.detached {
            InstallCredentialStore(deploymentID: deploymentID).secret(for: slot)
        }.value
        if let stored { secret = SSHSecretDraft(editing: stored) }
    }

    /// Runs one repair as root, then reads the disks again
    func run(_ step: StorageStep) async {
        island?.finish("")
        island = IslandRun(title: step.title, serverName: deployment.name,
                           progressText: UIL10n.string("Working on the disks…"), deployment: deployment)
        _ = await output(of: step)
        await load()
        if isBusy, stepFailure == nil {
            island?.update(busyLine.text, progress: busyLine.progress)
        } else {
            finishIsland()
        }
    }

    /// Runs a script as root and returns what it printed
    @discardableResult
    func output(of step: StorageStep) async -> String? {
        guard let endpoint else { return nil }
        runningStep = step.title
        stepFailure = nil
        defer { runningStep = nil }
        do {
            if usesServerAccount {
                let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: deployment)
                if let output = try await agentOutput(of: step, runner: runner) { return output }
                return try await StoragePreparation.output(of: step, runner: runner, host: host,
                                                           elevated: serverAccount != "root")
            }
            let stored = InstallCredentialStore(deploymentID: deployment.id).secret(for: host)
            var draft = secret
            guard let resolved = draft.secret(keeping: stored) else { return nil }
            secret = draft
            let user = username.trimmingCharacters(in: .whitespaces)
            let runner = try await InstallSessionFactory.makeRunnerDetached(
                deployment: deployment, address: endpoint.host, port: endpoint.port,
                username: user, pinSlot: host, secret: resolved)
            defer { Task { await runner.disconnect() } }
            return try await StoragePreparation.output(of: step, runner: runner, elevated: user != "root")
        } catch {
            stepFailure = AgentOutdated.describe(error)
            return nil
        }
    }
}

extension StorageViewModel {
    /// Runs the step through the agent, when it can
    func agentOutput(of step: StorageStep, runner: any SSHCommandRunner) async throws -> String? {
        guard let task = step.agentTask, deployment.usesAgent, #available(macOS 15.0, *) else { return nil }
        let client = try await AgentConnection.client(deployment: deployment, runner: runner, host: host)
        let result: Gryonixnexusd_V1_StorageTaskResult
        do {
            result = try await client.runStorageTask(task)
        } catch AgentError.rpc(code: "not_found", message: _) {
            return nil
        }
        guard result.output.contains(step.doneMarker) else {
            let tail = result.output.split(separator: "\n").suffix(6).joined(separator: "\n")
            throw StoragePreparation.Failure(detail: step.title + "\n" + tail)
        }
        return result.output
    }
}

/// What the General tab knows about each machine's disks
@MainActor
final class StorageOverview: ObservableObject {
    @Published private(set) var hardware: [SSHHostID: ServerHardware] = [:]
    private var loadedFor: UUID?

    /// Needs two disks or an existing array
    static func manages(_ hardware: ServerHardware) -> Bool {
        hardware.disks.count >= 2 || !StorageArray.all(in: hardware).isEmpty
    }

    func load(_ deployment: Deployment, force: Bool = false) async {
        guard force || loadedFor != deployment.id else { return }
        loadedFor = deployment.id
        #if DEBUG
        if DemoFleet.covers(deployment) {
            if let demo = ServerHardware.parse(DemoHardware.degradedProbe) {
                hardware = Dictionary(uniqueKeysWithValues: deployment.workerHosts.map { ($0, demo) })
            }
            return
        }
        #endif
        guard let runner = try? await DashboardSessionFactory.makeRunnerDetached(deployment: deployment) else { return }
        for host in deployment.workerHosts {
            guard let result = try? await runner.run(ServerHardware.probeCommand, on: host, timeout: .seconds(20)),
                  let parsed = ServerHardware.parse(result.stdout) else { continue }
            hardware[host] = parsed
        }
    }
}
