import AgentControl
import Combine
import Foundation
import os
import ServerControl
import ServiceCatalog
import VPNProfile
import VPNTunnel
import WidgetKit
#if os(macOS)
import SystemExtensions
#endif
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class TunnelController: ObservableObject {
    static let shared = TunnelController()

    @Published private(set) var state: TunnelEngineState = .idle
    @Published private(set) var profiles: [TunnelProfile] = []
    /// What the big button acts on
    @Published var selectedID: UUID? {
        didSet {
            guard selectedID != oldValue else { return }
            profileStore.select(selectedID)
            writeSnapshot()
        }
    }
    @Published var errorMessage: String? {
        didSet {
            if let errorMessage { Self.log.error("connect stopped: \(errorMessage, privacy: .public)") }
        }
    }
    @Published private(set) var isProvisioningThisDevice = false

    static let log = Logger(subsystem: "com.skaymer.gryonixnexus", category: "tunnel")

    private let engine: any TunnelEngine
    private let profileStore: TunnelProfileStore
    private let sessionLog: TunnelSessionLog
    private let secrets: any TunnelSecretStoring
    private let snapshots: FleetSnapshotStore
    private let liveActivity: any TunnelActivityPresenting
    private let activitySettings: LiveActivitySettings

    private var runningSessionID: UUID?
    /// Rate limit for the statistics half of the snapshot
    private var lastStatisticsWrite = Date.distantPast
    private var lastSessionUpdate = Date.distantPast
    private static let statisticsWriteInterval: TimeInterval = 10

    private var watcher: Task<Void, Never>?

    init(engine: (any TunnelEngine)? = nil,
         profileStore: TunnelProfileStore = TunnelProfileStore(),
         sessionLog: TunnelSessionLog = TunnelSessionLog(),
         secrets: any TunnelSecretStoring = KeychainTunnelSecretStore(),
         snapshots: FleetSnapshotStore = FleetSnapshotStore(),
         liveActivity: (any TunnelActivityPresenting)? = nil,
         activitySettings: LiveActivitySettings? = nil) {
        let policy = { @Sendable in
            await MainActor.run { TunnelOnDemandSettings.shared.policy }
        }
        self.engine = engine
            ?? (TunnelAvailability.carriesTraffic
                ? SystemTunnelEngine(providers: MacTunnelPackaging.providers,
                                     runsAsSystemExtension: MacTunnelPackaging.usesSystemExtension,
                                     onDemand: policy)
                : SimulatedTunnelEngine())
        self.profileStore = profileStore
        self.sessionLog = sessionLog
        self.secrets = secrets
        self.snapshots = snapshots
        self.liveActivity = liveActivity ?? makeTunnelActivityPresenter()
        self.activitySettings = activitySettings ?? .shared
        self.profiles = profileStore.load()
        self.selectedID = profileStore.selectedID
        watch()
        writeSnapshot()
        TunnelIntents.target = self
        self.activitySettings.onChange = { [weak self] shows in
            self?.applyActivitySetting(shows)
        }
        self.activitySettings.onStyleChange = { [weak self] in
            self?.restyleLiveActivity()
        }
        TunnelOnDemandSettings.shared.onChange = { [weak self] _ in
            guard let system = self?.engine as? SystemTunnelEngine else { return }
            Task { await system.updateOnDemand() }
        }
    }

    deinit { watcher?.cancel() }

    // MARK: - What the screens ask

    var selected: TunnelProfile? {
        profiles.first { $0.id == selectedID } ?? profiles.first
    }

    var active: TunnelProfile? {
        guard state.status.isActive || state.status.isBusy else { return nil }
        return state.profileID.flatMap { id in profiles.first { $0.id == id } }
    }

    var status: TunnelStatus { state.status }

    var isDemonstration: Bool { !TunnelAvailability.carriesTraffic }

    func trafficThisMonth() -> TunnelStatistics {
        let start = Calendar.current.dateInterval(of: .month, for: Date())?.start
            ?? Date().addingTimeInterval(-30 * 86_400)
        return sessionLog.total(since: start)
    }

    func recentSessions(limit: Int = 20) -> [TunnelSession] {
        Array(sessionLog.sessions().prefix(limit))
    }

    // MARK: - Acting

    func toggle() async {
        if state.status.isActive || state.status == .connecting {
            await disconnect()
        } else {
            await connect()
        }
    }

    func connect(_ profile: TunnelProfile? = nil) async {
        Self.log.notice("connect: start")
        guard let chosen = profile ?? selected else {
            errorMessage = UIL10n.string("No tunnel yet. Open a device on one of your servers and choose “Use on this device”.")
            return
        }
        guard LicenseStore.isUnlocked || DemoServer.isDemo(chosen.serverID) else {
            errorMessage = LicenseGate.message(for: LicenseGate.reason)
            LicensePrompt.shared.allow()
            return
        }
        guard let profile = await knownToServer(chosen) else { return }
        guard let secret = secrets.secret(for: profile.secretAccount) else {
            errorMessage = UIL10n.string("This tunnel's configuration is no longer on this device. Open the device on its server and choose “Use on this device” again.")
            return
        }
        errorMessage = nil
        selectedID = profile.id
        Self.log.notice("connect: handing \(profile.protocolID.rawValue, privacy: .public) to the system")
        do {
            try await activateSystemExtensionIfCarried()
            try await engine.start(profile: profile, secret: secret)
        } catch {
            errorMessage = VPNText.message(for: error)
        }
    }

    /// Turns the Mac's tunnel extension on before its first use
    private func activateSystemExtensionIfCarried() async throws {
        #if os(macOS)
        guard MacTunnelPackaging.usesSystemExtension, engine is SystemTunnelEngine else { return }
        let activator = SystemExtensionActivator.shared
        activator.onNeedsApproval = { [weak self] in
            self?.errorMessage = UIL10n.string("Allow the gryonixNexus tunnel in System Settings → General → Login Items & Extensions → Network Extensions. It connects as soon as it is allowed.")
        }
        do {
            try await activator.activate()
            errorMessage = nil
        } catch let error as OSSystemExtensionError where error.code == .unsupportedParentBundleLocation {
            throw TunnelEngineError.systemRefused(UIL10n.string("Move gryonixNexus to the Applications folder and open it from there. macOS runs the tunnel only for apps in Applications."))
        }
        #endif
    }

    /// The profile its server still knows, recreated when forgotten
    private func knownToServer(_ profile: TunnelProfile) async -> TunnelProfile? {
        guard #available(macOS 15.0, *),
              let deployment = ((try? FileDeploymentStore().load()) ?? []).first(where: { $0.id == profile.serverID }),
              deployment.usesAgent else { return profile }
        isProvisioningThisDevice = true
        defer { isProvisioningThisDevice = false }
        let viewModel = DashboardViewModel(deployment: deployment)
        guard let clients = await Self.loadedClients(of: viewModel, protocolID: profile.protocolID) else {
            Self.log.notice("connect: server did not list devices in time")
            return profile
        }
        guard !clients.contains(where: { $0.id == profile.deviceID }) else {
            Self.log.notice("connect: server knows this device")
            return profile
        }
        Self.log.notice("connect: server forgot this device, adding it again")
        secrets.delete(profile.secretAccount)
        profileStore.remove(id: profile.id)
        reloadProfiles()
        errorMessage = nil
        await provisionNewDevice(with: viewModel, deployment: deployment, protocolID: profile.protocolID)
        let renewed = self.profile(serverID: profile.serverID, protocolID: profile.protocolID)
        if errorMessage == nil, renewed == nil {
            errorMessage = UIL10n.string("This tunnel's configuration is no longer on this device. Open the device on its server and choose “Use on this device” again.")
        }
        return errorMessage == nil ? renewed : nil
    }

    /// How long Connect waits for the client list
    private static let clientListWait: Duration = .seconds(6)

    /// The clients, or nil when the server stays silent
    private static func loadedClients(of viewModel: DashboardViewModel,
                                      protocolID: ServiceID) async -> [VPNClientDevice]? {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                await viewModel.loadVPNClients(protocol: protocolID)
                return true
            }
            group.addTask {
                try? await Task.sleep(for: clientListWait)
                return false
            }
            let answered = await group.next() ?? false
            group.cancelAll()
            guard answered, case .loaded(let clients) = viewModel.vpnClients else { return nil }
            return clients
        }
    }

    func disconnect() async {
        await engine.stop()
    }

    /// Picks a tunnel, switching a running one over
    func choose(_ profile: TunnelProfile) async {
        let running = state.status.isActive || state.status.isBusy
        selectedID = profile.id
        guard running, state.profileID != profile.id else { return }
        await engine.stop()
        await waitUntilDown()
        await connect(profile)
    }

    /// Waits for the old tunnel to finish going down
    private func waitUntilDown(timeout: Duration = .seconds(8)) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let current = await engine.state().status
            if !current.isActive, !current.isBusy { return }
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    // MARK: - Profiles

    @discardableResult
    func adopt(configurationText text: String,
               protocolID: ServiceID,
               serverID: UUID,
               serverName: String,
               deviceID: String,
               deviceName: String,
               dns: [String] = []) throws -> TunnelProfile {
        let existing = profileStore.load().first {
            $0.serverID == serverID && $0.protocolID == protocolID && $0.deviceID == deviceID
        }
        let built = try TunnelProfileBuilder.build(text: text, protocolID: protocolID,
                                                   serverID: serverID, serverName: serverName,
                                                   deviceID: deviceID, deviceName: deviceName,
                                                   reusing: existing)
        let proxy = protocolID == .shadowsocks || protocolID == .xrayReality
        let secret = proxy ? ProxyTunnelText.compose(link: built.secret, dns: dns) : built.secret
        try secrets.store(secret, for: built.profile.secretAccount)
        do {
            let stored = try profileStore.store(built.profile)
            reloadProfiles()
            return stored
        } catch {
            Self.log.error("profile not written: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Is this exact device already a tunnel here?
    func hasProfile(serverID: UUID, protocolID: ServiceID, deviceID: String) -> Bool {
        profiles.contains {
            $0.serverID == serverID && $0.protocolID == protocolID && $0.deviceID == deviceID
        }
    }

    func remove(_ profile: TunnelProfile) async {
        if state.profileID == profile.id, state.status.isActive || state.status.isBusy {
            await disconnect()
        }
        secrets.delete(profile.secretAccount)
        profileStore.remove(id: profile.id)
        reloadProfiles()
    }

    func removeProfiles(forServer serverID: UUID) async {
        for profile in profileStore.profiles(forServer: serverID) {
            await remove(profile)
        }
    }

    /// This device's tunnel to that server and protocol, if any
    func profile(serverID: UUID, protocolID: ServiceID) -> TunnelProfile? {
        profiles.first { $0.serverID == serverID && $0.protocolID == protocolID }
    }

    static var thisDeviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Device"
        #endif
    }

    func ownProfile(serverID: UUID, protocolID: ServiceID) -> TunnelProfile? {
        profiles.first {
            $0.serverID == serverID && $0.protocolID == protocolID && $0.deviceName == Self.thisDeviceName
        }
    }

    /// Connects this device, creating its server entry if needed
    func connectHere(deployment: Deployment, protocolID: ServiceID) async {
        await useAsThisDevice(deployment: deployment, protocolID: protocolID)
        guard errorMessage == nil,
              let profile = ownProfile(serverID: deployment.id, protocolID: protocolID) else { return }
        if !(state.status.isActive || state.status.isBusy) {
            await connect(profile)
        }
    }

    func useAsThisDevice(deployment: Deployment, protocolID: ServiceID, carry: TunnelCarry? = nil) async {
        guard LicensePrompt.shared.allow() else { return }
        if let refusal = VPNText.refusal(for: protocolID) {
            errorMessage = refusal
            return
        }
        let existing = ownProfile(serverID: deployment.id, protocolID: protocolID)
        guard #available(macOS 15.0, *) else {
            if let existing { await choose(existing) } else {
                errorMessage = UIL10n.string("This server is not managed over the panel's own connection.")
            }
            return
        }
        errorMessage = nil
        isProvisioningThisDevice = true
        defer { isProvisioningThisDevice = false }
        let viewModel = DashboardViewModel(deployment: deployment)
        await viewModel.loadVPNClients(protocol: protocolID)
        if let existing {
            guard case .loaded(let clients) = viewModel.vpnClients else { return await choose(existing) }
            if let current = clients.first(where: { $0.id == existing.deviceID }) {
                return await adoptAndChoose(current, from: viewModel, deployment: deployment,
                                            protocolID: protocolID, carry: carry)
            }
            await remove(existing)
        }
        await provisionNewDevice(with: viewModel, deployment: deployment, protocolID: protocolID, carry: carry)
    }

    /// Uses one device's configuration from the server here
    func use(_ client: VPNClientDevice, deployment: Deployment, protocolID: ServiceID) async {
        guard LicensePrompt.shared.allow() else { return }
        guard #available(macOS 15.0, *) else { return }
        errorMessage = nil
        isProvisioningThisDevice = true
        defer { isProvisioningThisDevice = false }
        let viewModel = DashboardViewModel(deployment: deployment)
        await adoptAndChoose(client, from: viewModel, deployment: deployment, protocolID: protocolID)
    }

    /// Creates this device on the server and connects with it
    @available(macOS 15.0, *)
    private func provisionNewDevice(with viewModel: DashboardViewModel, deployment: Deployment,
                                    protocolID: ServiceID, carry: TunnelCarry? = nil) async {
        let before = Set((viewModel.vpnClients.value ?? []).map(\.id))
        await viewModel.addVPNClient(protocol: protocolID, named: AgentDeviceEnrolment.deviceLabel,
                                     dns: carry?.dns ?? [])
        guard case .loaded(let clients) = viewModel.vpnClients,
              let created = clients.first(where: { !before.contains($0.id) }) else {
            errorMessage = viewModel.quickActionResult?.message
                ?? UIL10n.string("The server did not confirm a new device.")
            return
        }
        await adoptAndChoose(created, from: viewModel, deployment: deployment, protocolID: protocolID, carry: carry)
    }

    /// DNS the user picked, shown while it is being applied
    @Published private(set) var wantedDNS: [UUID: [String]] = [:]

    /// Changes this device's DNS on its server, newest pick last
    @available(macOS 15.0, *)
    func changeDNS(of profile: TunnelProfile, to dns: [String]) async {
        let idle = wantedDNS[profile.id] == nil
        wantedDNS[profile.id] = dns
        guard idle else { return }
        var applied: [String]?
        while let wanted = wantedDNS[profile.id], wanted != applied {
            await applyDNS(of: profiles.first { $0.id == profile.id } ?? profile, to: wanted)
            applied = wanted
        }
        wantedDNS[profile.id] = nil
    }

    @available(macOS 15.0, *)
    private func applyDNS(of profile: TunnelProfile, to dns: [String]) async {
        guard let deployment = ((try? FileDeploymentStore().load()) ?? []).first(where: { $0.id == profile.serverID }) else { return }
        let viewModel = DashboardViewModel(deployment: deployment)
        await viewModel.setVPNClientDNS(protocol: profile.protocolID, clientID: profile.deviceID, dns: dns)
        guard let configuration = await viewModel.vpnClientConfiguration(protocol: profile.protocolID,
                                                                         clientID: profile.deviceID) else {
            errorMessage = viewModel.quickActionResult?.message
                ?? UIL10n.string("Could not fetch the device's configuration.")
            return
        }
        do {
            let updated = try adopt(configurationText: configuration.text, protocolID: profile.protocolID,
                                    serverID: profile.serverID, serverName: profile.serverName,
                                    deviceID: profile.deviceID, deviceName: profile.deviceName,
                                    dns: configuration.dns)
            guard state.profileID == updated.id, state.status.isActive else { return }
            await engine.stop()
            await waitUntilDown()
            await connect(updated)
        } catch {
            errorMessage = VPNText.message(for: error)
        }
    }

    /// Fetches this device's configurations of one protocol again
    func refreshConfigurations(of deployment: Deployment, protocolID: ServiceID) async {
        for profile in profiles where profile.serverID == deployment.id && profile.protocolID == protocolID {
            let viewModel = DashboardViewModel(deployment: deployment)
            guard let configuration = await viewModel.vpnClientConfiguration(protocol: protocolID,
                                                                             clientID: profile.deviceID),
                  let updated = try? adopt(configurationText: configuration.text, protocolID: protocolID,
                                           serverID: profile.serverID, serverName: profile.serverName,
                                           deviceID: profile.deviceID, deviceName: profile.deviceName,
                                           dns: configuration.dns) else { continue }
            guard state.profileID == updated.id, state.status.isActive else { continue }
            await engine.stop()
            await waitUntilDown()
            await connect(updated)
        }
    }

    /// Reaches the tunnel's server by its address or its domain
    func reachByAddress(_ byAddress: Bool, profile: TunnelProfile) async {
        let pins = TunnelEndpointPins.shared
        if byAddress {
            do {
                _ = try await pins.pinAddress(of: profile)
            } catch {
                errorMessage = Self.message(for: error as? TunnelEndpointPins.Refusal ?? .notFound)
                return
            }
        } else {
            pins.unpin(profile)
        }
        errorMessage = nil
        guard state.profileID == profile.id, state.status.isActive else { return }
        await engine.stop()
        await waitUntilDown()
        await connect(profile)
    }

    private static func message(for refusal: TunnelEndpointPins.Refusal) -> String {
        switch refusal {
        case .notFound:
            return UIL10n.string("The server's address could not be found. Keep the domain name or try again later.")
        case .privateAddress(let address):
            return UIL10n.string("The domain points to a private address (%@). Keep the domain name.", address)
        }
    }

    /// Takes the server's current configuration of a device and connects
    @available(macOS 15.0, *)
    private func adoptAndChoose(_ client: VPNClientDevice, from viewModel: DashboardViewModel,
                                deployment: Deployment, protocolID: ServiceID, carry: TunnelCarry? = nil) async {
        guard let configuration = await carriedConfiguration(of: client.id, protocolID: protocolID,
                                                             from: viewModel, carry: carry) else {
            errorMessage = viewModel.quickActionResult?.message
                ?? UIL10n.string("Could not fetch the device's configuration.")
            return
        }
        do {
            let profile = try adopt(configurationText: configuration.text,
                                    protocolID: protocolID,
                                    serverID: deployment.id,
                                    serverName: deployment.name,
                                    deviceID: client.id,
                                    deviceName: client.name,
                                    dns: configuration.dns)
            await applyReach(carry, to: profile)
            await choose(profile)
        } catch {
            errorMessage = VPNText.message(for: error)
        }
    }

    private func reloadProfiles() {
        profiles = profileStore.load()
        selectedID = profileStore.selectedID
        writeSnapshot()
    }

    // MARK: - Following the engine

    /// Follows the engine for the life of the controller
    private func watch() {
        watcher = Task { [weak self] in
            guard let self else { return }
            _ = await self.engine.state()
            for await state in self.engine.events() {
                self.apply(state)
            }
        }
    }

    private func apply(_ new: TunnelEngineState) {
        let previous = state
        state = new
        recordSession(from: previous, to: new)
        writeSnapshot(statusChanged: previous.status != new.status)
        dropServerLinksOnRouteChange(from: previous, to: new)
        updateLiveActivity(from: previous, to: new)
    }

    /// SSH sessions opened over the old route stop answering
    private func dropServerLinksOnRouteChange(from previous: TunnelEngineState, to new: TunnelEngineState) {
        guard previous.status.isActive != new.status.isActive, !isDemonstration else { return }
        DashboardSessionFactory.invalidateAll()
    }

    private func updateLiveActivity(from previous: TunnelEngineState, to new: TunnelEngineState) {
        if !previous.status.isActive, new.status.isActive {
            startLiveActivity(for: new)
        } else if previous.status.isActive, !new.status.isActive {
            liveActivity.end(statistics: new.statistics)
        } else if new.status.isActive, activitySettings.showsVPNSession {
            liveActivity.update(status: new.status, statistics: new.statistics)
        }
    }

    private func startLiveActivity(for state: TunnelEngineState) {
        guard activitySettings.showsVPNSession,
              let profile = active ?? selected, let since = state.status.activeSince else { return }
        liveActivity.start(profile: profile, since: since,
                           isSimulated: isDemonstration,
                           statistics: state.statistics,
                           style: activitySettings.vpnIslandStyle)
    }

    /// The Live Activity switch flipped mid-session
    private func applyActivitySetting(_ shows: Bool) {
        if shows {
            if state.status.isActive { startLiveActivity(for: state) }
        } else {
            liveActivity.end(statistics: state.statistics)
        }
    }

    private func recordSession(from previous: TunnelEngineState, to new: TunnelEngineState) {
        let wasUp = previous.status.isActive
        let isUp = new.status.isActive

        if !wasUp, isUp, let profile = active ?? selected {
            let session = TunnelSession(profileID: profile.id,
                                        serverName: profile.serverName,
                                        protocolName: profile.protocolID.displayName,
                                        deviceName: profile.deviceName,
                                        startedAt: new.status.activeSince ?? Date(),
                                        wasSimulated: isDemonstration)
            sessionLog.begin(session)
            runningSessionID = session.id
            return
        }

        if let id = runningSessionID {
            if isUp {
                let now = Date()
                if now.timeIntervalSince(lastSessionUpdate) >= Self.statisticsWriteInterval {
                    lastSessionUpdate = now
                    sessionLog.update(id: id, statistics: new.statistics)
                }
            } else {
                sessionLog.end(id: id, statistics: new.statistics,
                               failureReason: new.status.failureReason)
                runningSessionID = nil
            }
            return
        }

        if let reason = new.status.failureReason, let profile = active ?? selected {
            let now = Date()
            let session = TunnelSession(profileID: profile.id,
                                        serverName: profile.serverName,
                                        protocolName: profile.protocolID.displayName,
                                        deviceName: profile.deviceName,
                                        startedAt: now, endedAt: now,
                                        failureReason: reason,
                                        wasSimulated: isDemonstration)
            sessionLog.begin(session)
            sessionLog.end(id: session.id, at: now, statistics: .zero, failureReason: reason)
        }
    }

    private func writeSnapshot(statusChanged: Bool = true) {
        let now = Date()
        guard statusChanged || now.timeIntervalSince(lastStatisticsWrite) >= Self.statisticsWriteInterval
        else { return }
        lastStatisticsWrite = now

        let profile = active ?? selected
        snapshots.writeTunnel(TunnelSnapshot(status: state.status,
                                             profileID: profile?.id,
                                             profileName: profile?.deviceName,
                                             serverName: profile?.serverName,
                                             protocolName: profile?.protocolID.displayName,
                                             statistics: state.statistics,
                                             isSimulated: isDemonstration,
                                             profileCount: profiles.count))
        if statusChanged { WidgetRefresh.reload() }
    }
}

extension TunnelController: TunnelIntentTarget {
    func intentConnect() async { await connect() }
    func intentDisconnect() async { await disconnect() }

    /// The island's stop: the first tap asks, the second disconnects
    func intentIslandStop() async {
        guard liveActivity.isStopArmed else {
            liveActivity.setStopArmed(true)
            try? await Task.sleep(for: .seconds(OperationStopper.armedSeconds))
            if liveActivity.isStopArmed { liveActivity.setStopArmed(false) }
            return
        }
        liveActivity.setStopArmed(false)
        await disconnect()
    }

    /// The island's look changed, so its session starts over
    private func restyleLiveActivity() {
        guard state.status.isActive, activitySettings.showsVPNSession else { return }
        liveActivity.end(statistics: state.statistics)
        startLiveActivity(for: state)
    }
    func intentOpenApp() { AppNavigator.shared.open(.app) }
}

/// Asking the widgets to redraw, in one place
enum WidgetRefresh {
    static func reload() {
        #if !targetEnvironment(simulator)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
