import AgentClient
import Foundation
import MailRecipe
import ServerControl
import SwiftUI

/// Servers whose agent is older than available
@MainActor
final class AgentUpdateOffer: ObservableObject {
    static let shared = AgentUpdateOffer()

    struct Outdated: Identifiable, Equatable, Sendable {
        /// Where the newer version comes from
        enum Source: Equatable, Sendable { case bundled, published }

        let deployment: Deployment
        let installed: String
        var target = ""
        var source = Source.bundled
        var id: UUID { deployment.id }
    }

    struct Offer: Identifiable, Equatable {
        let version: String
        let servers: [Outdated]
        var id: String { version }
    }

    @Published var offer: Offer?
    /// Last check at opening, per server, for its agent page
    @Published private(set) var findings: [UUID: Check] = [:]

    /// What one server turned out to be
    enum Check: Sendable, Equatable {
        case current, unreachable(String), outdated(Outdated)

        var outdated: Outdated? { if case .outdated(let item) = self { item } else { nil } }
    }

    typealias Fleet = @MainActor () -> [Deployment]
    typealias Probe = @Sendable (Deployment, String) async -> Check
    /// False while the licence is still loading
    typealias Ready = @MainActor () async -> Bool

    private let fleet: Fleet
    private let probe: Probe
    private let ready: Ready
    private let deadline: Duration
    private let retryDelay: Duration
    private let presentWithin: Duration
    private var checking = false
    private var dismissedThisRun = false
    private var lastChecked: Date?
    private var foundOutdated = false
    private var retries = 0
    private var presentation: Task<Void, Never>?
    private var appeared = false
    private static let recheckAfter: TimeInterval = 120
    private static let maxRetries = 4
    private static let presentAttempts = 20

    init(fleet: @escaping Fleet = AgentUpdateOffer.storedFleet,
         probe: @escaping Probe = AgentUpdateOffer.check,
         ready: @escaping Ready = AgentUpdateOffer.licenceReady,
         deadline: Duration = .seconds(45),
         retryDelay: Duration = .seconds(15),
         presentWithin: Duration = .seconds(3)) {
        self.fleet = fleet
        self.probe = probe
        self.ready = ready
        self.deadline = deadline
        self.retryDelay = retryDelay
        self.presentWithin = presentWithin
    }

