import AgentClient
import AgentControl
import Foundation
import gryonixNexusCore
import MailRecipe
import ServerControl
import ServerControlSSH
import ServiceCatalog
import SwiftUI

@MainActor
final class InstallViewModel: ObservableObject {
    struct Target: Identifiable {
        enum Kind {
            case single
            case vps
            case home
        }

        let kind: Kind
        let script: Artifact
        let pinSlot: SSHHostID
        var address: String
        var port: Int
        var username = "root"
        /// How this machine is signed in to
        var secret = SSHSecretDraft()
        var connection = ConnectionState.unchecked
        /// Hardware read during the connection check
        var hardware: ServerHardware?
        var storage = StorageChoice()
        var swap = SwapState.idle

        var id: SSHHostID { pinSlot }

        var expectedDistribution: String? {
            script.contents
                .split(separator: "\n")
                .prefix(10)
                .first { $0.contains("\(SetupMarkers.distribution):") }
                .flatMap { $0.split(separator: ":").last }
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    enum ConnectionState: Equatable {
        case unchecked
        case checking
        case ok
        /// Signed in, but sudo still asks for a password
        case needsSudoPassword(String?)
        case failed(String)
    }

    enum Phase: Equatable {
        /// Entering addresses, pasting the key, checking connections
        case setup
        case installing
        case finished
        case failed(String)
    }

    struct Report: Identifiable {
        let id = UUID()
        let targetKind: Target.Kind
        let text: String
    }

    /// DKIM records the server generated
    @Published private(set) var dkimRecordsFromStream: [DKIMRecord] = []

    var dkimRecords: [DKIMRecord] { dkimRecordsFromStream }

    var mailWasInstalled: Bool {
        ServiceRegistry.mailEngine(in: deployment.services) != nil
    }

    var requirements: ServerRequirements {
        ServiceRegistry.requirements(for: deployment.services)
    }

    /// A relay carries no services, so it needs far less
    func requirements(for kind: Target.Kind) -> ServerRequirements {
        kind == .vps ? ServiceRegistry.relayRequirements : requirements
    }

    private(set) var deployment: Deployment
    /// Settings from before the data moved to an array
    private var settingsBeforePlacement: ServiceSettings?

    @Published var targets: [Target] = []
    @Published private(set) var phase = Phase.setup {
        didSet {
            #if DEBUG
            InstallResetProbe.note("InstallViewModel.phase \(String(describing: oldValue)) -> \(String(describing: phase))")
            #endif
            Task { @MainActor in InstallSessionRegistry.shared.refreshActivity() }
        }
    }
    @Published private(set) var currentTargetIndex = 0
    @Published private(set) var stage = ""
    @Published private(set) var stepIndex = 0
    @Published private(set) var stepTotal = 0
    /// One machine's run, as one bar
    @Published private(set) var parts = InstallParts()
    @Published private(set) var logLines: [String] = []
    @Published private(set) var reports: [Report] = []
    @Published private(set) var installWarnings: [String] = []
    @Published private(set) var publicKey: String?
    let dnsRecordsText: String?
    /// One script per service, from the generated bundle
    private let allServiceScripts: [Artifact]
    @Published private(set) var sawDNSCheckFailure = false
    @Published private(set) var sawPortConflict = false

    private var installTask: Task<Void, Never>?
    private var skipDNSCheck = false
    private var tunnelConnected = false

    #if DEBUG
    func debugSeedHardware() {
        guard !targets.isEmpty else { return }
        targets[0].connection = .ok
        targets[0].hardware = ServerHardware.parse(DemoHardware.probeOutput)
        targets[0].storage = targets[0].hardware.map(StorageChoice.defaults(for:)) ?? StorageChoice()
    }

    func debugSeedFinished() {
        phase = .finished
        dkimRecordsFromStream = [DKIMRecord(
            name: "dkim._domainkey.example.com",
            value: "v=DKIM1;k=rsa;t=s;p=" + String(repeating: "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A", count: 13))]
        let body = (1...200).map { "line \($0): synthetic report content for layout testing" }
            .joined(separator: "\n")
        reports = [Report(targetKind: .single, text: body)]
    }
    #endif
    private static let logLimit = 20_000

    let bundleFingerprint: Int

    var isInstalling: Bool { phase == .installing }

    static func fingerprint(of bundle: GeneratedBundle) -> Int {
        var hasher = Hasher()
        for artifact in bundle.artifacts where artifact.kind == .shellScript {
            hasher.combine(artifact.fileName)
            hasher.combine(artifact.contents)
        }
        return hasher.finalize()
    }

    init(deployment: Deployment, bundle: GeneratedBundle) {
        self.deployment = deployment
        self.allServiceScripts = bundle.serviceScripts
        self.bundleFingerprint = Self.fingerprint(of: bundle)
        self.dnsRecordsText = bundle.artifacts.first { $0.kind == .dnsRecord }?.contents
        self.publicKey = nil

        func script(for role: ServerRole) -> Artifact? {
            bundle.artifacts.first { $0.kind == .shellScript && $0.server == role }
        }
        func installUser(_ host: SSHHostID) -> String {
            InstallAddressStore.installUser(deploymentID: deployment.id, host: host) ?? "root"
        }
        if let single = script(for: .singleHost) {
            targets = [Target(kind: .single, script: single, pinSlot: .vps,
                              address: deployment.entry.host, port: deployment.entry.port,
                              username: installUser(.vps))]
        } else if let vps = script(for: .vpsRelay), let home = script(for: .homeBackend) {
            targets = [
                Target(kind: .vps, script: vps, pinSlot: .vps,
                       address: deployment.entry.host, port: deployment.entry.port,
                       username: installUser(.vps)),
                Target(kind: .home, script: home, pinSlot: .home,
                       address: InstallAddressStore.homeAddress(deploymentID: deployment.id),
                       port: 22, username: installUser(.home))
            ]
        }
    }

    func loadIdentityIfNeeded() async {
        guard publicKey == nil else { return }
        let deploymentID = deployment.id
        let slots = targets.map(\.pinSlot)
        let loaded = await Task.detached(priority: .userInitiated) {
            let key = try? KeychainSSHIdentityStore(deploymentID: deploymentID).loadOrGenerate().publicKeyOpenSSH
            let store = InstallCredentialStore(deploymentID: deploymentID)
            let secrets = slots.reduce(into: [SSHHostID: SSHSecret]()) { found, slot in
                found[slot] = store.secret(for: slot)
            }
            return (key, secrets)
        }.value
        publicKey = loaded.0
        for index in targets.indices {
            if let stored = loaded.1[targets[index].pinSlot] {
                targets[index].secret = SSHSecretDraft(editing: stored)
            }
        }
    }

    private func resolveSecret(_ index: Int) async -> SSHSecret? {
        let target = targets[index]
        let deploymentID = deployment.id
        let slot = target.pinSlot
        let stored = await Task.detached(priority: .userInitiated) {
            InstallCredentialStore(deploymentID: deploymentID).secret(for: slot)
        }.value
        var draft = target.secret
        let resolved = draft.secret(keeping: stored)
        targets[index].secret = draft
        return resolved
    }

    func credentialChanged(_ targetID: SSHHostID) {
        guard let index = targets.firstIndex(where: { $0.id == targetID }) else { return }
        targets[index].connection = .unchecked
    }

    /// Remembers a credential that has just been proven to work
    private func remember(_ secret: SSHSecret, for slot: SSHHostID) {
        let deploymentID = deployment.id
        Task.detached(priority: .utility) {
            try? InstallCredentialStore(deploymentID: deploymentID).save(secret, for: slot)
        }
    }

    var grantCommand: String {
        AccessGrantCommand.command(publicKey: publicKey ?? "")
    }

    var canStart: Bool {
        phase == .setup && publicKey != nil
            && targets.allSatisfy { $0.connection == .ok && $0.secret.isComplete && $0.storageIsReady }
    }

    var needsAccessGrant: Bool {
        targets.contains { $0.secret.kind == .appKey }
    }

    var overallProgress: Double {
        guard !targets.isEmpty else { return 0 }
        let script = stepTotal > 0 ? Double(stepIndex) / Double(stepTotal) : 0
        return (Double(currentTargetIndex) + parts.fraction(script: script)) / Double(targets.count)
    }

    /// The one line the lock screen has room for
    var lockScreenLine: String {
        let base = stage.isEmpty ? UIL10n.string("Starting the installation…") : stage
        guard targets.count > 1 else { return base }
        return UIL10n.string("%1$@ — machine %2$lld of %3$lld",
                             base, currentTargetIndex + 1, targets.count)
    }

    var failureMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    // MARK: - Connection check

    func checkConnection(_ targetID: SSHHostID) {
        guard let index = targets.firstIndex(where: { $0.id == targetID }) else { return }
        targets[index].connection = .checking
        Task {
            guard let secret = await resolveSecret(index) else {
                if let index = targets.firstIndex(where: { $0.id == targetID }) {
                    targets[index].connection = .unchecked
                }
                return
            }
            let (state, hardware) = await probeConnection(targets[index], secret: secret)
            if state == .ok { remember(secret, for: targetID) }
            if let index = targets.firstIndex(where: { $0.id == targetID }) {
                targets[index].connection = state
                if targets[index].hardware != hardware {
                    targets[index].hardware = hardware
                    targets[index].storage = hardware.map(StorageChoice.defaults(for:)) ?? StorageChoice()
                }
            }
        }
    }

    /// Makes a swap file, then reads the machine again
    func addSwap(_ targetID: SSHHostID, sizeGB: Int) {
        guard let index = targets.firstIndex(where: { $0.id == targetID }) else { return }
        targets[index].swap = .adding
        Task {
            let outcome = await runSwap(targets[index], sizeGB: sizeGB)
            guard let index = targets.firstIndex(where: { $0.id == targetID }) else { return }
            targets[index].swap = outcome
            if outcome == .idle { checkConnection(targetID) }
        }
    }

    private func runSwap(_ target: Target, sizeGB: Int) async -> SwapState {
        guard let index = targets.firstIndex(where: { $0.id == target.id }),
              let secret = await resolveSecret(index) else { return .idle }
        let step = StorageStep(title: UIL10n.string("Adding swap…"), script: SwapPlan(sizeGB: sizeGB).script(),
                               doneMarker: SwapPlan.doneMarker)
        do {
            let runner = try await InstallSessionFactory.makeRunnerDetached(
                deployment: deployment, address: target.address.trimmingCharacters(in: .whitespaces),
                port: target.port, username: target.username.trimmingCharacters(in: .whitespaces),
                pinSlot: target.pinSlot, secret: secret)
            defer { Task { await runner.disconnect() } }
            let elevated = target.username.trimmingCharacters(in: .whitespaces) != "root"
            _ = try await StoragePreparation.output(of: step, runner: runner, elevated: elevated)
            return .idle
        } catch {
            return .failed((error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
    }

    private func probeConnection(_ target: Target,
                                 secret: SSHSecret) async -> (ConnectionState, ServerHardware?) {
        var lastError = UIL10n.string("Unexpected response from the server")
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(2)) }
            do {
                let runner = try await InstallSessionFactory.makeRunnerDetached(
                    deployment: deployment,
                    address: target.address.trimmingCharacters(in: .whitespaces),
                    port: target.port,
                    username: target.username.trimmingCharacters(in: .whitespaces),
                    pinSlot: target.pinSlot,
                    secret: secret
                )
                let result = try await runner.run(
                    "echo GRYONIXNEXUS_PING; . /etc/os-release 2>/dev/null; " +
                    "echo \"\(SetupMarkers.distribution):${ID:-}:${ID_LIKE:-}\"; " +
                    ServerHardware.probeCommand + "; " + SudoAccess.probeCommand,
                    on: .vps, timeout: .seconds(20))
                await runner.disconnect()
                if result.stdout.contains("GRYONIXNEXUS_PING") {
                    let hardware = ServerHardware.parse(result.stdout)
                    if let mismatch = distributionMismatch(target, output: result.stdout) {
                        return (.failed(mismatch), hardware)
                    }
                    guard SudoAccess.isReady(result.stdout) else {
                        return (.needsSudoPassword(nil), hardware)
                    }
                    return (.ok, hardware)
                }
            } catch {
                lastError = grantDescription(of: error)
            }
        }
        return (.failed(lastError), nil)
    }

    /// Writes passwordless sudo with the password typed once
    func grantSudo(_ targetID: SSHHostID, password: String) {
        guard let index = targets.firstIndex(where: { $0.id == targetID }) else { return }
        targets[index].connection = .checking
        Task {
            let state = await sudoGrantState(targets[index], password: password)
            guard let index = targets.firstIndex(where: { $0.id == targetID }) else { return }
            if state == .ok { checkConnection(targetID) } else { targets[index].connection = state }
        }
    }

    private func sudoGrantState(_ target: Target, password: String) async -> ConnectionState {
        guard let index = targets.firstIndex(where: { $0.id == target.id }),
              let secret = await resolveSecret(index) else { return .unchecked }
        do {
            let runner = try await InstallSessionFactory.makeRunnerDetached(
                deployment: deployment,
                address: target.address.trimmingCharacters(in: .whitespaces),
                port: target.port,
                username: target.username.trimmingCharacters(in: .whitespaces),
                pinSlot: target.pinSlot,
                secret: secret
            )
            defer { Task { await runner.disconnect() } }
            let outcome = try await SudoAccess.grant(password: password, runner: runner, host: .vps)
            return Self.state(after: outcome)
        } catch {
            return .needsSudoPassword(shortDescription(of: error))
        }
    }

    static func state(after outcome: SudoAccess.Outcome) -> ConnectionState {
        switch outcome {
        case .granted:
            return .ok
        case .wrongPassword:
            return .needsSudoPassword(UIL10n.string("Wrong password. Try again."))
        case .notAllowed:
            return .failed(UIL10n.string("This account may not act as administrator on the server. Sign in as root or as an account that may use sudo."))
        case .failed(let detail):
            return .needsSudoPassword(UIL10n.string("Could not set up administrator access: %@", detail))
        }
    }

    private func distributionMismatch(_ target: Target, output: String) -> String? {
        guard let expected = target.expectedDistribution else { return nil }
        guard let line = output.split(separator: "\n")
            .first(where: { $0.hasPrefix("\(SetupMarkers.distribution):") }) else { return nil }
        let fields = line.split(separator: ":", omittingEmptySubsequences: false)
        let id = fields.count > 1 ? String(fields[1]) : ""
        let idLike = fields.count > 2 ? String(fields[2]) : ""
        guard !id.isEmpty else { return nil }
        guard !DistributionMatch.accepts(expected: expected, id: id, idLike: idLike) else { return nil }
        return UIL10n.string(
            "This machine reports %@, but its script was generated for %@. Go back to the configuration, set this host's distribution, and generate again.",
            id, expected)
    }

    private func grantDescription(of error: Error) -> String {
        if let error = error as? ServerControlError, case .connectionFailed(let detail) = error,
           detail.localizedCaseInsensitiveContains("authentication") {
            return UIL10n.string("The server refused the app's key. Run the command from step 1 on this machine and check the account name it prints — it must be the install user above. A key added for a different account, or a ~/.ssh directory left owned by root, both look exactly like this.")
        }
        return shortDescription(of: error)
    }

    func addressChanged(_ targetID: SSHHostID) {
        guard let index = targets.firstIndex(where: { $0.id == targetID }) else { return }
        targets[index].connection = .unchecked
        targets[index].hardware = nil
        targets[index].storage = StorageChoice()
        if targets[index].kind == .home {
            InstallAddressStore.save(
                homeAddress: targets[index].address.trimmingCharacters(in: .whitespaces),
                deploymentID: deployment.id)
        }
        InstallAddressStore.save(
            installUser: targets[index].username.trimmingCharacters(in: .whitespaces),
            deploymentID: deployment.id,
            host: targets[index].pinSlot)
    }

    // MARK: - Installation

    func startInstall() {
        guard canStart else { return }
        #if DEBUG
        InstallResetProbe.note("InstallViewModel.startInstall() — canStart passed", trace: true)
        #endif
        phase = .installing
        runInstall()
    }

    #if DEBUG
    func debugForceInstalling() {
        InstallResetProbe.note("InstallViewModel.debugForceInstalling() — forcing phase = .installing", trace: true)
        phase = .installing
    }
    #endif

    func retry(skipDNSCheck: Bool = false) {
        guard case .failed = phase else { return }
        self.skipDNSCheck = skipDNSCheck
        phase = .installing
        runInstall()
    }

    func cancel() {
        installTask?.cancel()
        installTask = nil
        if phase == .installing { phase = .setup }
    }

    // MARK: - Resuming a running agent-phase job

    @available(macOS 15.0, *)
    func resumeAgentPhase() {
        guard phase == .setup else { return }
        phase = .installing
        installTask = Task {
            do {
                try await runResumedAgentPhase()
                phase = .finished
                NotificationCenter.default.post(name: .gryonixDeploymentInstalled,
                                                object: deployment.id)
            } catch is CancellationError {
                phase = .setup
            } catch {
                phase = .failed(shortDescription(of: error))
            }
        }
    }

    @available(macOS 15.0, *)
    private func runResumedAgentPhase() async throws {
        stage = UIL10n.string("Reconnecting…")
        let session = try await AgentConnection.open(deployment: deployment, shared: true)
        let client = session.client
        _ = try await client.getState().agentVersion
        markUsesAgent()

        let gate = AgentChannelGate.shared(for: deployment.id)
        let devicePublicKey = await DashboardViewModel.devicePublicKey(for: deployment)
        let context = DashboardViewModel.agentHostSurfaceContext(
            for: deployment, devicePublicKey: devicePublicKey)
        let installer = AgentInstallOperations(client: client, gate: gate)
        if let running = try? await installer.plan(), running.isRunning {
            try await finishPlan(try await followSetupPlan(planFollower(installer), from: running, gate: gate), gate: gate)
            PendingAgentInstalls.shared.refresh()
            await publishTunnelNames()
            return
        }
        let jobs = InstallJobStore()
        let present = AgentServiceMapping.serviceIDs(
            forAgentServices: ((try? await client.discover().services) ?? []).map { ($0.id, $0.containers.map(\.name)) })
        for service in ServiceRegistry.all where deployment.services.contains(service.id) {
            let existing = jobs.job(deployment: deployment.id, service: service.id)
            if existing == nil, present.contains(service.id) { continue }
            stage = UIL10n.string("Installing %@…", service.displayName)
            if let existing {
                _ = try await installer.watch(jobID: existing.jobID, onChunk: { [weak self] chunk in
                    Task { @MainActor in self?.appendLog(chunk) }
                }, onWarning: { [weak self] text in
                    Task { @MainActor in self?.appendWarning(text) }
                })
            } else {
                _ = try await installer.install(
                    service.id, context: await serviceContext(context, for: service),
                    onJobID: { [deploymentID = deployment.id] jobID in
                        jobs.remember(deployment: deploymentID, service: service.id, jobID: jobID)
                    },
                    onChunk: { [weak self] chunk in
                        Task { @MainActor in self?.appendLog(chunk) }
                    },
                    onWarning: { [weak self] text in
                        Task { @MainActor in self?.appendWarning(text) }
                    })
            }
            jobs.forget(deployment: deployment.id, service: service.id)
            if service.id == ServiceID.mailcow || service.id == ServiceID.mailu
                || service.id == ServiceID.dockerMailserver {
                dkimRecordsFromStream.append(
                    contentsOf: (try? await AgentDkimOperations(client: client, gate: gate)
                        .fetchRecords()) ?? [])
            }
        }
        PendingAgentInstalls.shared.refresh()
        await publishTunnelNames()
    }

    private func runInstall() {
        installTask = Task {
            let background = BackgroundGrace()
            defer { background.end() }
            defer { skipDNSCheck = false }
            while currentTargetIndex < targets.count {
                do {
                    try await install(targets[currentTargetIndex])
                    currentTargetIndex += 1
                } catch is CancellationError {
                    phase = .setup
                    return
                } catch {
                    phase = .failed(shortDescription(of: error))
                    return
                }
            }
            phase = .finished
            NotificationCenter.default.post(name: .gryonixDeploymentInstalled,
                                            object: deployment.id)
        }
    }

    private func install(_ target: Target) async throws {
        stage = ""
        stepIndex = 0
        stepTotal = 0
        sawDNSCheckFailure = false
        sawPortConflict = false

        guard let index = targets.firstIndex(where: { $0.id == target.id }),
              let secret = await resolveSecret(index) else {
            throw ServerControlError.notConfigured(
                UIL10n.string("choose how to sign in to this server"))
        }
        let runner = try await InstallSessionFactory.makeRunnerDetached(
            deployment: deployment,
            address: target.address.trimmingCharacters(in: .whitespaces),
            port: target.port,
            username: target.username.trimmingCharacters(in: .whitespaces),
            pinSlot: target.pinSlot,
            secret: secret
        )
        defer { Task { await runner.disconnect() } }
        let installUsername = target.username.trimmingCharacters(in: .whitespaces)

        try await prepareStorage(target, runner: runner, username: installUsername)

        let routeThroughAgent = Self.canRouteThroughAgent(deployment)
        parts = InstallParts(throughAgent: routeThroughAgent)
        let oneByOne = !serviceScripts(for: target).isEmpty

        let installer = SetupInstaller(runner: runner, host: .vps, username: installUsername)
        for try await event in installer.install(script: target.script.contents,
                                                 fileName: target.script.fileName,
                                                 skipDNSCheck: skipDNSCheck,
                                                 skipServices: routeThroughAgent || oneByOne) {
            handle(event, for: target)
        }

        guard routeThroughAgent else {
            if oneByOne { try await installOneByOne(target, runner: runner, username: installUsername) }
            return
        }
        parts.scriptDone = true

        if #available(macOS 15.0, *) {
            for attempt in 1...Self.agentAttempts {
                do {
                    try await installViaAgent(target: target, runner: runner)
                    return
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    logLines.append(UIL10n.string("Why: %@", shortDescription(of: error)))
                    if agentPlanStarted { throw error }
                    guard attempt < Self.agentAttempts else { break }
                    stage = UIL10n.string("The agent step did not finish. Trying it once more…")
                    logLines.append(stage)
                    try await Task.sleep(for: .seconds(3))
                }
            }
            stage = UIL10n.string("Could not hand services to the agent — installing them directly instead…")
            logLines.append(stage)
        }
        undoDataPlacement()
        try await installOneByOne(target, runner: runner, username: installUsername)
    }

