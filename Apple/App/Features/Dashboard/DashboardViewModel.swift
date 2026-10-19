import AgentClient
import AgentClientSSH
import AgentControl
import Foundation
import gryonixNexusCore
import MailRecipe
import ServerControl
import ServerControlSSH
import ServiceCatalog
import SwiftUI
import VPNTunnel

/// State of a single dashboard row
enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

@MainActor
final class LongOperationState: ObservableObject, Identifiable {
    let id = UUID()
    let startedAt = Date()
    let title: String
    @Published var progressText: String {
        didSet { if let settled, progressText != settled.text { progressText = settled.text } }
    }
    @Published var log: String = ""
    @Published var isFinished = false
    @Published var errorMessage: String? {
        didSet { if let settled, errorMessage != settled.error { errorMessage = settled.error } }
    }
    /// The server's recorded ending; later writes keep it
    private var settled: (text: String, error: String?)?
    @Published var progress: Double?
    @Published var shareableBackupPath: String?
    /// What the user must still do, such as DNS records
    @Published var notice: String?
    /// DNS records to change once the user says yes
    @Published var dnsUpdate: ServiceDNSPublisher.Update?
    /// Which machine `shareableBackupPath` is an absolute path ON
    var downloadHost: SSHHostID?

    var reattachDeployment: Deployment?
    /// Runs the same operation again, when that makes sense
    var retry: (() -> Void)?

    init(title: String, progressText: String = "") {
        self.title = title
        self.progressText = progressText
    }

    /// Ends the run with what the server recorded
    func settle(progressText: String, errorMessage: String?) {
        settled = nil
        self.progressText = progressText
        self.errorMessage = errorMessage
        settled = (progressText, errorMessage)
        isFinished = true
    }
}

struct QuickActionResult: Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
}