    /// An App Store licence arrives a moment after launch
    private static func licenceReady() async -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_AGENT_OFFER"] != nil { return true }
        #endif
        if LicenseStore.shared.status.isActive { return true }
        await PurchaseStore.shared.refreshEntitlement()
        return LicenseStore.shared.status.isActive
    }

    private static func storedFleet() -> [Deployment] {
        #if DEBUG
        if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_AGENT_OFFER"] != nil,
           let demo = DemoDeployments.fromEnvironment() {
            return Array(demo.prefix(2))
        }
        #endif
        return ((try? FileDeploymentStore().load()) ?? []).filter { $0.usesAgent && !DemoServer.isDemo($0) }
    }

    /// Each time the app is opened
    func checkOnLaunch() async {
        guard !checking, offer == nil, presentation == nil, !dismissedThisRun else { return }
        if !foundOutdated, let lastChecked, Date().timeIntervalSince(lastChecked) < Self.recheckAfter { return }
        guard #available(macOS 15.0, *) else { return }
        checking = true
        defer { checking = false }
        guard await ready() else {
            retryLater()
            return
        }
        let checks = await checkAll(shipped: AgentBootstrapOperations.shippedVersion)
        take(checks)
        let silent = checks.contains { if case .unreachable = $0.1 { true } else { false } }
        lastChecked = silent ? nil : Date()
        if silent, !foundOutdated { retryLater() } else { retries = 0 }
    }

    /// The window opens with the first outdated server
    private func take(_ checks: [(UUID, Check)]) {
        for (id, check) in checks { findings[id] = check }
        let outdated = checks.compactMap(\.1.outdated).sorted { $0.deployment.name < $1.deployment.name }
        foundOutdated = !outdated.isEmpty
        guard foundOutdated, !dismissedThisRun else { return }
        let next = Offer(version: Self.highest(outdated), servers: outdated)
        guard next != offer else { return }
        if appeared, offer?.id == next.id { offer = next } else { present(next) }
    }

    /// The next opening asks again, even after Later
    func appLeft() {
        dismissedThisRun = false
        retries = 0
    }

    /// The window shows itself
    func appeared(_ shown: Offer) {
        if shown == offer { appeared = true }
    }

    /// Another window may hide ours; retry until it is seen
    private func present(_ found: Offer) {
        presentation?.cancel()
        presentation = Task { [weak self, presentWithin] in
            for _ in 0..<Self.presentAttempts {
                guard let self, !Task.isCancelled, !self.dismissedThisRun else { break }
                self.appeared = false
                self.offer = found
                try? await Task.sleep(for: presentWithin)
                if self.appeared || self.offer == nil || Task.isCancelled { break }
                self.offer = nil
                try? await Task.sleep(for: presentWithin)
            }
            if !Task.isCancelled { self?.presentation = nil }
        }
    }

    private func stopPresenting() {
        presentation?.cancel()
        presentation = nil
    }

    /// Network or licence may not be ready at start
    private func retryLater() {
        guard retries < Self.maxRetries else { return }
        retries += 1
        Task {
            try? await Task.sleep(for: retryDelay)
            await checkOnLaunch()
        }
    }

    private static func highest(_ servers: [Outdated]) -> String {
        servers.map(\.target).reduce("") { AgentVersion.isNewer($1, than: $0) || $0.isEmpty ? $1 : $0 }
    }

    private func checkAll(shipped version: String) async -> [(UUID, Check)] {
        let servers = fleet()
        let probe = self.probe
        let limit = deadline
        let silence = UIL10n.string("The server has not answered for %lld seconds.", Int(limit.components.seconds))
        return await withTaskGroup(of: (UUID, Check).self) { group in
            for deployment in servers {
                group.addTask {
                    (deployment.id, await Deadline.run(limit, fallback: .unreachable(silence)) {
                        await probe(deployment, version)
                    })
                }
            }
            var found: [(UUID, Check)] = []
            for await item in group {
                found.append(item)
                self.take(found)
            }
            return found
        }
    }

    /// Whether any machine of the deployment runs an older agent
    @Sendable
    nonisolated static func check(_ deployment: Deployment, shipped: String) async -> Check {
        guard #available(macOS 15.0, *) else { return .current }
        let runner: any SSHCommandRunner & RemoteFileBrowser
        do {
            runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: deployment, shared: true)
        } catch {
            return .unreachable(await DashboardViewModel.message(for: error))
        }
        var silent: String?
        for host in deployment.agentHosts {
            let client: AgentClient
            let installed: String
            do {
                client = try await AgentConnection.client(deployment: deployment, runner: runner, host: host)
                installed = try await client.getState().agentVersion
            } catch {
                silent = await DashboardViewModel.message(for: error)
                continue
            }
            if AgentVersion.isNewer(shipped, than: installed) {
                return .outdated(Outdated(deployment: deployment, installed: installed, target: shipped))
            }
            if let status = try? await client.getAgentUpdateStatus(), status.updateAvailable,
               AgentVersion.isNewer(status.availableVersion, than: installed) {
                return .outdated(Outdated(deployment: deployment, installed: installed,
                                          target: status.availableVersion, source: .published))
            }
        }
        return silent.map(Check.unreachable) ?? .current
    }

    func later() {
        dismissedThisRun = true
        stopPresenting()
        offer = nil
    }

    /// Updates each server in turn, each with its own progress
    func updateAll() {
        guard let offer else { return }
        dismissedThisRun = true
        stopPresenting()
        foundOutdated = false
        lastChecked = Date()
        self.offer = nil
        Task {
            for server in offer.servers { await update(server) }
        }
    }

    private func update(_ server: Outdated) async {
        let deployment = server.deployment
        let state = LongOperationState(title: UIL10n.string("Updating the agent"),
                                       progressText: UIL10n.string("Connecting…"))
        state.retry = { [weak self] in Task { await self?.update(server) } }
        RunningOperationsRegistry.shared.adopt(state, serverName: deployment.name, deployment: deployment)
        do {
            let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: deployment, shared: false)
            defer { Task { await runner.disconnect() } }
            let failures = server.source == .published
                ? await Self.applyPublished(deployment, runner: runner, state: state)
                : await Self.installEverywhere(deployment, runner: runner, state: state)
            if failures.isEmpty {
                state.progress = 1
                state.progressText = UIL10n.string("The agent is updated.")
            } else {
                state.errorMessage = failures.joined(separator: "\n")
            }
        } catch {
            state.errorMessage = DashboardViewModel.message(for: error)
        }
        state.isFinished = true
    }

    /// Asks each agent to fetch and apply its published update
    private static func applyPublished(_ deployment: Deployment, runner: any SSHCommandRunner & RemoteFileBrowser,
                                       state: LongOperationState) async -> [String] {
        guard #available(macOS 15.0, *) else { return [] }
        var failures: [String] = []
        for host in deployment.agentHosts {
            let name = DashboardViewModel.hostDisplayName(host, in: deployment)
            do {
                let client = try await AgentConnection.client(deployment: deployment, runner: runner, host: host)
                guard try await client.getAgentUpdateStatus().updateAvailable else { continue }
                var heard = false
                do {
                    for try await event in client.applyAgentUpdate() {
                        heard = true
                        if !event.text.isEmpty { await MainActor.run { state.progressText = event.text } }
                        if event.phase == .failed {
                            failures.append("\(name): " + (event.reason.isEmpty ? UIL10n.string("The update failed.") : event.reason))
                            break
                        }
                    }
                } catch where heard {
                    // The agent restarts itself, which ends the stream
                }
            } catch {
                failures.append("\(name): \(DashboardViewModel.message(for: error))")
            }
        }
        return failures
    }
}