    /// This machine's service scripts, the finishing one last
    private func serviceScripts(for target: Target) -> [Artifact] {
        allServiceScripts.filter { $0.server == target.script.server }
    }

    /// Each service by its own script, failures collected
    private func installOneByOne(_ target: Target, runner: any SSHCommandRunner,
                                 username: String) async throws {
        parts.directServices = true
        let scripts = serviceScripts(for: target)
        var failed: [String] = []
        for (index, script) in scripts.enumerated() {
            if script.fileName == Artifact.finishSetupName, !failed.isEmpty { break }
            stage = UIL10n.string("Installing %@ (%@ of %@)…", script.summary, "\(index + 1)", "\(scripts.count)")
            logLines.append(stage)
            do {
                try await runServiceScript(script, index: index, of: scripts.count, target: target,
                                           runner: runner, username: username)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failed.append(script.summary)
                logLines.append(UIL10n.string("Why: %@", shortDescription(of: error)))
            }
        }
        guard failed.isEmpty else {
            throw InstallStepFailure(message: UIL10n.string(
                "Not installed: %@. Start the installation again to retry them.", failed.joined(separator: ", ")))
        }
    }

    private func runServiceScript(_ script: Artifact, index: Int, of count: Int, target: Target,
                                  runner: any SSHCommandRunner, username: String) async throws {
        let installer = SetupInstaller(runner: runner, host: .vps, username: username)
        for try await event in installer.install(script: script.contents, fileName: script.fileName,
                                                 skipDNSCheck: true, skipServices: false) {
            if case .step(let step, let total) = event {
                parts.directStep = (Double(index) + Double(step) / Double(max(total, 1))) / Double(count)
            } else {
                handle(event, for: target)
            }
        }
    }