/// Dashboard for a single deployment
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var deployment: Deployment

    /// Settings sent with the next install only
    var oneTimeInstallSettings: [String: String] = [:]

    @Published var vpsForwarding: Loadable<Bool> = .idle
    @Published var homeForwarding: Loadable<Bool> = .idle

    var forwarding: Loadable<Bool> {
        switch (vpsForwarding, homeForwarding) {
        case (.failed(let message), _), (_, .failed(let message)):
            return .failed(message)
        case (.loaded(let vps), .loaded(let home)):
            return .loaded(vps && home)
        case (.loading, _), (_, .loading):
            return .loading
        default:
            return .idle
        }
    }
    @Published var vpsPing: Loadable<PingResult> = .idle
    @Published var securityAutoRules: HostSecurityAutoRules?
    @Published var securityAutoRulesBusy = false
    @Published var securityAutoRulesError: String?

    @Published var onFallbackAddress = false
    @Published var tunnelPing: Loadable<PingResult> = .idle

    @Published var hostMetrics: [SSHHostID: Loadable<HostMetricsSnapshot>] = [:]
    @Published var hostWireGuard: [SSHHostID: Loadable<WGStatus>] = [:]
    @Published var hostDisk: [SSHHostID: Loadable<[DiskMount]>] = [:]
    @Published var hostMemory: [SSHHostID: Loadable<MemoryUsage>] = [:]

    var vpsMetrics: Loadable<HostMetricsSnapshot> { hostMetrics[.vps] ?? .idle }
    var homeMetrics: Loadable<HostMetricsSnapshot> { hostMetrics[.home] ?? .idle }
    var vpsWireGuard: Loadable<WGStatus> { hostWireGuard[.vps] ?? .idle }
    var vpsDisk: Loadable<[DiskMount]> { hostDisk[.vps] ?? .idle }
    var vpsMemory: Loadable<MemoryUsage> { hostMemory[.vps] ?? .idle }
    var homeWireGuard: Loadable<WGStatus> { hostWireGuard[.home] ?? .idle }
    var homeDisk: Loadable<[DiskMount]> { hostDisk[.home] ?? .idle }
    var homeMemory: Loadable<MemoryUsage> { hostMemory[.home] ?? .idle }

    private var previousMetricsSamples: [SSHHostID: HostMetricsSample] = [:]

    private var demoMetricsTick: UInt64 = 1

    // Services — generic, keyed by service id
    @Published var adminLockdown: Loadable<AdminLockdownState> = .idle

    @Published var serviceStatuses: [ServiceID: Loadable<[ContainerStatus]>] = [:]
    @Published var serviceBackups: [ServiceID: Loadable<[BackupEntry]>] = [:]
    @Published var preRestoreCopies: [ServiceID: [PreRestoreCopy]] = [:]

    /// Scheduled-backup configuration as it is on the server
    @Published var autoBackup = AutoBackupSettings()
    @Published private(set) var autoBackupAnswered = false
    @Published var autoBackupError: String?
    @Published var backupDestination = BackupDestinationState()
    @Published private(set) var backupDestinationAnswered = false
    @Published var backupDestinationBusy = false
    @Published var backupDestinationError: String?
    @Published var backupDestinationCheck: BackupDestinationTestResult?
    @Published var autoUpdate = AutoUpdateSettings()
    @Published var autoUpdateError: String?
    @Published var updateRunLog = ServiceUpdateRunLog(lastRun: nil, records: [])
    /// What the last check found, by service
    @Published var updateReports: [ServiceID: ServiceUpdateStatus] = [:]
    @Published var checkingUpdates = false

    @Published var quickActionResult: QuickActionResult?
    @Published var connectionError: String?
    @Published var isRefreshing = false

    func present(_ operation: LongOperationState, opensSheet: Bool = true) {
        RunningOperationsRegistry.shared.start(operation, serverName: deployment.name,
                                               deployment: deployment,
                                               opensSheet: opensSheet,
                                               downloadBackup: { [weak self, weak operation] path in
            guard let self else { throw CancellationError() }
            return try await self.downloadBackup(at: path, on: operation?.downloadHost)
        })
    }

    @MainActor
    private func appendWrapperOutput(_ chunk: String, to operation: LongOperationState) {
        operation.log = OutputTail.tail(WrapperLogText.readable(ANSIStripper.strip(operation.log + chunk)), maxCharacters: OutputTail.logCharacters)
    }

    private var runner: (any SSHCommandRunner)?
    private var sessionMaybeStale = false
    private let makeRunner: @Sendable (Deployment) throws -> any SSHCommandRunner

    var onDeploymentCorrected: ((Deployment) -> Void)?

    init(deployment: Deployment,
         makeRunner: @escaping @Sendable (Deployment) throws -> any SSHCommandRunner = {
             try DashboardSessionFactory.makeRunner(deployment: $0)
         }) {
        self.deployment = deployment
        self.makeRunner = makeRunner
    }

    var isRelay: Bool { deployment.hasRelayIngress }
    var services: [any ManagedService] { deployment.installedServices }
    var config: DashboardConfig { deployment.dashboardConfig }

    func commandSession() async throws -> any SSHCommandRunner { try await session() }

    func applyDeployment(_ updated: Deployment) { deployment = updated }

    func operations(for service: any ManagedService) async throws -> (ServiceOperations, any SSHCommandRunner) {
        let runner = try await session()
        return (ServiceOperations(runner: runner, deployment: deployment, service: service), runner)
    }

    /// Which path service management takes for this deployment
    var serviceControlRoute: ServiceControlRoute {
        ServiceControlRouting.route(usesAgent: deployment.usesAgent,
                                    agentTransportAvailable: Self.agentTransportAvailable)
    }

    static var agentTransportAvailable: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    lazy var agentGate = AgentChannelGate.shared(for: deployment.id)

    /// The management seam for one service
    func serviceControl(for service: any ManagedService) async throws -> any ServiceControlling {
        let runner = try await session()
        let ssh = SSHServiceControl(runner: runner, deployment: deployment)
        guard serviceControlRoute == .agent,
              AgentCommandRunner.agentID(for: service) != nil else { return ssh }
        guard #available(macOS 15.0, *) else { return ssh }
        guard let client = try? await AgentConnection.client(deployment: deployment, runner: runner)
        else { return ssh }
        return AgentCommandRunner(client: client, gate: agentGate)
    }

    /// The backup seam for one service
    func backupSeam(for service: any ManagedService) async throws -> any ServiceBackupManaging {
        let runner = try await session()
        let ssh = SSHServiceBackups(runner: runner, deployment: deployment)
        let kind = ServiceOperations(runner: runner, deployment: deployment, service: service).backupKind
        guard BackupRouting.route(usesAgent: deployment.usesAgent,
                                  agentTransportAvailable: Self.agentTransportAvailable,
                                  kind: kind) == .agent,
              AgentServiceMapping.agentID(for: service.id) != nil else { return ssh }
        guard #available(macOS 15.0, *) else { return ssh }
        guard let client = try? await AgentConnection.client(deployment: deployment, runner: runner)
        else { return ssh }
        return AgentBackupOperations(client: client, gate: agentGate)
    }

    /// The agent's backup calls, when this server uses it
    func agentBackups() async -> AgentBackupOperations? {
        guard deployment.usesAgent, Self.agentTransportAvailable else { return nil }
        guard #available(macOS 15.0, *) else { return nil }
        guard let runner = try? await session(),
              let client = try? await AgentConnection.client(deployment: deployment, runner: runner)
        else { return nil }
        return AgentBackupOperations(client: client, gate: agentGate)
    }

    /// The seam for RESTORING one service
    func restoreSeam(for service: any ManagedService) async throws -> any ServiceRestoreManaging {
        let runner = try await session()
        let ssh = SSHServiceRestore(runner: runner, deployment: deployment)
        guard RestoreRouting.route(usesAgent: deployment.usesAgent,
                                   agentTransportAvailable: Self.agentTransportAvailable) == .agent,
              AgentServiceMapping.agentID(for: service.id) != nil else { return ssh }
        guard #available(macOS 15.0, *) else { return ssh }
        guard let client = try? await AgentConnection.client(deployment: deployment, runner: runner)
        else { return ssh }
        return AgentRestoreOperations(client: client, gate: agentGate)
    }

    /// The seam for scheduled/on-demand SERVICE UPDATES
    private func updateManaging() async throws -> any ServiceUpdateManaging {
        let runner = try await session()
        let ssh = ServiceUpdateOperations(runner: runner, deployment: deployment)
        let route = ServiceUpdateRouting.route(usesAgent: deployment.usesAgent,
                                               agentTransportAvailable: Self.agentTransportAvailable)
        guard route == .agent else { return ssh }
        guard #available(macOS 15.0, *) else { return ssh }
        guard let client = try? await AgentConnection.client(deployment: deployment, runner: runner)
        else { return ssh }
        return AgentUpdateOperations(client: client, gate: agentGate)
    }

    /// The seam for the CATALOG SERVICES' backup schedule
    func autoBackupSeam() async throws -> any AutoBackupManaging {
        let runner = try await session()
        let ssh = AutoBackupOperations(runner: runner, deployment: deployment)
        let route = AutoBackupRouting.route(usesAgent: deployment.usesAgent,
                                            agentTransportAvailable: Self.agentTransportAvailable)
        guard route == .agent else { return ssh }
        guard #available(macOS 15.0, *) else { return ssh }
        guard let client = try? await AgentConnection.client(deployment: deployment, runner: runner)
        else { return ssh }
        return AgentAutoBackupOperations(client: client, gate: agentGate)
    }

    /// The seam for the admin-guard toggle
    private func lockdownSeam() async throws -> any AdminLockdownManaging {
        let runner = try await session()
        let ssh = SSHAdminLockdown(runner: runner, config: config, host: servicesHost)
        guard LockdownRouting.route(usesAgent: deployment.usesAgent,
                                    agentTransportAvailable: Self.agentTransportAvailable) == .agent else { return ssh }
        guard #available(macOS 15.0, *) else { return ssh }
        guard let client = try? await AgentConnection.client(deployment: deployment, runner: runner)
        else { return ssh }
        return AgentAdminLockdown(client: client, gate: agentGate)
    }

    /// The seam for removing ONE service
    private func removalManaging(for service: any ManagedService) async throws -> any ServiceRemovalManaging {
        let runner = try await session()
        let ssh = SSHServiceRemoval(runner: runner, deployment: deployment)
        let route = ServiceRemovalRouting.route(scope: .service, usesAgent: deployment.usesAgent,
                                                agentTransportAvailable: Self.agentTransportAvailable)
        guard route == .agent, AgentServiceMapping.agentID(for: service.id) != nil else { return ssh }
        guard #available(macOS 15.0, *) else { return ssh }
        guard let client = try? await AgentConnection.client(deployment: deployment, runner: runner,
                                                             host: agentHost(for: service.id))
        else { return ssh }
        return AgentServiceRemoval(client: client, gate: agentGate)
    }

    private func refreshHostSurfaceAfterRemoval(of service: any ManagedService) async -> String? {
        guard ServiceRemovalRouting.route(scope: .service, usesAgent: deployment.usesAgent,
                                          agentTransportAvailable: Self.agentTransportAvailable) == .agent,
              AgentServiceMapping.agentID(for: service.id) != nil else { return nil }
        guard #available(macOS 15.0, *) else { return nil }
        do {
            let runner = try await session()
            guard let client = try? await AgentConnection.client(deployment: deployment, runner: runner)
            else { return nil }
            let key = await Self.devicePublicKey(for: deployment)
            try await AgentInstallOperations(client: client, gate: agentGate)
                .provisionHost(Self.agentHostSurfaceContext(for: deployment, devicePublicKey: key))
            return nil
        } catch {
            return UIL10n.string(
                "Could not refresh the host's management scripts after removing %@: %@",
                service.displayName, Self.message(for: error))
        }
    }

    static func devicePublicKey(for deployment: Deployment) async -> String {
        let deploymentID = deployment.id
        return await Task.detached(priority: .userInitiated) {
            (try? KeychainSSHIdentityStore(deploymentID: deploymentID).loadOrGenerate().publicKeyOpenSSH) ?? ""
        }.value
    }

    static func agentHostSurfaceContext(for deployment: Deployment,
                                                devicePublicKey: String = "",
                                                role: Gryonixnexusd_V1_HostRole? = nil) -> AgentInstallContext {
        let role = role ?? (deployment.hasRelayIngress ? .homeBackend : .singleHost)
        return AgentInstallContext(domain: deployment.domain,
                                   additionalDomains: deployment.additionalDomains,
                                   localOnly: deployment.scope.usesInternalTLS,
                                   adminUsername: deployment.serviceSettings.adminUsername,
                                   language: ContentLanguageSetting.current,
                                   settings: AgentInstallSettings.map(from: deployment.serviceSettings),
                                   host: hostSurface(for: deployment, role: role, devicePublicKey: devicePublicKey))
    }

    /// The host surface, topology included
    static func hostSurface(for deployment: Deployment,
                                    role: Gryonixnexusd_V1_HostRole,
                                    devicePublicKey: String) -> AgentHostSurface {
        guard deployment.hasRelayIngress else {
            return AgentHostSurface(role: role, dashboardPublicKey: devicePublicKey)
        }
        let context = deployment.serviceContext
        let services = deployment.servicesBehindRelay
        return AgentHostSurface(
            role: role,
            ptrIP: deployment.entry.host,
            tunnelEndpoint: "\(deployment.entry.host):\(WireGuardDefaults.listenPort)",
            relayWGPort: UInt32(WireGuardDefaults.listenPort),
            relayForwardedPorts: ForwardedPorts.tcp(services: services, context: context).map { UInt32($0) },
            relayForwardedUDPPorts: ForwardedPorts.udp(services: services, context: context).map { UInt32($0) },
            homeWGAddress: deployment.homeWGAddress ?? "",
            dashboardPublicKey: devicePublicKey)
    }

    /// Whether this machine has a WireGuard interface worth reading
    func showsWireGuard(_ node: DeploymentNode) -> Bool {
        deployment.hasRelayIngress && node.legacySlot != nil
    }

    /// The name a machine's install report is filed under
    static func installReportKey(for node: DeploymentNode, in deployment: Deployment) -> String {
        switch node.legacySlot {
        case .vps: return deployment.hasRelayIngress ? "vps" : "single"
        case .home: return "home"
        case nil: return node.id.uuidString
        }
    }

    /// Can this deployment's RELAY be configured from here?
    var canProvisionRelay: Bool {
        guard #available(macOS 15.0, *) else { return false }
        return deployment.usesAgent && deployment.hasRelayIngress && Self.agentTransportAvailable
    }

    func provisionRelay() async {
        guard #available(macOS 15.0, *) else { return }
        let operation = LongOperationState(
            title: UIL10n.string("Configuring the relay"),
            progressText: UIL10n.string("Writing the relay's firewall and management scripts…"))
        present(operation)
        do {
            for note in try await reprovisionRelay() {
                operation.log += operation.log.isEmpty ? note : "\n" + note
            }
            operation.progressText = UIL10n.string("The relay is configured.")
        } catch {
            operation.errorMessage = Self.message(for: error)
        }
        operation.isFinished = true
    }

    /// Rewrites the relay's firewall and scripts; returns its notes
    @available(macOS 15.0, *)
    func reprovisionRelay() async throws -> [String] {
        let runner = try await session()
        let key = await Self.devicePublicKey(for: deployment)
        let client = try await AgentConnection.client(deployment: deployment, runner: runner, host: .vps)
        let response = try await AgentInstallOperations(client: client, gate: agentGate)
            .provisionHost(Self.agentHostSurfaceContext(for: deployment, devicePublicKey: key,
                                                        role: .vpsRelay))
        return response.notes
    }

    // MARK: - Dynamic DNS

    @Published var dynamicDNS: Gryonixnexusd_V1_DynamicDNSState?

    /// Can this server keep its own records current?
    var canManageDynamicDNS: Bool {
        guard #available(macOS 15.0, *) else { return false }
        return deployment.usesAgent && Self.agentTransportAvailable
    }

    /// Read the current setting and the host's recent runs
    func loadDynamicDNS() async {
        guard #available(macOS 15.0, *) else { return }
        do {
            dynamicDNS = try await dynamicDNSOperations().state()
        } catch {
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
        }
    }

    func setDynamicDNS(zone: String, names: [String], token: String) async {
        guard #available(macOS 15.0, *) else { return }
        do {
            let operations = try await dynamicDNSOperations()
            dynamicDNS = names.isEmpty
                ? try await operations.disable()
                : try await operations.enable(zone: zone, names: names, token: token)
            quickActionResult = QuickActionResult(
                message: names.isEmpty
                    ? UIL10n.string("This server no longer updates its own DNS records.")
                    : UIL10n.string("This server now keeps its DNS records pointing at its address."),
                isError: false)
        } catch {
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
        }
    }

    /// Health alerts go through the same agent connection
    var canManageNotifications: Bool { canManageDynamicDNS }

    @available(macOS 15.0, *)
    func notifyOperations() async throws -> AgentNotifyOperations {
        let runner = try await session()
        let client = try await AgentConnection.client(deployment: deployment, runner: runner)
        return AgentNotifyOperations(client: client, gate: agentGate)
    }

    @available(macOS 15.0, *)
    private func dynamicDNSOperations() async throws -> AgentDynamicDNSOperations {
        let runner = try await session()
        let client = try await AgentConnection.client(deployment: deployment, runner: runner)
        return AgentDynamicDNSOperations(client: client, gate: agentGate)
    }

    @Published var securityStatus: HostSecurityStatus?

    /// A read is on its way
    @Published var isReadingSecurity = false

    /// When the CrowdSec status last came from the host
    private var securityReadAt: Date?

    /// Whether the Security card is shown at all
    var canShowSecurity: Bool {
        guard #available(macOS 15.0, *) else { return false }
        return deployment.usesAgent && Self.agentTransportAvailable
    }

    /// Read the host's CrowdSec status
    func loadSecurity() async {
        guard #available(macOS 15.0, *), canShowSecurity else { return }
        isReadingSecurity = true
        defer { isReadingSecurity = false }
        do {
            securityStatus = try await onLiveSession { try await securityOperations().status() }
            securityReadAt = Date()
        } catch {
            securityStatus = .unknown
            securityReadAt = nil
            sessionMaybeStale = true
        }
        publishFleetStateToWidgets()
    }

    /// Re-read only when the answer is missing, failed or old
    func loadSecurityIfStale(maxAge: TimeInterval = DashboardViewModel.securityFreshness) async {
        guard !isReadingSecurity else { return }
        if let readAt = securityReadAt, securityStatus?.isKnown == true,
           Date().timeIntervalSince(readAt) < maxAge { return }
        await loadSecurity()
    }

    /// Re-read every part of the Security section at once
    func refreshSecuritySection() async {
        async let crowdSec: Void = loadSecurity()
        async let ssh: Void = loadSSHPasswordAccess()
        async let lockdown: Void = refreshAdminLockdownIfPresent()
        _ = await (crowdSec, ssh, lockdown)
    }

    private func refreshAdminLockdownIfPresent() async {
        guard hasAdminLockdown else { return }
        await refreshAdminLockdown()
    }

    /// Any part of the Security section is being read
    var isReadingSecuritySection: Bool {
        isReadingSecurity || isReadingSSHPasswordAccess
            || (hasAdminLockdown && adminLockdown.isLoading)
    }

    /// How long an answer is trusted
    nonisolated static let securityFreshness: TimeInterval = 45

    @available(macOS 15.0, *)
    private func securityOperations() async throws -> AgentSecurityOperations {
        let runner = try await session()
        let client = try await AgentConnection.client(deployment: deployment, runner: runner)
        return AgentSecurityOperations(client: client, gate: agentGate)
    }

    @Published var runningSecurityAction: AgentSecurityOperations.Action?

    /// The last line the running action printed
    @Published var securityActionProgress = ""

    /// What went wrong, in the host's own words
    @Published var securityActionFailure = ""

    func runSecurityAction(_ action: AgentSecurityOperations.Action) async {
        guard #available(macOS 15.0, *), canShowSecurity else { return }
        guard runningSecurityAction == nil else { return }
        runningSecurityAction = action
        securityActionProgress = ""
        securityActionFailure = ""
        defer { runningSecurityAction = nil; securityActionProgress = "" }
        do {
            let operations = try await securityOperations()
            for try await progress in operations.control(action) {
                switch progress {
                case .line(let text): securityActionProgress = text
                case .finished(let status): securityStatus = status
                }
            }
        } catch {
            securityActionFailure = error.localizedDescription
            await loadSecurity()
        }
        publishFleetStateToWidgets()
    }

    // MARK: - Blocked addresses and the allowlist

    /// Who the host is blocking right now
    @Published var securityDecisions: HostSecurityDecisions?
    /// The addresses this host will never ban
    @Published var securityAllowlist: HostSecurityAllowlist?
    @Published var securityListFailure = ""
    @Published var securityListBusy = false

    /// Read both lists
    func loadSecurityLists() async {
        guard #available(macOS 15.0, *), canShowSecurity else { return }
        do {
            let lists = try await onLiveSession { () -> (HostSecurityDecisions, HostSecurityAllowlist) in
                let operations = try await securityOperations()
                return (try await operations.decisions(), try await operations.allowlist())
            }
            securityDecisions = lists.0
            securityAllowlist = lists.1
        } catch {
            securityDecisions = .unknown
            securityAllowlist = .unknown
            sessionMaybeStale = true
        }
    }

    /// Lift a ban, or add one by hand
    func setBan(_ banned: Bool, value: String, decisionID: String = "",
                duration: TimeInterval = 0, reason: String = "") async {
        guard #available(macOS 15.0, *), canShowSecurity, !securityListBusy else { return }
        securityListBusy = true
        securityListFailure = ""
        defer { securityListBusy = false }
        do {
            securityDecisions = try await onLiveSession {
                try await securityOperations()
                    .setBan(banned, value: value, decisionID: decisionID,
                            duration: duration, reason: reason)
            }
        } catch {
            securityListFailure = error.localizedDescription
            await loadSecurityLists()
        }
        await loadSecurity()
    }

    /// Put an address beyond banning, or stop protecting it
    func setAllowed(_ allowed: Bool, value: String, comment: String = "",
                    duration: TimeInterval = 0) async {
        guard #available(macOS 15.0, *), canShowSecurity, !securityListBusy else { return }
        securityListBusy = true
        securityListFailure = ""
        defer { securityListBusy = false }
        do {
            securityAllowlist = try await onLiveSession {
                try await securityOperations()
                    .setAllowed(allowed, value: value, comment: comment, duration: duration)
            }
            if let operations = try? await securityOperations() {
                securityDecisions = try? await operations.decisions()
            }
        } catch {
            securityListFailure = error.localizedDescription
            await loadSecurityLists()
        }
        await loadSecurity()
    }

    @Published var sshPasswordAccess: SSHPasswordAccess?

    @Published var isChangingSSHPassword = false

    /// A read is on its way
    @Published var isReadingSSHPasswordAccess = false

    /// When the host last said what its SSH accepts
    private var sshPasswordAccessReadAt: Date?

    var sshLoginUser: String { deployment.dashboardConfig.sshUser }

    /// Read what the host accepts
    func loadSSHPasswordAccess() async {
        guard #available(macOS 15.0, *), canShowSecurity else { return }
        let key = await Self.devicePublicKey(for: deployment)
        guard !key.isEmpty || DemoFleet.covers(deployment) else {
            sshPasswordAccess = .unknown
            sshPasswordAccessReadAt = nil
            return
        }
        isReadingSSHPasswordAccess = true
        defer { isReadingSSHPasswordAccess = false }
        do {
            sshPasswordAccess = try await onLiveSession {
                try await securityOperations()
                    .sshPasswordAccess(loginUser: sshLoginUser, appPublicKey: key)
            }
            sshPasswordAccessReadAt = Date()
            await readAccountsWhenTheHostReadsOpen()
        } catch {
            sshPasswordAccess = .unknown
            sshPasswordAccessReadAt = nil
            sessionMaybeStale = true
        }
    }

    @Published var sshUsers: SSHUsers?

    /// A read or a change is on its way
    @Published var isWorkingOnSSHUsers = false

    /// Every account on this host and what its SSH accepts
    func loadSSHUsers() async {
        guard #available(macOS 15.0, *), canShowSecurity else { return }
        let key = await Self.devicePublicKey(for: deployment)
        isWorkingOnSSHUsers = true
        defer { isWorkingOnSSHUsers = false }
        do {
            sshUsers = try await onLiveSession {
                try await securityOperations().sshUsers(loginUser: sshLoginUser, appPublicKey: key)
            }
            adoptHostAccessFromUsers()
        } catch {
            sshUsers = .unknown
            sessionMaybeStale = true
        }
    }

    /// Key login only: everyone, some, or none
    func setKeyOnlySSHUsers(everyone: Bool, users: [String]) async {
        guard #available(macOS 15.0, *), canShowSecurity, !isWorkingOnSSHUsers else { return }
        let key = await Self.devicePublicKey(for: deployment)
        isWorkingOnSSHUsers = true
        defer { isWorkingOnSSHUsers = false }
        do {
            sshUsers = try await onLiveSession {
                try await securityOperations()
                    .setKeyOnlyUsers(everyone: everyone, users: users,
                                     loginUser: sshLoginUser, appPublicKey: key)
            }
            adoptHostAccessFromUsers()
        } catch {
            sessionMaybeStale = true
            failed(Self.message(for: error))
        }
    }

    /// The host-wide read cannot see a `Match User` block
    private func readAccountsWhenTheHostReadsOpen() async {
        guard sshPasswordAccess?.isOpen == true, !isWorkingOnSSHUsers else { return }
        await loadSSHUsers()
    }

    /// The accounts that still take passwords
    var openSSHAccountNames: String? {
        guard let answer = sshUsers, answer.isKnown else { return nil }
        let open = answer.users.filter { $0.isKnown && $0.passwordLoginOpen }.map(\.name)
        return open.isEmpty ? nil : open.joined(separator: ", ")
    }

    /// The accounts' answer becomes the host row's
    private func adoptHostAccessFromUsers() {
        guard let answer = sshUsers, answer.host.isKnown else { return }
        sshPasswordAccess = answer.hostAccess
        sshPasswordAccessReadAt = Date()
    }

    /// Re-read only when the answer is missing, failed or old
    func loadSSHPasswordAccessIfStale(maxAge: TimeInterval = DashboardViewModel.securityFreshness) async {
        guard !isReadingSSHPasswordAccess, !isChangingSSHPassword else { return }
        if let readAt = sshPasswordAccessReadAt, sshPasswordAccess?.isKnown == true,
           Date().timeIntervalSince(readAt) < maxAge { return }
        await loadSSHPasswordAccess()
    }

    func setSSHPasswordLogin(open: Bool) async {
        guard #available(macOS 15.0, *), canShowSecurity else { return }
        let key = await Self.devicePublicKey(for: deployment)
        guard !key.isEmpty || DemoFleet.covers(deployment) else {
            failed(UIL10n.string("Could not read this server's key from the Keychain."))
            return
        }
        isChangingSSHPassword = true
        defer { isChangingSSHPassword = false }
        do {
            sshPasswordAccess = try await onLiveSession {
                try await securityOperations()
                    .setSSHPasswordLogin(open: open, loginUser: sshLoginUser, appPublicKey: key)
            }
        } catch {
            sessionMaybeStale = true
            failed(Self.message(for: error))
        }
    }

    @discardableResult
    func grantAppKeyToLoginAccount() async -> Bool {
        let key = await Self.devicePublicKey(for: deployment)
        guard !key.isEmpty || DemoFleet.covers(deployment) else {
            failed(UIL10n.string("Could not read this server's key from the Keychain."))
            return false
        }
        isChangingSSHPassword = true
        defer { isChangingSSHPassword = false }
        do {
            let runner = try await session()
            let result = try await runner.run(AccessGrantCommand.command(publicKey: key),
                                              on: servicesHost,
                                              timeout: deployment.dashboardConfig.quickTimeout)
            guard result.stdout.contains(AccessGrantCommand.marker) else {
                failed(UIL10n.string(
                    "The server did not confirm the key was added. %@",
                    result.stderr.isEmpty ? result.stdout : result.stderr))
                return false
            }
            if deployment.usesPasswordAuth {
                guard try await keySignInWorks() else {
                    failed(UIL10n.string(
                        "The key was added, but signing in with it did not work — this server is still using the password. Check that the account it authorized is %@.",
                        sshLoginUser))
                    return false
                }
                var next = deployment
                next.usesPasswordAuth = false
                deployment = next
                onDeploymentCorrected?(next)
                invalidateSession()
            }
        } catch {
            sessionMaybeStale = true
            failed(Self.message(for: error))
            return false
        }
        await loadSSHPasswordAccess()
        return true
    }

    private func failed(_ message: String) {
        quickActionResult = QuickActionResult(message: message, isError: true)
    }

    private func keySignInWorks() async throws -> Bool {
        var keyOnly = deployment
        keyOnly.usesPasswordAuth = false
        let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: keyOnly,
                                                                          shared: false)
        defer { Task { await runner.disconnect() } }
        let result = try await runner.run("echo GRYONIXNEXUS_PING", on: servicesHost,
                                          timeout: deployment.dashboardConfig.quickTimeout)
        return result.stdout.contains("GRYONIXNEXUS_PING")
    }

    @Published var agentVersion: String?

    @discardableResult
    func installAgent(reinstall: Bool = false) async -> Deployment? {
        guard await sudoIsReady() else { return nil }
        let operation = LongOperationState(
            title: reinstall ? UIL10n.string("Reinstalling the agent") : UIL10n.string("Installing the agent"),
            progressText: UIL10n.string("Sending the agent sources…"))
        present(operation)
        do {
            let runner = try await session()
            guard let transfer = runner as? (any SSHCommandRunner & RemoteFileBrowser) else {
                throw ServerControlError.notConfigured(
                    UIL10n.string("This server is not managed over a real connection."))
            }
            let build = AgentBuildProgress(state: operation)
            let others = deployment.agentHosts.filter { $0 != servicesHost }
            let target = self.deployment
            async let relays: Void = withThrowingTaskGroup(of: Void.self) { group in
                for host in others {
                    group.addTask { @MainActor in
                        try await AgentUpdateOffer.install(on: host, named: Self.hostDisplayName(host, in: target),
                                                           runner: transfer, state: operation, reinstall: reinstall)
                    }
                }
                try await group.waitForAll()
            }
            try await AgentBootstrapOperations.install(
                runner: transfer, host: servicesHost, source: Self.chosenAgentSource, reinstall: reinstall,
                onPhase: { phase in
                    Task { @MainActor in operation.progressText = phase }
                },
                onOutput: { line in
                    Task { @MainActor in
                        operation.log = OutputTail.tail(ANSIStripper.strip(operation.log + line + "\n"), maxCharacters: OutputTail.logCharacters)
                        build.line(line)
                    }
                })
            try await relays
            var updated: Deployment?
            do {
                let version = try await probeAgentVersion()
                agentVersion = version
                if !deployment.usesAgent {
                    var next = deployment
                    next.usesAgent = true
                    deployment = next
                    updated = next
                }
                operation.progress = 1
                operation.progressText = UIL10n.string("The agent %@ is installed.", version)
            } catch {
                operation.errorMessage = UIL10n.string(
                    "The agent was installed but is not answering: %@",
                    error.localizedDescription)
            }
            operation.isFinished = true
            return updated
        } catch {
            operation.errorMessage = error.localizedDescription
            operation.isFinished = true
        }
        return nil
    }

    struct SudoPrompt: Identifiable, Equatable {
        let id = UUID()
        let username: String
        let note: String?
    }

    @Published var sudoPrompt: SudoPrompt?
    private var sudoAnswer: CheckedContinuation<String?, Never>?

    /// Asks the sign-in's password once when sudo needs it
    private func sudoIsReady() async -> Bool {
        guard !DemoServer.isDemo(deployment) else { return true }
        do {
            let runner = try await session()
            guard let transfer = runner as? (any SSHCommandRunner & RemoteFileBrowser) else { return true }
            let probe = try await transfer.run(
                SudoAccess.probeCommand(allowing: AgentBootstrapSections.scriptPath),
                on: servicesHost, timeout: deployment.dashboardConfig.quickTimeout)
            if SudoAccess.isReady(probe.stdout) { return true }
            if SudoAccess.passwordIsLocked(probe.stdout) {
                failed(UIL10n.string("%@ has no password: the app locked it when it set up this server, so no password can unlock sudo for it. Install the agent while signed in as root or as an account with sudo.",
                                     deployment.entry.user))
                return false
            }
            return try await grantSudo(runner: transfer)
        } catch {
            failed(Self.message(for: error))
            return false
        }
    }

    private func grantSudo(runner: any SSHCommandRunner & RemoteFileBrowser) async throws -> Bool {
        var note: String?
        while let password = await askSudoPassword(note: note) {
            switch try await SudoAccess.grant(password: password, runner: runner, host: servicesHost) {
            case .granted:
                return true
            case .wrongPassword:
                note = UIL10n.string("Wrong password. Try again.")
            case .notAllowed:
                failed(UIL10n.string("This account may not act as administrator on the server. Sign in as root or as an account that may use sudo."))
                return false
            case .failed(let detail):
                note = UIL10n.string("Could not set up administrator access: %@", detail)
            }
        }
        return false
    }

    private func askSudoPassword(note: String?) async -> String? {
        await withCheckedContinuation { continuation in
            sudoAnswer = continuation
            sudoPrompt = SudoPrompt(username: deployment.entry.user, note: note)
        }
    }

    func answerSudoPrompt(_ password: String?) {
        guard let answer = sudoAnswer else { return }
        sudoAnswer = nil
        sudoPrompt = nil
        answer.resume(returning: password)
    }

    private func probeAgentVersion() async throws -> String {
        guard Self.agentTransportAvailable, #available(macOS 15.0, *) else {
            throw ServerControlError.notConfigured(
                UIL10n.string("This version of the app cannot manage servers over the panel's own connection."))
        }
        let runner = try await session()
        let client = try await AgentConnection.client(deployment: deployment, runner: runner)
        return try await client.getState().agentVersion
    }

    var agentInstallCommand: String {
        let target = "\(deployment.entry.user)@\(deployment.entry.host)"
        let port = deployment.entry.port == 22 ? "" : " -p \(deployment.entry.port)"
        if let branch = Self.chosenAgentSource.branch {
            return "ssh\(port) \(target) 'curl -fsSL "
                + "https://codeload.github.com/\(AgentSource.repository)/tar.gz/refs/heads/\(branch)"
                + " | tar -xz && cd */Agent && bash bootstrap/install-agent.sh'"
        }
        // No rsync dependency — plain tar and ssh instead.
        return "tar -czf - Agent | ssh\(port) \(target) "
            + "'tar -xzf - -C /root && cd /root/Agent && bash bootstrap/install-agent.sh'"
    }

    /// What the last explicit agent check found
    enum AgentCheck: Equatable {
        case installed(version: String)
        case installedUnknownVersion
        case unreachable(String)
    }

    @Published var agentCheck: AgentCheck?
    @Published var isCheckingAgent = false
    @Published var agentUpdateOffer: String?

    var bundledAgentVersion: String { AgentBootstrapOperations.shippedVersion }

    /// What the agent section's picker is set to
    static var chosenAgentSource: AgentSource {
        AgentSource.named(UserDefaults.standard.string(forKey: "agent.source") ?? "")
    }

    @discardableResult
    func checkAgent() async -> Deployment? {
        isCheckingAgent = true
        defer { isCheckingAgent = false }
        agentUpdateOffer = nil
        do {
            let version = try await probeAgentVersion()
            agentVersion = version.isEmpty ? nil : version
            agentCheck = version.isEmpty ? .installedUnknownVersion : .installed(version: version)
            if AgentVersion.isNewer(bundledAgentVersion, than: version) {
                agentUpdateOffer = version
            }
            guard !deployment.usesAgent else { return nil }
            var next = deployment
            next.usesAgent = true
            deployment = next
            return next
        } catch {
            agentCheck = .unreachable(Self.message(for: error))
            return nil
        }
    }

    func loadAgentVersion() async {
        guard deployment.usesAgent, Self.agentTransportAvailable else { return }
        guard #available(macOS 15.0, *) else { return }
        do {
            let runner = try await session()
            guard let client = try? await AgentConnection.client(deployment: deployment, runner: runner)
            else { return }
            let state = try await client.getState()
            agentVersion = state.agentVersion
            homeDoors = Dictionary(state.homeDoors.map { ($0.serviceID, Int($0.port)) }) { first, _ in first }
            meshAddress = state.meshAddress.isEmpty ? nil : state.meshAddress
        } catch {
            agentVersion = nil
        }
    }

    /// Plain HTTP ports apps use at home, by service id
    @Published var homeDoors: [String: Int] = [:]

    /// A wake-up is being sent
    @Published var wakingUp = false
    /// Whether the network card wakes the machine, per the agent
    @Published var wakeSupport: Gryonixnexusd_V1_WakeSupport = .unknown

    /// This server's address in the Tailscale mesh
    @Published var meshAddress: String?

    /// The address apps use at home for one service
    func homeDoorURL(for serviceID: String) -> String? {
        guard let port = homeDoors[serviceID] else { return nil }
        let host = deployment.nodes.first { $0.sshHost == deployment.servicesHost }?.endpoint.host ?? deployment.entry.host
        let bracketed = host.contains(":") ? "[\(host)]" : host
        return "http://\(bracketed):\(port)"
    }

    /// The same door reached through the VPN
    func meshDoorURL(for serviceID: String) -> String? {
        guard let port = homeDoors[serviceID], let meshAddress else { return nil }
        return "http://\(meshAddress):\(port)"
    }

    // MARK: Agent self-update

    @Published var selfUpdateStatus: Gryonixnexusd_V1_AgentUpdateStatus?
    @Published var isApplyingSelfUpdate = false
    @Published var selfUpdateProgress: String?
    @Published var selfUpdateError: String?

    func loadSelfUpdateStatus() async {
        guard deployment.usesAgent, Self.agentTransportAvailable else { return }
        guard #available(macOS 15.0, *) else { return }
        do {
            let runner = try await session()
            guard let client = try? await AgentConnection.client(deployment: deployment, runner: runner)
            else { return }
            selfUpdateStatus = try await client.getAgentUpdateStatus()
        } catch {
            selfUpdateStatus = nil
        }
    }

    func applySelfUpdate() async {
        guard #available(macOS 15.0, *) else { return }
        isApplyingSelfUpdate = true
        selfUpdateError = nil
        selfUpdateProgress = UIL10n.string("Starting…")
        let island = IslandRun(title: UIL10n.string("Updating the agent"), serverName: deployment.name,
                               progressText: selfUpdateProgress ?? "", deployment: deployment)
        defer {
            isApplyingSelfUpdate = false
            island.finish(selfUpdateError == nil ? UIL10n.string("The agent is updated.") : "",
                          error: selfUpdateError)
        }
        var heardFromAgent = false
        do {
            let runner = try await session()
            let client = try await AgentConnection.client(deployment: deployment, runner: runner)
            for try await event in client.applyAgentUpdate() {
                heardFromAgent = true
                if !event.text.isEmpty {
                    selfUpdateProgress = event.text
                    island.update(event.text)
                }
                if event.phase == .failed {
                    selfUpdateError = event.reason.isEmpty ? UIL10n.string("The update failed.") : event.reason
                    return
                }
            }
        } catch {
            if !heardFromAgent {
                selfUpdateError = DashboardViewModel.message(for: error)
                return
            }
        }
        selfUpdateProgress = UIL10n.string("The agent is restarting…")
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        await loadSelfUpdateStatus()
        if selfUpdateStatus == nil {
            selfUpdateError = UIL10n.string("The agent did not answer after restarting.")
        } else if selfUpdateStatus?.lastApplySucceeded == false {
            selfUpdateError = selfUpdateStatus?.lastApplyReason
        }
    }

    /// Can this server take another service without being reinstalled?
    var canAddServices: Bool {
        guard Self.agentTransportAvailable else { return false }
        if #available(macOS 15.0, *) { return true }
        return false
    }

    /// Installs the agent if missing, then new services together
    func addServices(_ services: [any ManagedService]) async -> Deployment? {
        var latest: Deployment?
        if !deployment.usesAgent {
            latest = await installAgent()
            guard deployment.usesAgent else { return latest }
        }
        let steps = ServiceInstallPlan.steps(for: services, installed: deployment.services)
        if steps.count == 1, let only = steps.first {
            return await installService(only.service, alsoProtocols: only.alsoProtocols) ?? latest
        }
        guard !steps.isEmpty, !refusesPendingInstall(steps.map(\.service)) else { return latest }
        return await runStepsOnTheirMachines(steps) ?? latest
    }

    /// Runs each step on the machine of its service
    private func runStepsOnTheirMachines(_ steps: [ServiceInstallPlan.Step], title: String? = nil,
                                         purpose: AgentPlanPurpose = .add) async -> Deployment? {
        let (vpn, rest) = Self.splitForRelay(steps, vpnOnRelay: deployment.vpnRunsOnRelay)
        var latest: Deployment?
        if !rest.isEmpty { latest = await runInstallSteps(rest, title: title, purpose: purpose) }
        if !vpn.isEmpty { latest = await runInstallSteps(vpn, title: title, purpose: purpose, on: .vpn) ?? latest }
        return latest
    }

    /// VPN steps apart, when the VPN is on the relay
    static func splitForRelay(_ steps: [ServiceInstallPlan.Step],
                              vpnOnRelay: Bool) -> (vpn: [ServiceInstallPlan.Step], rest: [ServiceInstallPlan.Step]) {
        guard vpnOnRelay else { return ([], steps) }
        let vpn = steps.filter { ServiceID.vpnFamily.contains($0.service.id) }
        return (vpn, steps.filter { !ServiceID.vpnFamily.contains($0.service.id) })
    }

    /// Every installed service again through the agent, then the relay
    func rerunServices(repair: Bool) async -> Deployment? {
        let steps = ServiceInstallPlan.rerun(deployment.installedServices)
        guard !steps.isEmpty, !refusesPendingInstall(steps.map(\.service)) else { return nil }
        let title = UIL10n.string(repair ? "Repairing %@" : "Reinstalling %@", deployment.name)
        let updated = await runStepsOnTheirMachines(steps, title: title, purpose: repair ? .repair : .reinstall)
        if deployment.hasRelayIngress, #available(macOS 15.0, *) {
            _ = try? await reprovisionRelay()
        }
        return updated
    }

    /// The agent installs the whole list; the app only follows
    private func runInstallSteps(_ steps: [ServiceInstallPlan.Step], title: String? = nil,
                                 purpose: AgentPlanPurpose = .add,
                                 on machine: PlanMachine = .services) async -> Deployment? {
        let queuedIDs = steps.flatMap { [$0.service.id] + $0.alsoProtocols }
        installingNow.formUnion(queuedIDs)
        defer { installingNow.subtract(queuedIDs) }
        let operation = LongOperationState(title: title ?? Self.planTitle(.add, steps: steps, server: deployment.name),
                                           progressText: UIL10n.string("Preparing the server…"))
        present(operation)
        var latest: Deployment?
        do {
            guard #available(macOS 15.0, *) else { throw CancellationError() }
            let installer = try await installOperations(for: machine == .vpn ? .vpnPanel : nil)
            let (planned, requests) = try await planRequests(for: steps, operation: operation)
            deployment.serviceSettings = planned.serviceSettings
            onDeploymentCorrected?(deployment)
            let follower = planFollower(installer, operation: operation, purpose: purpose)
            let started = try await follower.start(requests)
            AgentPlanRecord.remember(planID: started.id, steps: steps, deployment: deployment.id, purpose: purpose)
            LiveActivityJobs.shared.jobStarted(started.id, on: deployment.id)
            let plan = try await followThroughDisconnects(follower, from: started, operation: operation,
                                                          machine: machine)
            latest = await recordPlan(plan, steps: steps, operation: operation)
        } catch {
            operation.errorMessage = Self.message(for: error)
        }
        operation.isFinished = true
        return latest
    }

    /// Which machine a plan runs on
    enum PlanMachine { case services, vpn }

    /// What a plan's window is called
    static func planTitle(_ purpose: AgentPlanPurpose, steps: [ServiceInstallPlan.Step], server: String) -> String {
        switch purpose {
        case .repair: UIL10n.string("Repairing %@", server)
        case .reinstall: UIL10n.string("Reinstalling %@", server)
        case .add, .setup: UIL10n.string("Installing %@", steps.flatMap(\.displayNames).joined(separator: ", "))
        }
    }

    /// Keeps following through sleep and dropped lines
    @available(macOS 15.0, *)
    private func followThroughDisconnects(_ first: InstallPlanFollower, from started: AgentInstallPlan,
                                          operation: LongOperationState,
                                          machine: PlanMachine = .services) async throws -> AgentInstallPlan {
        var follower = first
        var dropsWhileOpen = 0
        while true {
            do {
                return try await follower.follow(started)
            } catch where Self.isLostConnection(error) {
                let wasAway = !RunningJobsWatcher.shared.isAppActive
                operation.progressText = UIL10n.string("The server keeps working. Open the app to follow it.")
                await RunningJobsWatcher.shared.untilActive()
                dropsWhileOpen += wasAway ? 0 : 1
                guard dropsWhileOpen <= Self.reconnectAttempts else { throw error }
                operation.progressText = UIL10n.string("Reattaching…")
                try await Task.sleep(for: .seconds(2))
                invalidateSession()
                follower.installer = try await installOperations(for: machine == .vpn ? .vpnPanel : nil)
            }
        }
    }

    /// Reconnects tried while the app stays open
    private static let reconnectAttempts = 3

    /// Each step's install request, hostnames pinned one after another
    private func planRequests(for steps: [ServiceInstallPlan.Step], operation: LongOperationState) async throws
        -> (Deployment, [(ServiceID, AgentInstallContext)]) {
        var planned = deployment
        var requests: [(ServiceID, AgentInstallContext)] = []
        let key = await Self.devicePublicKey(for: deployment)
        let onHost = await hostVPNProtocols()
        for step in steps {
            let service = step.service
            planned.serviceSettings = ServiceDefaultHostnames.pinningSiblings(
                adding: service.id, to: planned.serviceSettings,
                installed: planned.services, domain: planned.domain)
            planned.services.insert(service.id)
            var context = Self.agentHostSurfaceContext(for: planned, devicePublicKey: key,
                                                       role: surfaceRole(for: service.id))
            let installed = planned.services.union(onHost).union(step.alsoProtocols)
            if let protocols = AgentInstallSettings.vpnProtocolList(adding: service.id, installed: installed) {
                context.settings[AgentInstallSettings.vpnProtocolsKey] = protocols
            }
            if service.id == .cloudflared {
                context.settings[AgentInstallSettings.cloudflaredTokenKey] = try await prepareTunnel(operation: operation)
            }
            requests.append((service.id, context))
        }
        return (planned, requests)
    }

    @available(macOS 15.0, *)
    private func planFollower(_ installer: AgentInstallOperations, operation: LongOperationState,
                              purpose: AgentPlanPurpose) -> InstallPlanFollower {
        InstallPlanFollower(
            installer: installer,
            purpose: purpose,
            onStage: { operation.progressText = $0 },
            onProgress: { settled, total in operation.progress = total == 0 ? nil : Double(settled) / Double(total) },
            onChunk: { chunk in
                Task { @MainActor in
                    operation.log = OutputTail.tail(ANSIStripper.strip(operation.log + chunk),
                                                    maxCharacters: OutputTail.logCharacters)
                }
            },
            onWarning: { _ in })
    }

    /// Records what the plan installed, then DNS and relay
    @available(macOS 15.0, *)
    private func recordPlan(_ plan: AgentInstallPlan, steps: [ServiceInstallPlan.Step],
                            operation: LongOperationState) async -> Deployment? {
        AgentPlanRecord.forget(deployment: deployment.id)
        var latest: Deployment?
        let onHost = await hostVPNProtocols()
        for step in steps where plan.items.contains(where: {
            $0.state == .done && $0.agentServiceID == AgentServiceMapping.agentID(for: step.service.id)
        }) {
            latest = await recordInstalled(step.service, settings: deployment.serviceSettings,
                                           vpnProtocols: onHost.union(step.alsoProtocols), operation: operation)
        }
        if let message = InstallPlanFollower.failureMessage(plan) {
            operation.errorMessage = message
        } else {
            operation.progress = 1
            operation.progressText = UIL10n.string("Installed: %@. Their credentials are in the install report.",
                                                   steps.flatMap(\.displayNames).joined(separator: ", "))
        }
        return latest
    }

    /// Follows a plan the app closed on to its end
    @available(macOS 15.0, *)
    private func resumePlan() async {
        guard let record = AgentPlanRecord.stored(deployment: deployment.id),
              !LiveActivityJobs.shared.isFollowing(record.planID),
              let installer = try? await installOperations() else { return }
        let steps = record.steps
        guard !steps.isEmpty else { return AgentPlanRecord.forget(deployment: deployment.id) }
        let operation = LongOperationState(
            title: Self.planTitle(record.purpose, steps: steps, server: deployment.name),
            progressText: UIL10n.string("Catching up with the server…"))
        present(operation, opensSheet: false)
        LiveActivityJobs.shared.jobStarted(record.planID, on: deployment.id)
        do {
            let current = try await installer.plan(record.planID)
            guard current.id == record.planID else { throw InstallStepFailure(message: InstallPlanFollower.lostMessage) }
            let follower = planFollower(installer, operation: operation, purpose: record.purpose)
            let plan = try await followThroughDisconnects(follower, from: current, operation: operation)
            _ = await recordPlan(plan, steps: steps, operation: operation)
        } catch {
            if !Self.isLostConnection(error) { AgentPlanRecord.forget(deployment: deployment.id) }
            operation.errorMessage = Self.message(for: error)
        }
        operation.isFinished = true
    }

    func installService(_ service: any ManagedService,
                        alsoProtocols: Set<ServiceID> = []) async -> Deployment? {
        guard !refusesPendingInstall([service]) else { return nil }
        let operation = LongOperationState(
            title: UIL10n.string("Installing %@", service.displayName),
            progressText: UIL10n.string("Preparing the server…"))
        present(operation)
        var updated: Deployment?
        do {
            updated = try await performInstall(service, alsoProtocols: alsoProtocols,
                                               operation: operation, isBatch: false)
            operation.progressText = UIL10n.string(
                "%@ is installed. Its credentials are in the install report.", service.displayName)
        } catch is InstallContinuesOnServer {
            operation.progressText = UIL10n.string(
                "Installing on the server. You can close the app — the server carries on, and this screen picks the run back up.")
        } catch {
            operation.errorMessage = Self.message(for: error)
        }
        operation.isFinished = true
        return updated
    }

    /// Re-applies Vaultwarden with registration open or closed
    func setVaultwardenSignups(_ open: Bool) async -> Deployment? {
        var changed = deployment
        changed.serviceSettings.vaultwardenAllowSignups = open
        deployment = changed
        return await installService(VaultwardenService())
    }

    /// Points Reality at another camouflage site; keys and devices stay
    func changeRealitySite(to site: String) async {
        guard site != deployment.serviceSettings.xrayRealitySNI,
              let service = ServiceRegistry.service(.xrayReality) else { return }
        let before = deployment
        deployment.serviceSettings.xrayRealitySNI = site
        guard let updated = await installService(service) else {
            deployment = before
            return
        }
        onDeploymentCorrected?(updated)
    }

    /// Gives Reality a new key pair; devices keep their ids
    func renewRealityKey() async -> Bool {
        guard let service = ServiceRegistry.service(.xrayReality) else { return false }
        oneTimeInstallSettings[AgentInstallSettings.xrayRealityNewKeyKey] = UUID().uuidString
        defer { oneTimeInstallSettings = [:] }
        guard let updated = await installService(service) else { return false }
        onDeploymentCorrected?(updated)
        return true
    }

    /// Says so when one of these is already installing
    private func refusesPendingInstall(_ services: [any ManagedService]) -> Bool {
        guard let busy = services.first(where: {
            PendingAgentInstalls.shared.isPending(deployment: deployment.id, service: $0.id)
        }) else { return false }
        quickActionResult = QuickActionResult(
            message: UIL10n.string(
                "%@ is already installing on this server. Open it from the activity strip to watch it.",
                busy.displayName),
            isError: true)
        return true
    }

    /// One service on the server; VPN protocols travel together
    private func performInstall(_ service: any ManagedService, alsoProtocols: Set<ServiceID>,
                                operation: LongOperationState, isBatch: Bool) async throws -> Deployment {
        let deploymentID = deployment.id
        let finished = [service.id] + alsoProtocols
        installingNow.formUnion(finished)
        defer { installingNow.subtract(finished) }
        do {
            let installed = try await installOnServer(service, alsoProtocols: alsoProtocols,
                                                      operation: operation, isBatch: isBatch)
            forget(finished)
            return installed
        } catch {
            if Self.isLostConnection(error),
               InstallJobStore().job(deployment: deploymentID, service: service.id)?.jobID.isEmpty == false {
                throw InstallContinuesOnServer()
            }
            forget(finished)
            throw error
        }
    }

    /// Installs a moved VPN, rejoining after a dropped connection
    func installForMove(_ anchor: any ManagedService, alsoProtocols: Set<ServiceID>,
                        operation: LongOperationState) async throws {
        let services = [anchor.id] + alsoProtocols
        installingNow.formUnion(services)
        defer { installingNow.subtract(services) }
        let context = await moveContext(for: anchor.id)
        let job = MoveJobID()
        let earlierLog = operation.log
        do {
            let log = try await installOperations(for: anchor.id).install(
                anchor.id, context: context,
                onJobID: { id in Task { @MainActor in job.value = id } },
                onChunk: { chunk in
                    Task { @MainActor in
                        operation.log = OutputTail.tail(ANSIStripper.strip(operation.log + chunk), maxCharacters: OutputTail.logCharacters)
                    }
                })
            operation.log = OutputTail.tail(earlierLog + log, maxCharacters: OutputTail.logCharacters)
        } catch where Self.isLostConnection(error) && !job.value.isEmpty {
            try await rejoin(jobID: job.value, of: anchor, after: earlierLog, operation: operation)
        }
    }

    /// The moved VPN's install request, every protocol at once
    private func moveContext(for anchor: ServiceID) async -> AgentInstallContext {
        var context = Self.agentHostSurfaceContext(
            for: deployment, devicePublicKey: await Self.devicePublicKey(for: deployment),
            role: surfaceRole(for: anchor))
        if let protocols = AgentInstallSettings.vpnProtocolList(adding: anchor, installed: deployment.services) {
            context.settings[AgentInstallSettings.vpnProtocolsKey] = protocols
        }
        return context
    }

    /// Watches a running install again on a fresh session
    private func rejoin(jobID: String, of service: any ManagedService, after earlierLog: String,
                        operation: LongOperationState) async throws {
        var lastError: Error = CancellationError()
        for delay in Self.rejoinDelays {
            try await Task.sleep(for: .seconds(delay))
            operation.log = earlierLog
            do {
                invalidateSession()
                let log = try await installOperations(for: service.id).watch(jobID: jobID, onChunk: { chunk in
                    Task { @MainActor in
                        operation.log = OutputTail.tail(ANSIStripper.strip(operation.log + chunk), maxCharacters: OutputTail.logCharacters)
                    }
                })
                operation.log = OutputTail.tail(earlierLog + log, maxCharacters: OutputTail.logCharacters)
                return
            } catch where Self.isLostConnection(error) {
                lastError = error
            }
        }
        throw lastError
    }

    private static let rejoinDelays = [2, 10, 30, 60]

    private func forget(_ services: [ServiceID]) {
        for id in services { InstallJobStore().forget(deployment: deployment.id, service: id) }
        PendingAgentInstalls.shared.refresh()
    }

    private func forgetQueue(_ steps: [ServiceInstallPlan.Step]) {
        forget(steps.flatMap { [$0.service.id] + $0.alsoProtocols })
    }

    func installOnServer(_ service: any ManagedService, alsoProtocols: Set<ServiceID>,
                                 operation: LongOperationState, isBatch: Bool) async throws -> Deployment {
        let deploymentID = deployment.id
        let installer = try await installOperations(for: service.id)
        var planned = deployment
        planned.serviceSettings = ServiceDefaultHostnames.pinningSiblings(
            adding: service.id, to: deployment.serviceSettings,
            installed: deployment.services, domain: deployment.domain)
        planned.services.insert(service.id)
        var context = Self.agentHostSurfaceContext(
            for: planned, devicePublicKey: await Self.devicePublicKey(for: deployment),
            role: surfaceRole(for: service.id))
        let installedServices = deployment.services.union(await hostVPNProtocols()).union(alsoProtocols)
        if let protocols = AgentInstallSettings.vpnProtocolList(adding: service.id,
                                                               installed: installedServices) {
            context.settings[AgentInstallSettings.vpnProtocolsKey] = protocols
        }
        context.settings.merge(oneTimeInstallSettings) { _, once in once }
        if service.id == .cloudflared {
            context.settings[AgentInstallSettings.cloudflaredTokenKey] =
                try await prepareTunnel(operation: operation)
        }
        let earlierLog = operation.log
        let log = try await installer.install(
            service.id, context: context,
            onJobID: { jobID in
                InstallJobStore().remember(deployment: deploymentID, service: service.id, jobID: jobID)
                Task { @MainActor in PendingAgentInstalls.shared.refresh() }
                guard !isBatch else { return }
                Task { @MainActor in
                    operation.progressText = UIL10n.string(
                        "Installing on the server. You can close the app — the server carries on, and this screen picks the run back up.")
                }
            },
            onChunk: { chunk in
                Task { @MainActor in
                    operation.log = OutputTail.tail(ANSIStripper.strip(operation.log + chunk), maxCharacters: OutputTail.logCharacters)
                }
            })
        operation.log = OutputTail.tail(earlierLog + log, maxCharacters: OutputTail.logCharacters)
        if service.id == .cloudflared {
            await publishTunnelHostnames(operation: operation)
        }
        return await recordInstalled(service, settings: planned.serviceSettings,
                                     vpnProtocols: installedServices, operation: operation)
    }

    /// Records the new service, then updates DNS and relay
    private func recordInstalled(_ service: any ManagedService, settings: ServiceSettings,
                                 vpnProtocols: Set<ServiceID>, operation: LongOperationState) async -> Deployment {
        var deployment = self.deployment
        deployment.serviceSettings = settings
        deployment.services.insert(service.id)
        if ServiceID.vpnProtocols.contains(service.id) {
            deployment.services.insert(.vpnPanel)
            deployment.services.formUnion(vpnProtocols.filter(ServiceID.vpnProtocols.contains))
        }
        let portsChanged = Self.forwardedPorts(of: self.deployment) != Self.forwardedPorts(of: deployment)
        self.deployment = deployment
        await finishAddedService(service, relayPortsChanged: portsChanged, operation: operation)
        return deployment
    }

    /// The ports a relay forwards for this deployment
    static func forwardedPorts(of deployment: Deployment) -> [Int] {
        let services = deployment.servicesBehindRelay
        let context = deployment.serviceContext
        return ForwardedPorts.tcp(services: services, context: context)
            + ForwardedPorts.udp(services: services, context: context).map { -$0 }
    }

    /// DNS names and relay forwards for a newly added service
    private func finishAddedService(_ service: any ManagedService, relayPortsChanged: Bool,
                                    operation: LongOperationState) async {
        let (update, dnsNotes) = await ServiceDNSPublisher.pending(adding: service, to: deployment)
        operation.dnsUpdate = update
        if update != nil { RunningOperationsRegistry.shared.bringUp(operation) }
        var notes = dnsNotes
        if relayPortsChanged, deployment.hasRelayIngress, #available(macOS 15.0, *) {
            do {
                notes += try await reprovisionRelay()
            } catch {
                notes.append(UIL10n.string("Could not update the relay: %@", Self.message(for: error)))
            }
        }
        for note in notes {
            operation.log += operation.log.isEmpty ? note : "\n" + note
        }
        if !notes.isEmpty { operation.notice = notes.joined(separator: "\n") }
    }

    @discardableResult
    func applyMinecraftMods(_ setting: String) async -> Deployment? {
        guard let service = ServiceRegistry.service(.minecraftJava) else { return nil }
        deployment.serviceSettings.minecraftJavaMods = setting
        if var draft = ConfiguratorStore.shared.loadDeploymentConfig(for: deployment.id) {
            draft.minecraftJavaMods = setting
            ConfiguratorStore.shared.saveDeploymentConfig(draft)
        }
        return await installService(service)
    }

    func resumeInstalls() async {
        guard !isResumingInstalls else { return }
        isResumingInstalls = true
        defer { isResumingInstalls = false }
        if #available(macOS 15.0, *) { await resumePlan() }
        let store = InstallJobStore()
        for record in store.jobs(deployment: deployment.id) where !record.jobID.isEmpty
            && !installingNow.contains(ServiceID(rawValue: record.serviceID)) {
            guard let known = ServiceRegistry.service(ServiceID(rawValue: record.serviceID)) else {
                store.forget(deployment: deployment.id, rawService: record.serviceID)
                PendingAgentInstalls.shared.refresh()
                continue
            }
            guard let installer = try? await installOperations(for: known.id) else { return }
            await catchUp(with: known, jobID: record.jobID, installer: installer)
        }
        await continueQueue(store.jobs(deployment: deployment.id).filter { $0.jobID.isEmpty })
    }

    /// Follows one remembered install on its machine to the end
    private func catchUp(with known: any ManagedService, jobID: String,
                         installer: AgentInstallOperations) async {
        let name = known.displayName
        let operation = LongOperationState(
            title: UIL10n.string("Installing %@", name),
            progressText: UIL10n.string("Catching up with the server…"))
        present(operation, opensSheet: false)
        do {
            operation.log = try await installer.watch(jobID: jobID, onChunk: { chunk in
                Task { @MainActor in
                    operation.log = OutputTail.tail(ANSIStripper.strip(operation.log + chunk), maxCharacters: OutputTail.logCharacters)
                }
            })
            let recorded = await recordInstalled(known, settings: deployment.serviceSettings,
                                                 vpnProtocols: [known.id], operation: operation)
            onDeploymentCorrected?(recorded)
            operation.progressText = UIL10n.string(
                "%@ is installed. Its credentials are in the install report.", name)
        } catch {
            operation.errorMessage = Self.message(for: error)
        }
        InstallJobStore().forget(deployment: deployment.id, service: known.id)
        PendingAgentInstalls.shared.refresh()
        operation.isFinished = true
    }

    /// Installs services still waiting in the queue
    private func continueQueue(_ queued: [StoredInstallJob]) async {
        let stale = queued.filter { Date().timeIntervalSince($0.startedAt) > Self.queueLifetime }
        forget(stale.map { ServiceID(rawValue: $0.serviceID) })
        let queued = queued.filter {
            !stale.contains($0) && !installingNow.contains(ServiceID(rawValue: $0.serviceID))
        }
        let services = queued.compactMap { ServiceRegistry.service(ServiceID(rawValue: $0.serviceID)) }
        forget(queued.map { ServiceID(rawValue: $0.serviceID) })
        let steps = ServiceInstallPlan.steps(for: services, installed: deployment.services)
        guard !steps.isEmpty else { return }
        _ = await runInstallSteps(steps)
    }

    private var isResumingInstalls = false
    private var installingNow: Set<ServiceID> = []
    private static let queueLifetime: TimeInterval = 30 * 60

    // MARK: - Cloudflare Tunnel

    private func prepareTunnel(operation: LongOperationState) async throws -> String {
        operation.progressText = UIL10n.string("Preparing the tunnel at Cloudflare…")
        return try await TunnelSetup.connectorToken(for: deployment)
    }

    /// Point every web hostname of this deployment at the tunnel
    private func publishTunnelHostnames(operation: LongOperationState) async {
        do {
            let count = try await TunnelSetup.publishNames(of: deployment)
            operation.progressText = UIL10n.string("%lld names now reach this server through the tunnel.", count)
        } catch {
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
        }
    }

    private func hostVPNProtocols() async -> Set<ServiceID> {
        guard deployment.usesAgent, Self.agentTransportAvailable,
              #available(macOS 15.0, *) else { return [] }
        do {
            let runner = try await session()
            guard let client = try? await AgentConnection.client(deployment: deployment, runner: runner,
                                                                 host: deployment.vpnHost)
            else { return [] }
            let discovered = try await client.discover()
            let ids = AgentServiceMapping.serviceIDs(
                forAgentServices: discovered.services.map { ($0.id, $0.containers.map(\.name)) })
            return ids.filter { ServiceID.vpnProtocols.contains($0) }
        } catch {
            return []
        }
    }

    /// The relay's role, when this service runs on the relay
    func surfaceRole(for service: ServiceID?) -> Gryonixnexusd_V1_HostRole? {
        agentHost(for: service) == nil ? nil : .vpsRelay
    }

    /// The machine that runs this service, when not the default
    func agentHost(for service: ServiceID?) -> SSHHostID? {
        guard let service, deployment.vpnRunsOnRelay, ServiceID.vpnFamily.contains(service) else { return nil }
        return deployment.vpnHost
    }

    private func installOperations(for service: ServiceID? = nil) async throws -> AgentInstallOperations {
        guard deployment.usesAgent, Self.agentTransportAvailable else {
            throw ServerControlError.commandFailed(
                command: "install", exitCode: nil,
                stderr: UIL10n.string("This server is not managed by the gryonixNexus agent."))
        }
        guard #available(macOS 15.0, *) else {
            throw ServerControlError.commandFailed(
                command: "install", exitCode: nil,
                stderr: UIL10n.string("Agent management needs macOS 15 or newer."))
        }
        let runner = try await session()
        let client = try await AgentConnection.client(deployment: deployment, runner: runner,
                                                      host: agentHost(for: service))
        return AgentInstallOperations(client: client, gate: agentGate)
    }

    // MARK: - A session that died between taps

    /// Rebuilds a dead session once instead of failing
    func onLiveSession<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            guard Self.isDeadSession(error) else { throw error }
            invalidateSession()
            sessionMaybeStale = false
            return try await work()
        }
    }

    /// An answered call is a refusal, not a dead session
    static func isDeadSession(_ error: Error) -> Bool {
        if case AgentError.rpc = error { return false }
        if case AgentError.transport = error { return true }
        if case ServerControlError.sudoPasswordRequired = error { return false }
        let text = String(describing: error).lowercased()
        return Self.deadSessionWords.contains { text.contains($0) }
    }

    /// What the layers below call a closed channel
    private static let deadSessionWords = [
        "closed", "not connected", "broken pipe", "connection reset", "connectionreset",
        "unavailable", "timed out", "timeout", "eof", "disconnect", "no such channel",
        "handshake", "connectionrefused", "connection refused", "socket",
    ]

    func invalidateSession() {
        let old = runner
        runner = nil
        DashboardSessionFactory.invalidate(deploymentID: deployment.id)
        Task { await old?.disconnect() }
    }

    func session() async throws -> any SSHCommandRunner {
        if let runner { return runner }
        let make = makeRunner
        let target = deployment
        let fresh = try await Task.detached(priority: .userInitiated) {
            try make(target)
        }.value
        if let runner {
            Task { [id = target.id] in
                await DashboardSessionFactory.release(fresh, deploymentID: id)
            }
            return runner
        }
        runner = fresh
        return fresh
    }

    // MARK: - Refresh

    func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        connectionError = nil
        if sessionMaybeStale {
            sessionMaybeStale = false
            invalidateSession()
        }

        await withTaskGroup(of: Void.self) { group in
            for node in self.deployment.nodes {
                let host = node.sshHost
                let wireGuard = self.showsWireGuard(node)
                group.addTask { await self.loadHost(host, wireGuard: wireGuard) }
            }
            if self.isRelay {
                group.addTask { await self.loadGeneral() }
            }
            group.addTask { await self.loadServices() }
            if self.hasAdminLockdown {
                group.addTask { await self.refreshAdminLockdown() }
            }
            if self.canShowSecurity {
                group.addTask { await self.loadSecurity() }
                group.addTask { await self.loadSSHPasswordAccess() }
            }
            group.addTask { await self.importInstallReportsIfNeeded() }
        }
    }

    // MARK: - Install report

    private var reportImportsTried: Set<String> = []

    private func importInstallReportsIfNeeded() async {
        let store = DeploymentReportStore(deploymentID: deployment.id)
        let stored = await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: store.load().map { ($0.host, $0.text) })
        }.value
        let hosts: [(String, SSHHostID)] = deployment.nodes.map {
            (Self.installReportKey(for: $0, in: deployment), $0.sshHost)
        }
        for (key, host) in hosts where !reportImportsTried.contains(key) {
            reportImportsTried.insert(key)
            guard let text = try? await readInstallReport(on: host),
                  !text.isEmpty, text != stored[key] else { continue }
            await Task.detached(priority: .utility) {
                store.save(host: key, text: text)
            }.value
            adoptDomainIfMissing(from: text)
        }
        if deployment.domain.trimmingCharacters(in: .whitespaces).isEmpty {
            for report in stored.values { adoptDomainIfMissing(from: report) }
        }
    }

    private func adoptDomainIfMissing(from report: String) {
        guard deployment.domain.trimmingCharacters(in: .whitespaces).isEmpty,
              let domain = InstallReportFacts.domain(inReport: report) else { return }
        var corrected = deployment
        corrected.domain = domain
        deployment = corrected
        onDeploymentCorrected?(corrected)
    }

    private func readInstallReport(on host: SSHHostID) async throws -> String? {
        let runner = try await session()
        let result = try await runner.run(CommandCatalog.installReport, on: host,
                                          timeout: .seconds(30))
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : DKIMRecordParser.stripMarkers(from: result.stdout)
    }

    var canManageDevices: Bool { deployment.usesAgent && Self.agentTransportAvailable }

    var hasVPNProtocol: Bool {
        !deployment.services.isDisjoint(with: ServiceID.vpnProtocols)
    }

    var vpnProtocolNames: String {
        let names = deployment.services
            .filter { ServiceID.vpnProtocols.contains($0) }
            .sorted()
            .map { ServiceRegistry.service($0)?.displayName ?? $0.rawValue }
        return names.joined(separator: " · ")
    }

    var vpnPanelOnlyReason: LocalizedStringKey {
        if !deployment.usesAgent || !Self.agentTransportAvailable {
            return "This server runs a VPN, but the app cannot manage its devices: that goes through the server's own agent. Install the agent on the server, or open its VPN panel to add a device there."
        }
        return "This server hands out VPN configurations from its own panel — that is how it is set up. Change it in the server's VPN settings to manage devices here as well."
    }

    var managesVPNClients: Bool {
        guard Self.agentTransportAvailable, deployment.usesAgent else { return false }
        guard !deployment.services.isDisjoint(with: ServiceID.vpnProtocols) else { return false }
        return deployment.serviceSettings.vpnClientAccess.allowsAppManagement
    }

    var hasAdminLockdown: Bool { deployment.services.contains(.vpnPanel) }

    private var servicesHost: SSHHostID { deployment.servicesHost }

    /// When the panel guard last answered
    private var adminLockdownReadAt: Date?

    func refreshAdminLockdown() async {
        await loadLockdown { ops in try await ops.status() }
    }

    /// Re-read only when the answer is missing, failed or old
    func refreshAdminLockdownIfStale(maxAge: TimeInterval = DashboardViewModel.securityFreshness) async {
        guard hasAdminLockdown, !adminLockdown.isLoading else { return }
        if adminLockdown.value != nil, let readAt = adminLockdownReadAt,
           Date().timeIntervalSince(readAt) < maxAge { return }
        await refreshAdminLockdown()
    }

    func setAdminLockdown(_ enabled: Bool) async {
        await loadLockdown { ops in try await ops.set(enabled) }
    }

    var lockdownPages: [(id: ServiceID, name: String, host: String)] {
        services.compactMap { service in
            service.webIngress(deployment.serviceContext)
                .map { (service.id, service.displayName, $0.hostname) }
        }
    }

    /// A quick-access link to one installed service's web UI
    struct WebSite: Identifiable {
        let id: String
        let name: String
        let systemImage: String
        let host: String
        var url: URL? { URL(string: "https://\(host)") }
    }

    var webSites: [WebSite] {
        allWebSites.filter { !$0.host.hasSuffix(".") }
    }

    var sitesNeedDomain: Bool {
        allWebSites.contains { $0.host.hasSuffix(".") }
    }

    private var allWebSites: [WebSite] {
        services.compactMap { service in
            service.webIngress(deployment.serviceContext).map {
                WebSite(id: service.id.rawValue, name: service.displayName,
                        systemImage: service.systemImage, host: $0.hostname)
            }
        }
    }

    /// Turns one page's protection on/off
    func setLockdown(host: String, guarded: Bool) async {
        guard let current = adminLockdown.value else { return }
        let all = Set(lockdownPages.map(\.host))
        var wanted = Set(all.filter(current.guards))
        if guarded { wanted.insert(host) } else { wanted.remove(host) }
        let context = deployment.serviceContext
        let expanded = wanted.flatMap { [$0] + context.mirroredHostnames(of: $0) }
        await loadLockdown { ops in
            if wanted == all {
                return try await ops.set(true)
            }
            return try await ops.set(hosts: expanded.sorted())
        }
    }

    private func loadGeneral() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadVPSGeneral() }
            group.addTask { await self.loadHomeForwarding() }
        }
    }

    private func loadHomeForwarding() async {
        await load(\.homeForwarding) { ops in try await ops.ipForwarding(on: .home) }
    }

    /// Every reading for one machine
    private func loadHost(_ host: SSHHostID, wireGuard: Bool) async {
        await loadHostMetrics(on: host)
        if wireGuard {
            await loadHostReading(into: \.hostWireGuard, host: host) { ops in
                try await ops.wgStatus(on: host)
            }
        }
        await loadHostReading(into: \.hostDisk, host: host) { ops in try await ops.disk(on: host) }
        await loadHostReading(into: \.hostMemory, host: host) { ops in try await ops.memory(on: host) }
    }

    private func loadHostReading<T>(
        into keyPath: ReferenceWritableKeyPath<DashboardViewModel, [SSHHostID: Loadable<T>]>,
        host: SSHHostID,
        _ probe: @escaping (StatusOperations) async throws -> T
    ) async {
        self[keyPath: keyPath][host] = .loading
        do {
            let runner = try await session()
            let value = try await probe(StatusOperations(runner: runner, config: config))
            self[keyPath: keyPath][host] = .loaded(value)
        } catch {
            sessionMaybeStale = true
            self[keyPath: keyPath][host] = .failed(Self.message(for: error))
        }
    }

    private func loadHostMetrics(on host: SSHHostID) async {
        if DemoHostMetrics.covers(deployment) {
            demoMetricsTick &+= 1
            hostMetrics[host] = .loaded(DemoHostMetrics.snapshot(
                deploymentID: deployment.id, host: host, tick: demoMetricsTick))
            return
        }
        if hostMetrics[host]?.value == nil { hostMetrics[host] = .loading }
        do {
            let probe = HostMetricsProbe(runner: try await session(),
                                         timeout: config.quickTimeout)
            var previous = previousMetricsSamples[host]
            if previous == nil {
                previous = try await probe.sample(on: host)
                try? await Task.sleep(for: .seconds(1.5))
            }
            let current = try await probe.sample(on: host)
            previousMetricsSamples[host] = current
            let snapshot = HostMetricsSnapshot(current: current, previous: previous)
            hostMetrics[host] = .loaded(snapshot)
            publishMetricsToWidgets(snapshot, from: host)
        } catch {
            previousMetricsSamples[host] = nil
            sessionMaybeStale = true
            hostMetrics[host] = .failed(Self.message(for: error))
        }
    }

    private func loadServices() async {
        await withTaskGroup(of: Void.self) { group in
            for service in services {
                group.addTask { await self.refreshService(service) }
            }
        }
        publishFleetStateToWidgets()
    }

    func refreshService(_ service: any ManagedService) async {
        serviceStatuses[service.id] = .loading
        do {
            try await onLiveSession {
                let (ops, _) = try await operations(for: service)
                serviceStatuses[service.id] =
                    .loaded(try await serviceControl(for: service).status(of: service))
                if ops.backupKind != .none {
                    serviceBackups[service.id] =
                        .loaded(try await backupSeam(for: service).listBackups(of: service))
                }
            }
        } catch {
            sessionMaybeStale = true
            serviceStatuses[service.id] = .failed(Self.message(for: error))
        }
    }

    /// Re-reads the DKIM record(s) for the configuration export
    func fetchDKIMRecords() async throws -> [DKIMRecord] {
        try await dkimSeam().fetchRecords()
    }

    /// The seam for the DKIM re-read
    private func dkimSeam() async throws -> any DKIMManaging {
        let runner = try await session()
        let ssh = SSHDKIMOperations(runner: runner, deployment: deployment)
        let route = DKIMRouting.route(usesAgent: deployment.usesAgent,
                                      agentTransportAvailable: Self.agentTransportAvailable,
                                      hasMailEngine: ServiceRegistry.mailEngine(in: deployment.services) != nil)
        guard route == .agent else { return ssh }
        guard #available(macOS 15.0, *) else { return ssh }
        guard let client = try? await AgentConnection.client(deployment: deployment, runner: runner)
        else { return ssh }
        return AgentDkimOperations(client: client, gate: agentGate)
    }

    /// One command, three rows
    private func loadVPSGeneral() async {
        vpsForwarding = .loading
        vpsPing = .loading
        tunnelPing = .loading
        do {
            let runner = try await session()
            let status = try await StatusOperations(runner: runner, config: config).generalVPSStatus()
            vpsForwarding = .loaded(status.forwarding)
            vpsPing = .loaded(status.selfPing)
            tunnelPing = .loaded(status.tunnelPing)
            if let citadel = runner as? CitadelCommandRunner {
                onFallbackAddress = await citadel.isReachedByFallback(.vps)
            }
        } catch {
            sessionMaybeStale = true
            let message = Self.message(for: error)
            vpsForwarding = .failed(message)
            vpsPing = .failed(message)
            tunnelPing = .failed(message)
        }
    }

    private func load<T>(_ keyPath: ReferenceWritableKeyPath<DashboardViewModel, Loadable<T>>,
                         _ probe: @escaping (StatusOperations) async throws -> T) async {
        self[keyPath: keyPath] = .loading
        do {
            let value = try await onLiveSession { () -> T in
                let runner = try await session()
                return try await probe(StatusOperations(runner: runner, config: config))
            }
            self[keyPath: keyPath] = .loaded(value)
        } catch {
            sessionMaybeStale = true
            self[keyPath: keyPath] = .failed(Self.message(for: error))
        }
    }

    private func loadLockdown(_ probe: @escaping (any AdminLockdownManaging) async throws -> AdminLockdownState) async {
        adminLockdown = .loading
        do {
            let state = try await onLiveSession { try await probe(try await lockdownSeam()) }
            adminLockdown = .loaded(state)
            adminLockdownReadAt = Date()
        } catch {
            sessionMaybeStale = true
            adminLockdown = .failed(Self.message(for: error))
            adminLockdownReadAt = nil
        }
    }

    /// Restarts sshd on EVERY machine this deployment has
    func restartSSHDEverywhere() async {
        await runQuickAction(successMessage: UIL10n.string("SSH was restarted.")) { runner in
            let ops = StatusOperations(runner: runner, config: self.config)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for node in self.deployment.nodes {
                    group.addTask { try await ops.restartSSHD(on: node.sshHost) }
                }
                try await group.waitForAll()
            }
        }
    }

    var sshdRestartQuestion: String {
        switch deployment.nodes.count {
        case 0, 1: return UIL10n.string("Restart sshd?")
        case 2: return UIL10n.string("Restart sshd on both machines?")
        default: return UIL10n.string("Restart sshd on every machine?")
        }
    }

    /// What the reboot button for one machine says
    static func rebootTitle(for node: DeploymentNode, in deployment: Deployment) -> String {
        if !node.name.isEmpty { return UIL10n.string("Reboot %@", node.name) }
        switch node.legacySlot {
        case .vps:
            return deployment.nodes.count > 1
                ? UIL10n.string("Reboot VPS") : UIL10n.string("Reboot server")
        case .home:
            return UIL10n.string("Reboot local server")
        case nil:
            return UIL10n.string("Reboot %@", node.endpoint.host)
        }
    }

    /// Reboots one host
    func rebootHost(_ host: SSHHostID) async {
        await runQuickAction(successMessage: UIL10n.string("Reboot sent — the machine will be back in about a minute.")) { runner in
            let ops = StatusOperations(runner: runner, config: self.config)
            try await ops.reboot(on: host)
        }
        invalidateSession()
    }

    func restartWireGuardBoth() async {
        let operation = LongOperationState(title: UIL10n.string("Restarting WireGuard"),
                                           progressText: UIL10n.string("Restarting on the VPS…"))
        present(operation)
        do {
            let runner = try await session()
            let op = WireGuardRestartOperation(runner: runner, config: config)
            for try await event in op.restartBoth() {
                switch event {
                case .restartingVPS:
                    operation.progressText = UIL10n.string("Restarting on the VPS…")
                case .vpsDone:
                    operation.progressText = UIL10n.string("The VPS is done.")
                case .restartSentToHome:
                    operation.progressText = UIL10n.string("The command was sent to the local server (the connection dropped — this is expected).")
                case .pollingTunnel(let attempt, let maxAttempts):
                    let seconds = attempt * 3
                    operation.progressText = UIL10n.string("Waiting for the tunnel: attempt %1$d/%2$d (%3$d s)…",
                                                           attempt, maxAttempts, seconds)
                case .recovered:
                    operation.progressText = UIL10n.string("The tunnel is back up.")
                case .failedToRecover:
                    operation.errorMessage = UIL10n.string("The tunnel did not recover within 60 seconds. Check the local server manually.")
                }
            }
        } catch {
            operation.errorMessage = Self.message(for: error)
        }
        operation.isFinished = true
        invalidateSession()
        await refreshAll()
    }

    func restartEverything() async {
        let operation = LongOperationState(title: UIL10n.string("Restarting everything"))
        present(operation)
        func note(_ line: String) {
            operation.progressText = line
            operation.log += operation.log.isEmpty ? line : "\n" + line
        }
        do {
            let runner = try await session()
            // Only services that actually declare a restart command.
            let targets: [FullRestartOperation.ServiceRestartTarget] = services.compactMap { service in
                guard let command = service.actions(deployment.serviceContext).restart else { return nil }
                return .init(name: service.displayName, command: command.command)
            }
            let op = FullRestartOperation(runner: runner, config: config, services: targets)
            for try await event in op.run() {
                switch event {
                case .restartingService(let name):
                    note(UIL10n.string("Restarting %@…", name))
                case .serviceRestarted(let name):
                    note(UIL10n.string("%@ was restarted.", name))
                case .serviceFailed(let name, let detail):
                    note(UIL10n.string("%1$@ could not be restarted: %2$@", name, detail))
                case .restartSentToHomeTunnel:
                    note(UIL10n.string("The command was sent to the local server (the connection dropped — this is expected)."))
                case .restartingVPSTunnel:
                    note(UIL10n.string("Restarting on the VPS…"))
                case .vpsTunnelDone:
                    note(UIL10n.string("The VPS is done."))
                case .waitingForTunnel(let attempt, let maxAttempts):
                    operation.progressText = UIL10n.string("Waiting for the tunnel: attempt %1$d/%2$d (%3$d s)…",
                                                           attempt, maxAttempts, attempt * 3)
                case .recovered:
                    note(UIL10n.string("The tunnel is back up."))
                case .failedToRecover:
                    operation.errorMessage = UIL10n.string("The tunnel did not recover within 60 seconds. Check the local server manually.")
                }
            }
        } catch {
            operation.errorMessage = Self.message(for: error)
        }
        operation.isFinished = true
        invalidateSession()
        await refreshAll()
    }

    func restart(_ service: any ManagedService) async {
        await power(.restart, service,
                    successMessage: UIL10n.string("%@ was restarted.", service.displayName))
    }

    func start(_ service: any ManagedService) async {
        await power(.start, service,
                    successMessage: UIL10n.string("%@ was started.", service.displayName))
    }

    func stop(_ service: any ManagedService) async {
        await power(.stop, service,
                    successMessage: UIL10n.string("%@ was stopped.", service.displayName))
    }

    /// A bounded tail of one service's log, read over SSH
    func serviceLogs(_ service: any ManagedService) async throws -> [String] {
        let (ops, _) = try await operations(for: service)
        return try await ops.logs()
    }

    /// Start / stop / restart, on whichever route this deployment uses
    private func power(_ action: ServicePowerAction, _ service: any ManagedService,
                       successMessage: String) async {
        do {
            let control = try await serviceControl(for: service)
            serviceStatuses[service.id] = .loaded(try await control.power(action, on: service))
            quickActionResult = QuickActionResult(message: successMessage, isError: false)
        } catch {
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
            await refreshService(service)
        }
    }

    /// Start/stop/restart a single container of a service
    func controlContainer(_ container: ContainerStatus,
                          action: CommandCatalog.Containers.Action,
                          service: any ManagedService) async {
        let name = container.name
        let message: String
        switch action {
        case .start: message = UIL10n.string("%@ was started.", name)
        case .stop: message = UIL10n.string("%@ was stopped.", name)
        case .restart: message = UIL10n.string("%@ was restarted.", name)
        }
        let host = deployment.host(running: service.id)
        await runQuickAction(successMessage: message) { runner in
            let ops = StatusOperations(runner: runner, config: self.config)
            try await ops.controlContainer(action, name: name, on: host)
        }
        await refreshService(service)
    }

    // MARK: - Scheduled backups

    var hasBackupCapableService: Bool {
        services.contains { $0.actions(deployment.serviceContext).backup != nil }
    }

    var autoBackupHasPassphrase: Bool {
        guard autoBackup.isOn else { return false }
        return services.contains { service in
            guard autoBackup.services.contains(service.id.rawValue) else { return false }
            if case .encryptedVolume = service.actions(deployment.serviceContext).backup {
                return true
            }
            return false
        }
    }

    func loadAutoBackup() async {
        do {
            let seam = try await autoBackupSeam()
            autoBackup = try await seam.load()
            autoBackupAnswered = true
            autoBackupError = nil
            publishFleetStateToWidgets()
        } catch {
            autoBackupError = Self.message(for: error)
        }
    }

    func loadSecurityAutoRules() async {
        guard #available(macOS 15.0, *), canShowSecurity else { return }
        do {
            securityAutoRules = try await onLiveSession { try await securityOperations().autoRules() }
            securityAutoRulesError = nil
        } catch {
            securityAutoRulesError = Self.message(for: error)
        }
    }

    /// The rules edited during a save that is still running
    private var queuedSecurityAutoRules: HostSecurityAutoRules?

    func saveSecurityAutoRules(_ rules: HostSecurityAutoRules) async {
        guard #available(macOS 15.0, *), canShowSecurity else { return }
        queuedSecurityAutoRules = rules
        // A later edit replaces the one waiting
        guard !securityAutoRulesBusy else { return }
        securityAutoRulesBusy = true
        defer { securityAutoRulesBusy = false }
        while let next = queuedSecurityAutoRules {
            queuedSecurityAutoRules = nil
            do {
                let wasOn = securityAutoRules?.isOn
                securityAutoRules = try await securityOperations().setAutoRules(next)
                securityAutoRulesError = nil
                guard wasOn != next.isOn else { continue }
                quickActionResult = QuickActionResult(
                    message: next.isOn
                        ? UIL10n.string("Automatic blocking is on.")
                        : UIL10n.string("Automatic blocking is off."),
                    isError: false)
            } catch {
                securityAutoRulesError = Self.message(for: error)
                queuedSecurityAutoRules = nil
                return
            }
        }
    }

    // MARK: - Backup destination

    func loadBackupDestination() async {
        do {
            let seam = try await autoBackupSeam()
            backupDestination = try await seam.loadDestination()
            backupDestinationAnswered = true
            backupDestinationError = nil
        } catch {
            backupDestinationError = Self.message(for: error)
        }
    }

    func saveBackupDestination(_ settings: BackupDestinationSettings, secret: String?) async {
        backupDestinationBusy = true
        backupDestinationCheck = nil
        defer { backupDestinationBusy = false }
        do {
            let seam = try await autoBackupSeam()
            try await seam.saveDestination(settings, secret: secret)
            backupDestination = try await seam.loadDestination()
            backupDestinationAnswered = true
            backupDestinationError = nil
        } catch {
            backupDestinationError = Self.message(for: error)
        }
    }

    /// Sends one small file and keeps what came back
    func checkBackupDestination() async {
        backupDestinationBusy = true
        defer { backupDestinationBusy = false }
        do {
            let seam = try await autoBackupSeam()
            backupDestinationCheck = try await seam.testDestination()
            backupDestination = try await seam.loadDestination()
            backupDestinationError = nil
        } catch {
            backupDestinationError = Self.message(for: error)
            backupDestinationCheck = nil
        }
    }

    func authorizeBackupKey(on target: Deployment) async {
        guard !backupDestination.publicKey.isEmpty else { return }
        backupDestinationBusy = true
        defer { backupDestinationBusy = false }
        do {
            let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: target,
                                                                             shared: false)
            let command = AccessGrantCommand.command(publicKey: backupDestination.publicKey)
            let result = try await runner.run(command, on: target.servicesHost,
                                              timeout: target.timeouts.duration(for: .quick))
            await DashboardSessionFactory.release(runner, deploymentID: target.id)
            guard result.succeeded else {
                backupDestinationError = OutputTail.tail(result.stderr)
                return
            }
            backupDestinationError = nil
            quickActionResult = QuickActionResult(
                message: UIL10n.string("The key is authorized on %@.", target.name),
                isError: false)
        } catch {
            backupDestinationError = Self.message(for: error)
        }
    }

    func loadAutoUpdate() async {
        do {
            let updates = try await updateManaging()
            autoUpdate = try await updates.loadSchedule()
            autoUpdateError = nil
        } catch {
            autoUpdateError = Self.message(for: error)
        }
        if let updates = try? await updateManaging(),
           let log = try? await updates.loadStatus() {
            updateRunLog = log
        }
    }

    func saveAutoUpdate(_ settings: AutoUpdateSettings) async {
        do {
            try await updateManaging().save(settings)
            autoUpdate = settings
            autoUpdateError = nil
            quickActionResult = QuickActionResult(
                message: settings.isOn
                    ? UIL10n.string("Scheduled updates are on.")
                    : UIL10n.string("Scheduled updates are off."),
                isError: false)
        } catch {
            autoUpdateError = Self.message(for: error)
        }
    }

    /// Asks the server what has moved
    func checkForUpdates() async {
        checkingUpdates = true
        defer { checkingUpdates = false }
        do {
            let reports = try await updateManaging().check()
            var answers = Dictionary(uniqueKeysWithValues: reports.map { ($0.service, $0.status) })
            for service in services where answers[service.id] == nil {
                answers[service.id] = Self.statusForUnreported(service, context: deployment.serviceContext)
            }
            updateReports = answers
            autoUpdateError = nil
            publishFleetStateToWidgets()
        } catch {
            autoUpdateError = Self.message(for: error)
            updateReports = [:]
        }
    }

    /// What a service the check did not mention should show
    static func statusForUnreported(_ service: any ManagedService,
                                    context: ServiceContext) -> ServiceUpdateStatus {
        switch service.updateSpec(context).flavour {
        case .ownUpdater: return .selfManaged
        case .builtOnServer: return .rebuiltBySetup
        case .composePull: return .unknown
        }
    }

    func runUpdateNow(_ service: any ManagedService) async {
        let operation = LongOperationState(
            title: UIL10n.string("Updating %@", service.displayName),
            progressText: UIL10n.string("Backing up, then updating. This may take up to 10 minutes.")
        )
        operation.retry = { [weak self] in Task { await self?.runUpdateNow(service) } }
        present(operation)
        do {
            let started = Date()
            let streamed = Task { @MainActor in
                try await self.updateManaging().run(service.id) { chunk in
                    Task { @MainActor in
                        self.appendWrapperOutput(chunk, to: operation)
                    }
                }
            }
            let watchdog = Task { @MainActor in
                await self.updateEndedOnServer(service, since: started, streamed: streamed)
            }
            defer { watchdog.cancel() }
            if let ended = try await Self.updateResult(of: streamed, watchdog: watchdog) {
                Self.show(ended, in: operation)
            }
        } catch {
            if await continuesOnServer(operation, after: error, kind: .update, service: service) { return }
            operation.errorMessage = Self.message(for: error)
        }
        operation.isFinished = true
        await refreshService(service)
        await loadAutoUpdate()
    }

    private func continuesOnServer(_ operation: LongOperationState, after error: Error,
                                   kind: AgentJobKind, service: any ManagedService) async -> Bool {
        guard deployment.usesAgent, Self.isLostConnection(error), #available(macOS 15.0, *),
              let subject = AgentServiceMapping.agentID(for: service.id) else { return false }
        let watcher = RunningJobsWatcher.shared
        guard watcher.isAppActive else {
            watcher.resumeWhenBack(operation, kind: kind, subject: subject, of: deployment)
            return true
        }
        return await watcher.resume(operation, kind: kind, subject: subject, of: deployment)
    }

    /// Anything but a reply the agent itself sent
    private static func isLostConnection(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if case AgentError.rpc = error { return false }
        if case ServerControlError.commandFailed = error { return false }
        return true
    }

    /// The service row's Update button
    func update(_ service: any ManagedService) async {
        await runUpdateNow(service)
    }

    func saveAutoBackup(_ settings: AutoBackupSettings, passphrase: String?) async {
        do {
            let seam = try await autoBackupSeam()
            try await seam.save(settings, passphrase: passphrase)
            autoBackup = settings
            autoBackupAnswered = true
            autoBackupError = nil
            publishFleetStateToWidgets()
            quickActionResult = QuickActionResult(
                message: settings.isOn
                    ? UIL10n.string("Scheduled backups are on.")
                    : UIL10n.string("Scheduled backups are off."),
                isError: false)
        } catch {
            autoBackupError = Self.message(for: error)
        }
    }

    func loadBackups(_ service: any ManagedService) async {
        serviceBackups[service.id] = .loading
        do {
            serviceBackups[service.id] =
                .loaded(try await backupSeam(for: service).listBackups(of: service))
        } catch {
            serviceBackups[service.id] = .failed(Self.message(for: error))
        }
        await loadPreRestoreCopies(service)
    }

    func backupPath(_ service: any ManagedService, entry: BackupEntry) -> String? {
        guard let runner else { return nil }
        return ServiceOperations(runner: runner, deployment: deployment, service: service)
            .backupPath(for: entry)
    }

    func deleteBackup(_ service: any ManagedService, entry: BackupEntry) async {
        do {
            let (ops, _) = try await operations(for: service)
            guard let path = ops.backupPath(for: entry) else { return }
            try await backupSeam(for: service).deleteBackup(service, path: path)
            quickActionResult = QuickActionResult(
                message: UIL10n.string("%@ was deleted.", entry.displayName), isError: false)
        } catch {
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
        }
        await loadBackups(service)
    }

    /// Removes the service from the machine
    func uninstall(_ service: any ManagedService, purge: PurgeOptions) async -> Deployment? {
        let operation = LongOperationState(
            title: UIL10n.string("Removing %@", service.displayName),
            progressText: UIL10n.string("Stopping and removing containers…"))
        present(operation)
        let remaining = Self.remainingVPNProtocols(after: service, in: deployment.services)
        if !remaining.isEmpty {
            return await dropVPNProtocol(service, keeping: remaining, operation: operation)
        }
        var updated: Deployment?
        do {
            let removal = try await removalManaging(for: service)
            operation.log = WrapperLogText.readable(
                try await removal.remove(service, purge: purge) { chunk in
                    Task { @MainActor in
                        self.appendWrapperOutput(chunk, to: operation)
                    }
                })
            let before = self.deployment
            var deployment = self.deployment
            deployment.services.subtract(Self.removedServices(with: service, installed: deployment.services))
            let portsChanged = Self.forwardedPorts(of: self.deployment) != Self.forwardedPorts(of: deployment)
            operation.dnsUpdate = await ServiceDNSPublisher.pending(removing: service, from: before, keeping: deployment)
            if operation.dnsUpdate != nil { RunningOperationsRegistry.shared.bringUp(operation) }
            self.deployment = deployment
            updated = deployment
            if portsChanged, deployment.hasRelayIngress, #available(macOS 15.0, *) {
                do {
                    _ = try await reprovisionRelay()
                } catch {
                    operation.log += "\n" + UIL10n.string("Could not update the relay: %@", Self.message(for: error)) + "\n"
                }
            }
            operation.progressText = purge.data
                ? UIL10n.string("The service and its data have been removed.")
                : UIL10n.string("The service has been removed. Its data is still on the server.")
            if let note = await refreshHostSurfaceAfterRemoval(of: service) {
                operation.log += "\n" + note + "\n"
            }
        } catch {
            if await continuesOnServer(operation, after: error, kind: .uninstall, service: service) { return nil }
            operation.errorMessage = Self.message(for: error)
        }
        operation.isFinished = true
        return updated
    }

    @Published var erased = false

    func fullCleanup(purge: PurgeOptions) async {
        let operation = LongOperationState(
            title: UIL10n.string("Erasing %@", deployment.name),
            progressText: UIL10n.string("Connecting…"))
        present(operation)
        do {
            let runner = try await session()
            let ops = UninstallOperations(runner: runner, deployment: deployment)
            try await ops.fullCleanup(purge: purge) { event in
                Task { @MainActor in
                    switch event {
                    case .hostStarted(let host):
                        operation.progressText = UIL10n.string("Cleaning up %@…", self.hostDisplayName(host))
                    case .output(let text):
                        self.appendWrapperOutput(text, to: operation)
                    case .hostFinished(let host):
                        operation.log += "\n" + UIL10n.string("%@ is clean.", self.hostDisplayName(host)) + "\n"
                    }
                }
            }
            erased = true
            operation.progressText = UIL10n.string("The server has been erased.")
        } catch {
            operation.errorMessage = Self.message(for: error)
        }
        operation.isFinished = true
    }

    /// What to call a machine in the erase log
    private func hostDisplayName(_ host: SSHHostID) -> String {
        Self.hostDisplayName(host, in: deployment)
    }

    /// What to call one machine of a deployment
    nonisolated static func hostDisplayName(_ host: SSHHostID, in deployment: Deployment) -> String {
        switch host.kind {
        case .slot(.vps): return UIL10n.string("VPS relay")
        case .slot(.home): return UIL10n.string("Local server")
        case .node(let id):
            guard let node = deployment.nodes.first(where: { $0.id == id }) else { return id.uuidString }
            return node.name.isEmpty ? node.endpoint.host : node.name
        }
    }

    /// VPN protocols that stay after this one goes
    nonisolated static func remainingVPNProtocols(after service: any ManagedService,
                                                  in installed: Set<ServiceID>) -> Set<ServiceID> {
        guard ServiceID.vpnProtocols.contains(service.id) else { return [] }
        return installed.intersection(ServiceID.vpnProtocols).subtracting([service.id])
    }

    /// Removes one protocol, reinstalling the VPN with the rest
    private func dropVPNProtocol(_ service: any ManagedService, keeping remaining: Set<ServiceID>,
                                 operation: LongOperationState) async -> Deployment? {
        var updated: Deployment?
        do {
            let installer = try await installOperations(for: service.id)
            var planned = deployment
            planned.services.remove(service.id)
            var context = Self.agentHostSurfaceContext(
                for: planned, devicePublicKey: await Self.devicePublicKey(for: deployment),
                role: surfaceRole(for: service.id))
            let anchor = ServiceRegistry.all.map(\.id).first(where: remaining.contains) ?? service.id
            context.settings[AgentInstallSettings.vpnProtocolsKey] =
                AgentInstallSettings.vpnProtocolList(adding: anchor, installed: remaining)
            let log = try await installer.install(anchor, context: context, onJobID: { _ in }, onChunk: { chunk in
                Task { @MainActor in self.appendWrapperOutput(chunk, to: operation) }
            })
            operation.log = OutputTail.tail(operation.log + log, maxCharacters: OutputTail.logCharacters)
            operation.dnsUpdate = await ServiceDNSPublisher.pending(removing: service, from: deployment, keeping: planned)
            if operation.dnsUpdate != nil { RunningOperationsRegistry.shared.bringUp(operation) }
            let portsChanged = Self.forwardedPorts(of: deployment) != Self.forwardedPorts(of: planned)
            deployment = planned
            updated = planned
            if portsChanged, planned.hasRelayIngress, #available(macOS 15.0, *) {
                _ = try? await reprovisionRelay()
            }
            operation.progressText = UIL10n.string("%@ is removed. The other VPN protocols keep running.",
                                                   service.displayName)
        } catch {
            if await continuesOnServer(operation, after: error, kind: .install, service: service) { return nil }
            operation.errorMessage = Self.message(for: error)
        }
        operation.isFinished = true
        return updated
    }

    /// Services that leave together with this one
    nonisolated static func removedServices(with service: any ManagedService,
                                            installed: Set<ServiceID>) -> Set<ServiceID> {
        if !remainingVPNProtocols(after: service, in: installed).isEmpty { return [service.id] }
        if ServiceID.vpnProtocols.contains(service.id) || service.id == .vpnPanel {
            return ServiceID.vpnProtocols.union([.vpnPanel])
        }
        return [service.id]
    }

    func estimateBackup(_ service: any ManagedService) async throws -> BackupEstimate? {
        try await backupSeam(for: service).estimate(of: service)
    }

    /// Backs up each chosen service in turn
    func runBackups(_ choice: BackupNowChoice) async {
        let context = deployment.serviceContext
        let chosen = choice.services.compactMap { id in services.first { $0.id.rawValue == id } }
        let defaultsOn = Set(chosen.filter { $0.actions(context).backup?.encryptsByDefault == true }.map(\.id.rawValue))
        let always = Set(chosen.filter { $0.actions(context).backup?.wrapper == nil }.map(\.id.rawValue))
        for (index, service) in chosen.enumerated() {
            let id = service.id.rawValue
            await runWrapperBackup(service,
                                   encrypt: choice.encrypts(id, defaultsOn: defaultsOn, alwaysEncrypted: always),
                                   passphrase: choice.passphraseToSend, opensSheet: index == 0)
        }
    }

    /// `encrypt` and `passphrase` come from the confirmation sheet
    func runWrapperBackup(_ service: any ManagedService,
                          encrypt: Bool? = nil, passphrase: String? = nil, opensSheet: Bool = true) async {
        let operation = LongOperationState(
            title: UIL10n.string("Backing up %@", service.displayName),
            progressText: deployment.usesAgent
                ? UIL10n.string("The backup may take a few minutes. It runs on the server, so you can close the app.")
                : UIL10n.string("The backup may take a few minutes. Keep the app open.")
        )
        operation.downloadHost = backupDownloadHost(for: service.id)
        present(operation, opensSheet: opensSheet)
        do {
            let (ops, _) = try await operations(for: service)
            operation.log = WrapperLogText.readable(
                try await backupSeam(for: service)
                    .backup(service, encrypt: encrypt, passphrase: passphrase) { chunk in
                        Task { @MainActor in
                            self.appendWrapperOutput(chunk, to: operation)
                        }
                    }.log)
            operation.progressText = UIL10n.string("Backup finished.")
            // Best effort: nil for directory backups (mailcow) — no button.
            operation.shareableBackupPath = try? await ops.latestShareableBackupPath()
        } catch {
            if await continuesOnServer(operation, after: error, kind: .backup, service: service) { return }
            operation.errorMessage = Self.message(for: error)
        }
        operation.isFinished = true
        await refreshService(service)
    }

    func runEncryptedBackup(_ service: any ManagedService, passphrase: String) async {
        let operation = LongOperationState(title: UIL10n.string("Encrypted backup of %@", service.displayName),
                                           progressText: UIL10n.string("Stopping the container…"))
        operation.downloadHost = backupDownloadHost(for: service.id)
        present(operation)
        do {
            let (ops, _) = try await operations(for: service)
            for try await event in ops.encryptedBackup(passphrase: passphrase) {
                switch event {
                case .stoppingContainer: operation.progressText = UIL10n.string("Stopping the container…")
                case .archiving: operation.progressText = UIL10n.string("Archiving data…")
                case .encrypting: operation.progressText = UIL10n.string("Encrypting (GPG, AES256)…")
                case .startingContainer: operation.progressText = UIL10n.string("Starting the container…")
                case .rotating: operation.progressText = UIL10n.string("Rotating old backups…")
                case .completed(let size):
                    operation.progressText = UIL10n.string("Backup finished.")
                    operation.log = size
                }
            }
            if let (ops, _) = try? await operations(for: service) {
                operation.shareableBackupPath = try? await ops.latestShareableBackupPath()
            }
        } catch {
            if await continuesOnServer(operation, after: error, kind: .backup, service: service) { return }
            operation.errorMessage = Self.message(for: error)
        }
        operation.isFinished = true
        await refreshService(service)
    }

    // MARK: - VPN client devices

    /// The devices of the protocol currently being looked at
    @Published var vpnClients: Loadable<[VPNClientDevice]> = .idle

    var vpnClientProtocols: [ServiceID] {
        guard deployment.usesAgent, Self.agentTransportAvailable else { return [] }
        return VPNClientProtocols.installed(in: deployment.services)
    }

    func vpnProtocol(preferring preferred: ServiceID?) -> ServiceID {
        let installed = vpnClientProtocols
        return preferred.flatMap { installed.contains($0) ? $0 : nil }
            ?? installed.first ?? .wireguardVPN
    }

    @Published var meshNodes: Loadable<[MeshNode]> = .idle

    var managesMesh: Bool {
        guard deployment.usesAgent, Self.agentTransportAvailable else { return false }
        return deployment.services.contains(.headscale)
    }

    // MARK: Containers

    @Published var containerInventory: Loadable<ContainerInventory> = .idle

    var canListContainers: Bool {
        deployment.usesAgent && Self.agentTransportAvailable
    }

    @available(macOS 15.0, *)
    private func containerOperations() async throws -> AgentContainerOperations {
        let runner = try await session()
        let client = try await AgentConnection.client(deployment: deployment, runner: runner)
        return AgentContainerOperations(client: client, gate: agentGate)
    }

    func loadContainers() async {
        guard #available(macOS 15.0, *) else {
            containerInventory = .failed(
                UIL10n.string("This server is not managed over the panel's own connection."))
            return
        }
        if containerInventory.value == nil { containerInventory = .loading }
        do {
            containerInventory = .loaded(try await containerOperations().inventory())
        } catch {
            sessionMaybeStale = true
            containerInventory = .failed(Self.message(for: error))
        }
    }

    func renameContainerGroup(key: String, to name: String) async {
        guard #available(macOS 15.0, *) else { return }
        do {
            containerInventory = .loaded(try await containerOperations().rename(key: key, to: name))
        } catch {
            sessionMaybeStale = true
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
        }
    }

    /// Start / stop / restart one group, then re-read
    func controlContainerGroup(key: String, action: ContainerAction) async {
        guard #available(macOS 15.0, *) else { return }
        do {
            let ops = try await containerOperations()
            for try await _ in ops.control(key: key, action: action) {}
            await loadContainers()
        } catch {
            sessionMaybeStale = true
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
            await loadContainers()
        }
    }

    @available(macOS 15.0, *)
    func inspectContainer(named name: String) async throws -> ContainerDetail {
        try await containerOperations().inspect(container: name)
    }

    @available(macOS 15.0, *)
    private func meshOperations() async throws -> any MeshManaging {
        let runner = try await session()
        let client = try await AgentConnection.client(deployment: deployment, runner: runner)
        return AgentMeshOperations(client: client, gate: agentGate)
    }

    func loadMeshNodes() async {
        guard #available(macOS 15.0, *) else {
            meshNodes = .failed(UIL10n.string("This server is not managed over the panel's own connection."))
            return
        }
        if meshNodes.value == nil { meshNodes = .loading }
        do {
            meshNodes = .loaded(try await meshOperations().nodes())
        } catch {
            sessionMaybeStale = true
            meshNodes = .failed(Self.message(for: error))
        }
    }

    func removeMeshNode(id: String) async {
        guard #available(macOS 15.0, *) else { return }
        do {
            meshNodes = .loaded(try await meshOperations().removeNode(id: id))
            quickActionResult = QuickActionResult(
                message: UIL10n.string("The device was removed."), isError: false)
        } catch {
            sessionMaybeStale = true
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
        }
    }

    /// Mint a join key for a new device
    func mintMeshJoinKey() async -> MeshAuthKey? {
        guard #available(macOS 15.0, *) else { return nil }
        do {
            let ops = try await meshOperations()
            let users = try await ops.users()
            let user: MeshUser
            if let existing = users.first(where: { $0.name == Self.meshDeviceUser }) {
                user = existing
            } else {
                let created = try await ops.createUser(named: Self.meshDeviceUser)
                guard let made = created.first(where: { $0.name == Self.meshDeviceUser }) else {
                    throw ServerControlError.notConfigured(
                        UIL10n.string("The mesh server did not create the user."))
                }
                user = made
            }
            return try await ops.mintAuthKey(userID: user.id, reusable: false, expirationHours: 24)
        } catch {
            sessionMaybeStale = true
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
            return nil
        }
    }

    var meshLoginServer: String {
        "https://" + HeadscaleService().hostname(deployment.serviceContext)
    }

    static let meshDeviceUser = "devices"

    /// Publish every name this deployment serves into the mesh
    @discardableResult
    func publishMeshNames() async -> [MeshName] {
        guard #available(macOS 15.0, *) else { return [] }
        do {
            let records = try await meshOperations().publishNames(meshPublishableNames())
            quickActionResult = QuickActionResult(
                message: records.isEmpty
                    ? UIL10n.string("The published names were cleared.")
                    : UIL10n.string("%lld names now resolve inside the mesh.", records.count),
                isError: false)
            return records
        } catch {
            sessionMaybeStale = true
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
            return []
        }
    }

    /// Every hostname the deployment serves over the web, aliases included
    func meshPublishableNames() -> [String] {
        TunnelSetup.webNames(of: deployment)
    }

    @available(macOS 15.0, *)
    private func vpnClientOperations() async throws -> any VPNClientManaging {
        // Same reason as the mesh seam above.
        let runner = try await session()
        let client = try await AgentConnection.client(deployment: deployment, runner: runner,
                                                      host: deployment.vpnHost)
        return AgentVPNClientOperations(client: client, gate: agentGate)
    }

    func loadVPNClients(protocol id: ServiceID) async {
        guard #available(macOS 15.0, *) else {
            vpnClients = .failed(UIL10n.string("This server is not managed over the panel's own connection."))
            return
        }
        if vpnClients.value == nil { vpnClients = .loading }
        do {
            let devices = try await vpnClientOperations().list(protocol: id)
            vpnClients = .loaded(devices)
            recordForWidgets(protocol: id, devices: devices, failure: nil)
        } catch {
            sessionMaybeStale = true
            let message = Self.message(for: error)
            vpnClients = .failed(message)
            recordForWidgets(protocol: id, devices: nil, failure: message)
        }
    }

    private func recordForWidgets(protocol id: ServiceID,
                                  devices: [VPNClientDevice]?,
                                  failure: String?) {
        let deploymentID = deployment.id
        let name = deployment.name
        let reading = devices.map {
            [FleetSnapshot.ProtocolDevices(protocolID: id,
                                           deviceCount: $0.count,
                                           deviceNames: Array($0.prefix(6).map(\.name)))]
        } ?? []
        Task.detached(priority: .utility) {
            FleetSnapshotStore().upsertServer(id: deploymentID,
                                              name: name,
                                              protocols: reading,
                                              failure: failure)
            WidgetRefresh.reload()
        }
    }

    /// Puts a host reading where a widget can draw it
    func publishFleetStateToWidgets() {
        guard !DemoServer.isEnabled || !DemoHostMetrics.covers(deployment) else { return }
        let deploymentID = deployment.id
        let name = deployment.name
        let now = Date()

        let answered = serviceStatuses.compactMapValues { $0.value }
        let services: FleetSnapshot.ServicesSummary? = answered.isEmpty ? nil
            : .init(total: answered.count,
                    needingAttention: answered.values.filter { containers in
                        containers.contains { $0.health != .ok }
                    }.count,
                    takenAt: now)

        let read = securityStatus.flatMap { $0.isKnown ? $0 : nil }
        let security: FleetSnapshot.SecuritySummary? = read.map {
            .init(isPresent: $0.isPresent,
                  engineRunning: $0.engineRunning,
                  bouncerRunning: $0.bouncerRunning,
                  alertsLast24h: $0.alertsLast24h,
                  localBans: $0.localBans,
                  communityBlocklistIPs: $0.communityBlocklistIPs,
                  takenAt: now)
        }

        var everyHours: Int?
        var everyDays: Int?
        switch autoBackup.schedule {
        case .off: break
        case .hours(let count, _): everyHours = count
        case .days(let count, _, _): everyDays = count
        }
        let backups: FleetSnapshot.BackupsSummary? = !autoBackupAnswered ? nil
            : FleetSnapshot.BackupsSummary(isOn: autoBackup.isOn,
                                           everyHours: everyHours,
                                           everyDays: everyDays,
                                           servicesCovered: autoBackup.services.count,
                                           retention: autoBackup.retention,
                                           takenAt: now)

        let updates: FleetSnapshot.UpdatesSummary? = updateReports.isEmpty ? nil
            : .init(waiting: updateReports.values.filter {
                        if case .available = $0 { return true } else { return false }
                    }.count,
                    checked: updateReports.count,
                    lastRunOnServer: updateRunLog.lastRun,
                    takenAt: now)

        Task.detached(priority: .utility) {
            FleetSnapshotStore().updateServer(id: deploymentID, name: name) { server in
                if let services { server.services = services }
                if let security { server.security = security }
                if let backups { server.backups = backups }
                if let updates { server.updates = updates }
            }
            WidgetRefresh.reload()
        }
    }

    private func publishMetricsToWidgets(_ snapshot: HostMetricsSnapshot, from host: SSHHostID) {
        guard host == deployment.servicesHost, !DemoHostMetrics.covers(deployment) else { return }
        let deploymentID = deployment.id
        let name = deployment.name
        let label = deployment.metricsMachineLabel(for: host) ?? name
        let reading = FleetSnapshot.Reading(cpuPercent: snapshot.cpuPercent,
                                            memUsedBytes: snapshot.memUsedBytes,
                                            memTotalBytes: snapshot.memTotalBytes,
                                            diskUsedBytes: snapshot.diskUsedBytes,
                                            diskTotalBytes: snapshot.diskTotalBytes,
                                            machineLabel: label,
                                            takenAt: Date())
        Task.detached(priority: .utility) {
            FleetSnapshotStore().upsertMetrics(id: deploymentID, name: name, reading: reading)
            WidgetRefresh.reload()
        }
    }

    func addVPNClient(protocol id: ServiceID, named name: String, dns: [String] = []) async {
        guard #available(macOS 15.0, *) else { return }
        await runVPNClientAction(protocol: id,
                                 message: UIL10n.string("The device was added.")) { ops in
            try await ops.add(protocol: id, named: name, dns: dns)
        }
    }

    func setVPNClientDNS(protocol id: ServiceID, clientID: String, dns: [String]) async {
        guard #available(macOS 15.0, *) else { return }
        await runVPNClientAction(protocol: id,
                                 message: UIL10n.string("The device's DNS was changed.")) { ops in
            try await ops.setDNS(protocol: id, clientID: clientID, dns: dns)
        }
    }

    /// Caddy retries certificates whose names now resolve
    func refreshCertificates() async {
        guard deployment.usesAgent, #available(macOS 15.0, *),
              let runner = try? await session(),
              let client = try? await AgentConnection.client(deployment: deployment, runner: runner) else { return }
        _ = try? await client.refreshCertificates()
    }

    /// The DNS new devices get, and the server's own resolver
    @Published var vpnDNS = VPNDNSDefaults()

    var vpnDefaultDNS: [String] { vpnDNS.dns }

    func loadVPNDefaultDNS() async {
        guard #available(macOS 15.0, *) else { return }
        if let loaded = try? await vpnClientOperations().defaultDNS() { vpnDNS = withHomeResolvers(loaded) }
    }

    func setVPNDefaultDNS(_ dns: [String]) async {
        guard #available(macOS 15.0, *) else { return }
        do {
            vpnDNS = withHomeResolvers(try await vpnClientOperations().setDefaultDNS(dns))
        } catch {
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
        }
    }

    @Published var vpnDNSPriority: VPNDNSPriority?

    /// On the relay, the resolvers installed at home answer
    func withHomeResolvers(_ defaults: VPNDNSDefaults) -> VPNDNSDefaults {
        guard deployment.vpnRunsOnRelay, !defaults.localAddress.isEmpty else { return defaults }
        var answered = defaults
        let home: [ServiceID] = [.adguardHome, .pihole].filter(deployment.services.contains)
        answered.localServices = defaults.localServices.isEmpty ? home : defaults.localServices
        return answered
    }

    /// Swaps in a changed copy of the deployment
    func replaceDeployment(_ changed: Deployment) {
        deployment = changed
    }

    func loadVPNDNSPriority() async {
        guard #available(macOS 15.0, *) else { return }
        vpnDNSPriority = try? await vpnClientOperations().dnsPriority()
    }

    func setVPNDNSPriority(_ resolvers: [String]) async {
        guard #available(macOS 15.0, *) else { return }
        do {
            vpnDNSPriority = try await vpnClientOperations().setDNSPriority(resolvers)
        } catch {
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
        }
    }

    func removeVPNClient(protocol id: ServiceID, clientID: String) async {
        guard #available(macOS 15.0, *) else { return }
        await runVPNClientAction(protocol: id,
                                 message: UIL10n.string("The device was removed.")) { ops in
            try await ops.remove(protocol: id, clientID: clientID)
        }
    }

    @available(macOS 15.0, *)
    private func runVPNClientAction(
        protocol id: ServiceID,
        message: String,
        _ body: @escaping (any VPNClientManaging) async throws -> [VPNClientDevice]
    ) async {
        do {
            let clients = try await body(try await vpnClientOperations())
            vpnClients = .loaded(clients)
            quickActionResult = QuickActionResult(message: message, isError: false)
        } catch {
            sessionMaybeStale = true
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
        }
    }

    /// One device's configuration, for showing and copying
    func vpnClientConfiguration(protocol id: ServiceID, clientID: String) async -> VPNClientConfiguration? {
        guard #available(macOS 15.0, *) else { return nil }
        do {
            return try await vpnClientOperations().configuration(protocol: id, clientID: clientID)
        } catch {
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
            return nil
        }
    }

    @Published var mailboxes: Loadable<[Mailbox]> = .idle

    /// Which half of the mailbox seam this deployment uses
    private func mailboxOperations() async throws -> any MailboxManaging {
        let runner = try await session()
        let ssh = MailboxOperations(runner: runner, deployment: deployment)
        guard #available(macOS 15.0, iOS 18.0, *) else { return ssh }
        let route = MailboxRouting.route(usesAgent: deployment.usesAgent,
                                         agentTransportAvailable: true,
                                         hasEngine: deployment.services.contains(.dockerMailserver))
        guard route == .agent,
              let client = try? await AgentConnection.client(deployment: deployment, runner: runner)
        else { return ssh }
        return AgentMailboxOperations(client: client, engineInstalled: true, gate: agentGate)
    }

    func loadMailboxes() async {
        if mailboxes.value == nil { mailboxes = .loading }
        do {
            mailboxes = .loaded(try await mailboxOperations().list())
        } catch {
            sessionMaybeStale = true
            mailboxes = .failed(Self.message(for: error))
        }
    }

    func addMailbox(address: String, password: String) async {
        await runMailboxAction(title: UIL10n.string("Adding a mailbox"),
                               progress: UIL10n.string("Creating %@ on the mail server…", address),
                               done: UIL10n.string("The mailbox was created.")) { ops in
            try await ops.add(address: address, password: password)
            try await self.saveMailboxPassword(address: address, password: password)
        }
    }

    func setMailboxPassword(address: String, password: String) async {
        await runMailboxAction(title: UIL10n.string("Changing a mailbox password"),
                               progress: UIL10n.string("Setting a new password for %@…", address),
                               done: UIL10n.string("The password was changed.")) { ops in
            try await ops.setPassword(address: address, password: password)
            try await self.saveMailboxPassword(address: address, password: password)
        }
    }

    private func saveMailboxPassword(address: String, password: String) async throws {
        guard deployment.usesAgent, #available(macOS 15.0, iOS 18.0, *) else { return }
        guard let node = deployment.nodes.first(where: { $0.sshHost == deployment.host(running: .dockerMailserver) }) else { return }
        let host = Self.installReportKey(for: node, in: deployment)
        let entry = AccessVaultEntry.mailbox(host: host, address: address, password: password,
                                           at: Date(), writer: DeviceIdentity.uid)
        guard await AccessVault.push([entry], deployment: deployment) else {
            throw NSError(domain: "MailboxVault", code: 1, userInfo: [NSLocalizedDescriptionKey:
                UIL10n.string("The mailbox password was changed, but could not be saved to the shared password vault. Keep your copy of the new password.")])
        }
    }

    /// Destructive: the maildir goes with the account
    func deleteMailbox(address: String) async {
        await runMailboxAction(title: UIL10n.string("Removing a mailbox"),
                               progress: UIL10n.string("Deleting %@ and its messages…", address),
                               done: UIL10n.string("The mailbox was removed.")) { ops in
            try await ops.delete(address: address)
        }
    }

    private func runMailboxAction(title: String, progress: String, done: String,
                                  _ body: @escaping (any MailboxManaging) async throws -> Void) async {
        let operation = LongOperationState(title: title, progressText: progress)
        present(operation)
        do {
            try await body(try await mailboxOperations())
            operation.progressText = done
        } catch {
            operation.errorMessage = Self.message(for: error)
        }
        operation.isFinished = true
        await loadMailboxes()
    }

    /// Where a restore takes its archive from
    enum RestoreSource {
        /// A backup already sitting in the service's backup directory
        case serverPath(String)
        case deviceFile(data: Data, fileName: String)
    }

    /// Restores a service from a backup
    func runRestore(_ service: any ManagedService, from source: RestoreSource,
                    passphrase: String?) async {
        let operation = LongOperationState(
            title: UIL10n.string("Restoring %@", service.displayName),
            progressText: UIL10n.string("The restore may take a while. Keep the app open.")
        )
        present(operation)
        do {
            let (ops, runner) = try await operations(for: service)
            let path: String
            switch source {
            case .serverPath(let remote):
                path = remote
            case .deviceFile(let data, let name):
                guard let browser = runner as? any RemoteFileBrowser else {
                    throw ServerControlError.notConfigured(
                        UIL10n.string("File transfer is not available for this connection."))
                }
                operation.progressText = UIL10n.string("Uploading the backup to the server…")
                path = try await ops.uploadBackup(data, fileName: name, using: browser)
            }
            operation.progressText = UIL10n.string("Restoring — the service is offline meanwhile…")
            let seam = try await restoreSeam(for: service)
            operation.log = WrapperLogText.readable(
                try await seam.restore(service, archivePath: path, passphrase: passphrase) { chunk in
                    Task { @MainActor in
                        self.appendWrapperOutput(chunk, to: operation)
                    }
                })
            operation.progressText = UIL10n.string("Restore finished.")
        } catch {
            if await continuesOnServer(operation, after: error, kind: .restore, service: service) { return }
            operation.errorMessage = Self.message(for: error)
        }
        operation.isFinished = true
        await refreshService(service)
    }

    struct RestorableBackup: Identifiable {
        let entry: BackupEntry
        let path: String
        var id: String { path }
    }

    /// The backups this service can be restored from, newest first
    func restorableBackups(_ service: any ManagedService) async throws -> [RestorableBackup] {
        let (ops, _) = try await operations(for: service)
        guard let spec = ops.restoreSpec else { return [] }
        let seam = try await backupSeam(for: service)
        return try await seam.listBackups(of: service).map {
            RestorableBackup(entry: $0,
                             path: $0.name.hasPrefix("/") ? $0.name : "\(spec.backupDir)/\($0.name)")
        }
    }

    /// Which machine a finished backup of `service` is ON
    func backupDownloadHost(for service: ServiceID) -> SSHHostID {
        deployment.host(running: service)
    }

    func downloadBackup(_ service: any ManagedService, at path: String) async throws -> Data {
        try await downloadBackup(at: path, on: backupDownloadHost(for: service.id))
    }

    func downloadBackup(at path: String, on host: SSHHostID? = nil) async throws -> Data {
        let runner = try await session()
        guard let browser = runner as? any RemoteFileBrowser else {
            throw ServerControlError.notConfigured(UIL10n.string("File transfer is not available for this connection."))
        }
        return try await browser.downloadFile(path, on: host ?? deployment.servicesHost,
                                              maxBytes: FileBrowserViewModel.downloadLimit)
    }

    func runQuickAction(successMessage: String,
                                _ action: @escaping (any SSHCommandRunner) async throws -> Void) async {
        do {
            let runner = try await session()
            try await action(runner)
            quickActionResult = QuickActionResult(message: successMessage, isError: false)
        } catch {
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
        }
    }

    static func message(for error: Error) -> String {
        // A password prompt establishes missing permission, not an old setup.
        if case ServerControlError.sudoPasswordRequired = error {
            return UIL10n.string("The server does not allow this action without a sudo password. Check this account's permissions for the action.")
        }
        if let outdated = agentIsOlderThanTheApp(error) { return outdated }
        if #available(macOS 15.0, *), SSHAgentTransport.isDeadLink(error) {
            return UIL10n.string("The server stopped answering over SSH. Try again in a moment.")
        }
        return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    /// The agent has never heard of this service
    private static func agentIsOlderThanTheApp(_ error: Error) -> String? {
        guard AgentOutdated.matches(error), case AgentError.rpc(_, let message) = error else { return nil }
        return UIL10n.string(
            "This server's agent does not know that service — the agent on it is older than this app. Update the agent on the Operations page and try again. (%@)",
            message)
    }
}

/// The agent keeps installing after the stream dropped
struct InstallContinuesOnServer: Error {}

/// The job a move's install runs as
@MainActor
private final class MoveJobID {
    var value = ""
}