extension AgentUpdateOffer {
    /// Every machine at once, builds side by side
    static func installEverywhere(_ deployment: Deployment, runner: any SSHCommandRunner & RemoteFileBrowser,
                                  state: LongOperationState) async -> [String] {
        await withTaskGroup(of: String?.self) { group in
            for host in deployment.agentHosts {
                let name = DashboardViewModel.hostDisplayName(host, in: deployment)
                group.addTask { @MainActor in
                    do {
                        try await install(on: host, named: name, runner: runner, state: state)
                        return nil
                    } catch let error as AgentUpdateNeedsAccess {
                        return error.localizedDescription
                    } catch {
                        return "\(name): \(DashboardViewModel.message(for: error))"
                    }
                }
            }
            var failures: [String] = []
            for await failure in group { if let failure { failures.append(failure) } }
            return failures
        }
    }

    /// One machine's agent, rebuilt from the shipped sources
    static func install(on host: SSHHostID, named name: String, runner: any SSHCommandRunner & RemoteFileBrowser,
                        state: LongOperationState, reinstall: Bool = false) async throws {
        let probe = try await runner.run(SudoAccess.probeCommand(allowing: AgentBootstrapSections.scriptPath),
                                         on: host, timeout: .seconds(20))
        guard SudoAccess.isReady(probe.stdout) else { throw AgentUpdateNeedsAccess(host: name) }
        let build = AgentBuildProgress(state: state)
        try await AgentBootstrapOperations.install(
            runner: runner, host: host, source: DashboardViewModel.chosenAgentSource, reinstall: reinstall,
            onPhase: { phase in Task { @MainActor in state.progressText = phase } },
            onOutput: { line in
                Task { @MainActor in
                    state.log = OutputTail.tail(state.log + line + "\n", maxCharacters: OutputTail.logCharacters)
                    build.line(line)
                }
            })
    }
}

/// The machine may not run the agent bootstrap yet
struct AgentUpdateNeedsAccess: LocalizedError {
    let host: String

    var errorDescription: String? {
        UIL10n.string("%@: the app is not allowed to update the agent on this machine yet. Run its setup script once more; after that the app updates it by itself.", host)
    }
}

/// The question itself
struct AgentUpdateOfferView: View {
    @ObservedObject var model: AgentUpdateOffer
    let offer: AgentUpdateOffer.Offer

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(offer.servers) { server in
                        LabeledContent(server.deployment.name) {
                            Text(verbatim: "\(server.installed) → \(server.target)").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Servers with an older agent")
                } footer: {
                    Text("Each server builds the new agent itself; this takes a few minutes and the services keep running.")
                }
            }
            .navigationTitle(Text("Agent \(offer.version) is available"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button { model.updateAll() } label: {
                        Text("Update all")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .prominentActionButtonStyle()
                    .controlSize(.large)
                    Button("Later") { model.later() }
                }
                .padding()
            }
        }
        .interactiveDismissDisabled()
        .onAppear { model.appeared(offer) }
    }
}

/// What the check at opening found for this server
struct AgentOpeningCheckRow: View {
    let deploymentID: UUID
    @ObservedObject private var model = AgentUpdateOffer.shared

    var body: some View {
        if let finding = model.findings[deploymentID] {
            Section {
                LabeledContent {
                    Text(verbatim: text(finding)).foregroundStyle(.secondary)
                } label: {
                    Text("When the app opened")
                }
            }
        }
    }

    private func text(_ finding: AgentUpdateOffer.Check) -> String {
        switch finding {
        case .current: UIL10n.string("Up to date")
        case .unreachable(let reason): reason.isEmpty ? UIL10n.string("The server did not answer.") : reason
        case .outdated(let item): UIL10n.string("Agent %@ is available", item.target)
        }
    }
}