    /// Builds the chosen RAID and fast storage before setup
    private func prepareStorage(_ target: Target, runner: any SSHCommandRunner,
                                username: String) async throws {
        for step in target.storageSteps {
            stage = step.title
            logLines.append(step.title)
            try await StoragePreparation.run(step, runner: runner, username: username)
        }
    }

    /// Tries of the agent step before the direct path
    private static let agentAttempts = 2
    /// Once the agent runs the list, scripts stay out
    private var agentPlanStarted = false
    /// How far the setup plan's log is read
    private let planMark = PlanLogMark()

    private static func canRouteThroughAgent(_ deployment: Deployment) -> Bool {
        guard !deployment.entry.user.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if #available(macOS 15.0, *) { return true }
        return false
    }

    @available(macOS 15.0, *)
    private func installViaAgent(target: Target,
                                 runner: any SSHCommandRunner & RemoteFileBrowser) async throws {
        stage = UIL10n.string("Preparing the server…")
        if !DemoServer.isDemo(deployment) {
            try await AgentBootstrapOperations.install(
                runner: runner, host: .vps,
                onPhase: { [weak self] phase in Task { @MainActor in self?.stage = phase } },
                onOutput: { [weak self] line in
                    Task { @MainActor in
                        self?.appendLog(line)
                        self?.parts.agentBuild.line(line)
                    }
                })
        }
        parts.agentDone = true

        let client = try await AgentConnection.client(deployment: deployment, runner: runner, host: .vps)
        _ = try await client.getState().agentVersion
        markUsesAgent()

        let gate = AgentChannelGate.shared(for: deployment.id)
        let devicePublicKey = await DashboardViewModel.devicePublicKey(for: deployment)

        if target.kind == .vps, deployment.hasRelayIngress {
            stage = UIL10n.string("Configuring the relay…")
            let context = DashboardViewModel.agentHostSurfaceContext(
                for: deployment, devicePublicKey: devicePublicKey, role: .vpsRelay)
            _ = try await AgentInstallOperations(client: client, gate: gate).provisionHost(context)
            try await revokeInstallKey(target: target, runner: runner)
            return
        }

        if let mount = target.chosenDataMount { placeData(under: mount) }
        let context = DashboardViewModel.agentHostSurfaceContext(
            for: deployment, devicePublicKey: devicePublicKey)
        let installer = AgentInstallOperations(client: client, gate: gate)
        let onHost = AgentServiceMapping.serviceIDs(
            forAgentServices: ((try? await client.discover().services) ?? []).map { ($0.id, $0.containers.map(\.name)) })
        let chosen = ServiceInstallPlan.agentRun(
            chosen: ServiceRegistry.all.filter { deployment.services.contains($0.id) }, onHost: onHost)
        parts.servicesTotal = chosen.count
        var requests: [(ServiceID, AgentInstallContext)] = []
        for service in chosen {
            requests.append((service.id, await serviceContext(context, for: service)))
        }
        if !requests.isEmpty {
            let follower = planFollower(installer)
            let started = try await follower.start(requests)
            agentPlanStarted = true
            try await finishPlan(try await followSetupPlan(follower, from: started, gate: gate), gate: gate)
        }
        PendingAgentInstalls.shared.refresh()
        await publishTunnelNames()

        try await revokeInstallKey(target: target, runner: runner)
    }

    /// Follows the setup plan through sleep and dropped lines
    @available(macOS 15.0, *)
    private func followSetupPlan(_ first: InstallPlanFollower, from started: AgentInstallPlan,
                                 gate: AgentChannelGate) async throws -> AgentInstallPlan {
        var follower = first
        var dropsWhileOpen = 0
        while true {
            do {
                return try await follower.follow(started)
            } catch where Self.isLostConnection(error) {
                let watcher = RunningJobsWatcher.shared
                dropsWhileOpen += watcher.isAppActive ? 1 : 0
                stage = UIL10n.string("The server keeps working. Open the app to follow it.")
                await watcher.untilActive()
                guard dropsWhileOpen <= Self.reconnectAttempts else {
                    throw InstallStepFailure(message: UIL10n.string(
                        "Installing on the server. You can close the app — the server carries on, and this screen picks the run back up."))
                }
                stage = UIL10n.string("Reconnecting…")
                try await Task.sleep(for: .seconds(2))
                let session = try await AgentConnection.open(deployment: deployment, shared: true)
                follower.installer = AgentInstallOperations(client: session.client, gate: gate)
            }
        }
    }

    /// Anything but a reply the agent itself sent
    private static func isLostConnection(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if case AgentError.rpc = error { return false }
        if error is InstallStepFailure { return false }
        if case ServerControlError.commandFailed = error { return false }
        return true
    }

    private static let reconnectAttempts = 3

    @available(macOS 15.0, *)
    private func planFollower(_ installer: AgentInstallOperations) -> InstallPlanFollower {
        InstallPlanFollower(
            installer: installer,
            purpose: .setup,
            onStage: { [weak self] stage in
                self?.stage = stage
                self?.logLines.append(stage)
            },
            onProgress: { [weak self] settled, total in
                self?.parts.servicesTotal = total
                self?.parts.servicesDone = max(self?.parts.servicesDone ?? 0, settled)
            },
            onChunk: { [weak self] chunk in Task { @MainActor in self?.appendLog(chunk) } },
            onWarning: { [weak self] text in Task { @MainActor in self?.appendWarning(text) } },
            mark: planMark)
    }

    /// Fetches DKIM after mail; throws for missed services
    @available(macOS 15.0, *)
    private func finishPlan(_ plan: AgentInstallPlan, gate: AgentChannelGate) async throws {
        if InstallPlanFollower.installedMail(plan),
           let session = try? await AgentConnection.open(deployment: deployment, shared: true) {
            dkimRecordsFromStream.append(
                contentsOf: (try? await AgentDkimOperations(client: session.client, gate: gate).fetchRecords()) ?? [])
        }
        if let message = InstallPlanFollower.failureMessage(plan) {
            throw InstallStepFailure(message: message)
        }
    }

    /// One service's agent context; the tunnel gets its connector token
    private func serviceContext(_ base: AgentInstallContext, for service: any ManagedService) async -> AgentInstallContext {
        var context = base
        if let protocols = AgentInstallSettings.vpnProtocolList(adding: service.id,
                                                               installed: deployment.services) {
            context.settings[AgentInstallSettings.vpnProtocolsKey] = protocols
        }
        guard service.id == .cloudflared else { return context }
        stage = UIL10n.string("Preparing the tunnel at Cloudflare…")
        do {
            context.settings[AgentInstallSettings.cloudflaredTokenKey] =
                try await TunnelSetup.connectorToken(for: deployment)
            tunnelConnected = true
        } catch {
            appendWarning(shortDescription(of: error))
        }
        return context
    }

    /// Sends the deployment's web names through its tunnel
    private func publishTunnelNames() async {
        guard tunnelConnected else { return }
        do {
            let count = try await TunnelSetup.publishNames(of: deployment)
            appendLog(UIL10n.string("%lld names now reach this server through the tunnel.", count))
        } catch {
            appendWarning(shortDescription(of: error))
        }
    }

    private func revokeInstallKey(target: Target, runner: any SSHCommandRunner) async throws {
        let access = DashboardAccessInput(sshUser: deployment.entry.user, appPublicKey: publicKey ?? "")
        let command = DashboardAccessSections.revokeInstallKey(access, language: ContentLanguageSetting.current)
        let result = try? await runner.run(command, on: .vps, timeout: .seconds(60))
        if result?.succeeded != true {
            appendWarning(UIL10n.string("The installation key could not be removed from the server. Remove it from the server's authorized keys by hand."))
        }
    }

    /// Points every service's data folders at the array
    private func placeData(under mount: String) {
        if settingsBeforePlacement == nil { settingsBeforePlacement = deployment.serviceSettings }
        for id in deployment.services {
            deployment.serviceSettings.placeData(of: id, under: mount)
        }
        saveServiceSettings()
    }

    /// The script installs to the usual folders
    private func undoDataPlacement() {
        guard let before = settingsBeforePlacement else { return }
        deployment.serviceSettings = before
        settingsBeforePlacement = nil
        saveServiceSettings()
    }

    private func saveServiceSettings() {
        let deploymentID = deployment.id
        let settings = deployment.serviceSettings
        Task.detached(priority: .utility) {
            try? FileDeploymentStore().update(id: deploymentID) { $0.serviceSettings = settings }
        }
    }

    /// Saved before the install reports done, so screens reread it
    private func markUsesAgent() {
        deployment.usesAgent = true
        _ = try? FileDeploymentStore().update(id: deployment.id) { $0.usesAgent = true }
    }

    private func appendLog(_ line: String) {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        logLines.append(text)
        if logLines.count > Self.logLimit {
            logLines.removeFirst(logLines.count - Self.logLimit)
        }
    }

    private func appendWarning(_ line: String) {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        installWarnings.append(text)
    }

    private func handle(_ event: SetupEvent, for target: Target) {
        switch event {
        case .step(let index, let total):
            if parts.directServices {
                parts.directStep = total > 0 ? Double(index) / Double(total) : 0
            } else {
                stepIndex = index
                stepTotal = total
            }
        case .stage(let title):
            stage = title
        case .line(let line):
            if line == SetupMarkers.dnsCheckFailed {
                sawDNSCheckFailure = true
                return
            }
            if line == SetupMarkers.portsInUse {
                sawPortConflict = true
                return
            }
            logLines.append(line)
            if logLines.count > Self.logLimit {
                logLines.removeFirst(logLines.count - Self.logLimit)
            }
        case .report(let text):
            let records = DKIMRecordParser.parse(text)
            dkimRecordsFromStream.append(contentsOf: records)
            let readable = DKIMRecordParser.stripMarkers(from: text)
            reports.removeAll { $0.targetKind == target.kind }
            reports.append(Report(targetKind: target.kind, text: readable))
            let store = DeploymentReportStore(deploymentID: deployment.id)
            let host = String(describing: target.kind)
            Task.detached(priority: .utility) {
                store.save(host: host, text: readable)
            }
        case .reconnecting(let attempt):
            stage = UIL10n.string("Connection lost — reconnecting (attempt %lld). The installation keeps running on the server.", attempt)
            logLines.append(stage)
        case .done:
            break
        }
    }

    private func shortDescription(of error: Error) -> String {
        if let error = error as? ServerControlError {
            if case .installUnfollowable = error {
                return UIL10n.string("Lost the connection to the installation log. The installation itself keeps running on the server — come back when the connection is back and it will pick the log up again.")
            }
            return error.errorDescription ?? String(describing: error)
        }
        return String(describing: error)
    }
}

/// Where one machine's run is, across its three parts
struct InstallParts: Equatable {
    var throughAgent = false
    var scriptDone = false
    var agentBuild = AgentBuildSteps()
    var agentDone = false
    var servicesTotal = 0
    var servicesDone = 0
    /// Services installed by the setup script instead
    var directServices = false
    var directStep = 0.0

    static let scriptShare = 0.45
    static let agentShare = 0.25

    /// The whole run's share, never going back
    func fraction(script: Double) -> Double {
        guard throughAgent else { return script }
        let setup = scriptDone ? 1 : script
        let agent = agentDone || directServices ? 1 : agentBuild.fraction
        let services: Double
        if directServices {
            services = directStep
        } else if servicesTotal > 0 {
            services = Double(servicesDone) / Double(servicesTotal)
        } else {
            services = agentDone ? 1 : 0
        }
        let rest = 1 - Self.scriptShare - Self.agentShare
        return Self.scriptShare * setup + Self.agentShare * agent + rest * services
    }
}

/// Where adding swap to one machine stands
enum SwapState: Equatable {
    case idle
    case adding
    case failed(String)
}

/// An install step that failed, with a readable reason
struct InstallStepFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
