import Foundation
@preconcurrency import NetworkExtension
import os
import ServiceCatalog
import VPNProfile
import VPNTunnel

public actor SystemTunnelEngine: TunnelEngine {
    private let providers: TunnelProviders
    /// System extensions cannot reach the user's Keychain
    private let runsAsSystemExtension: Bool
    private let onDemand: @Sendable () async -> TunnelOnDemandPolicy

    private var manager: NETunnelProviderManager?
    private var current: TunnelEngineState = .idle
    private var currentProfileID: UUID?
    private var listeners: [UUID: AsyncStream<TunnelEngineState>.Continuation] = [:]
    /// When the current session began
    private var connectedSince: Date?
    private var stopRequested = false
    private var watcher: Task<Void, Never>?
    private var counters: Task<Void, Never>?

    private static let counterInterval = Duration.seconds(1)
    private static let log = Logger(subsystem: "com.skaymer.gryonixnexus", category: "tunnel")

    init(providers: TunnelProviders = .appExtensions,
                runsAsSystemExtension: Bool = false,
                onDemand: @escaping @Sendable () async -> TunnelOnDemandPolicy = { .off }) {
        self.providers = providers
        self.runsAsSystemExtension = runsAsSystemExtension
        self.onDemand = onDemand
    }

    // MARK: - TunnelEngine

    public func state() async -> TunnelEngineState {
        await adoptRunningTunnel()
        return current
    }

    /// Picks up a tunnel the system already runs
    private func adoptRunningTunnel() async {
        guard manager == nil, let all = try? await loadAll(),
              let found = all.first(where: { Self.isUp($0.connection) }) ?? all.first else { return }
        manager = found
        let configuration = (found.protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        currentProfileID = (configuration?[VPNTunnelKeys.profileID] as? String).flatMap(UUID.init(uuidString:))
        watch(found)
    }

    public nonisolated func events() -> AsyncStream<TunnelEngineState> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.unregister(id: id) }
            }
        }
    }

    public func start(profile: TunnelProfile, secret: String) async throws {
        guard let datapath = TunnelCapableProtocols.datapath(for: profile.protocolID),
              TunnelCapableProtocols.integrated.contains(datapath) else {
            throw TunnelEngineError.protocolNotCarried(profile.protocolID)
        }
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TunnelEngineError.configurationMissing
        }

        let bundleID = providers.bundleID(for: datapath)
        for other in try await loadAll() where Self.bundleID(of: other) != bundleID {
            await stopRunning(other.connection)
        }
        let manager = try await load(bundleID) ?? NETunnelProviderManager()
        await stopRunning(manager.connection)
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = bundleID
        proto.serverAddress = profile.endpoint
        var configuration = Self.providerConfiguration(secret: secret, datapath: datapath,
                                                       inline: runsAsSystemExtension)
        configuration[VPNTunnelKeys.profileID] = profile.id.uuidString
        let pin = await MainActor.run { TunnelEndpointPins.shared.pin(for: profile) }
        configuration.merge(pin?.providerEntries ?? [:]) { _, pinned in pinned }
        proto.providerConfiguration = configuration
        manager.protocolConfiguration = proto
        manager.localizedDescription = profile.systemName
        manager.isEnabled = true
        apply(await onDemand(), to: manager)

        do {
            Self.log.notice("engine: saving the VPN configuration")
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            Self.log.notice("engine: saved, starting the tunnel")
            self.manager = manager
            currentProfileID = profile.id
            watch(manager)
            publish(.connecting)
            try (manager.connection as? NETunnelProviderSession)?.startVPNTunnel()
        } catch {
            Self.log.error("engine: system refused: \(String(describing: error), privacy: .public)")
            publish(.failed(reason: error.localizedDescription))
            throw TunnelEngineError.systemRefused(error.localizedDescription)
        }
    }

    /// Keychain by default, inline for system extensions
    static func providerConfiguration(secret: String, datapath: TunnelDatapath,
                                      inline: Bool = false) -> [String: Any] {
        var configuration: [String: Any] = [VPNTunnelKeys.datapath: datapath.rawValue]
        if !inline, SharedTunnelSecret.store(secret) {
            configuration[VPNTunnelKeys.configAccount] = SharedTunnelSecret.activeAccount
        } else {
            configuration[VPNTunnelKeys.config] = secret
        }
        return configuration
    }

    /// Stops a tunnel the system still runs
    private func stopRunning(_ connection: NEVPNConnection, timeout: Duration = .seconds(8)) async {
        guard connection.status != .disconnected, connection.status != .invalid else { return }
        Self.log.notice("engine: stopping the running tunnel first")
        stopRequested = true
        connection.stopVPNTunnel()
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline, connection.status != .disconnected, connection.status != .invalid {
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    public func stop() async {
        await adoptRunningTunnel()
        let all = (try? await loadAll()) ?? manager.map { [$0] } ?? []
        guard !all.isEmpty else { return }
        stopRequested = true
        publish(.disconnecting)
        for each in all {
            if each.isOnDemandEnabled {
                each.isOnDemandEnabled = false
                try? await each.saveToPreferences()
            }
            if Self.isUp(each.connection) { each.connection.stopVPNTunnel() }
        }
    }

    private static func isUp(_ connection: NEVPNConnection) -> Bool {
        connection.status != .disconnected && connection.status != .invalid
    }

    // MARK: - On demand

    public func updateOnDemand() async {
        guard let manager = try? await loadAll().first(where: \.isEnabled) else { return }
        apply(await onDemand(), to: manager)
        try? await manager.saveToPreferences()
        self.manager = manager
    }

    private func apply(_ policy: TunnelOnDemandPolicy, to manager: NETunnelProviderManager) {
        manager.isOnDemandEnabled = policy.isEnabled
        manager.onDemandRules = policy.rules.map(Self.systemRule)
    }

    private static func systemRule(_ rule: TunnelOnDemandPolicy.Rule) -> NEOnDemandRule {
        switch rule {
        case .disconnectOnWiFi(let networks):
            return wiFi(NEOnDemandRuleDisconnect(), networks)
        case .connectOnWiFi(let networks):
            return wiFi(NEOnDemandRuleConnect(), networks)
        case .connectOnCellular:
            return cellular(NEOnDemandRuleConnect())
        case .disconnectOnCellular:
            return cellular(NEOnDemandRuleDisconnect())
        case .connectOnAnything:
            let connect = NEOnDemandRuleConnect()
            connect.interfaceTypeMatch = .any
            return connect
        }
    }

    private static func wiFi(_ rule: NEOnDemandRule, _ networks: [String]) -> NEOnDemandRule {
        rule.interfaceTypeMatch = .wiFi
        if !networks.isEmpty { rule.ssidMatch = networks }
        return rule
    }

    private static func cellular(_ rule: NEOnDemandRule) -> NEOnDemandRule {
        #if os(iOS)
        rule.interfaceTypeMatch = .cellular
        #else
        rule.interfaceTypeMatch = .any
        #endif
        return rule
    }

    // MARK: - What the system is doing

    /// The configuration of one tunnel extension
    private func load(_ bundleID: String) async throws -> NETunnelProviderManager? {
        try await loadAll().first { Self.bundleID(of: $0) == bundleID }
    }

    /// Every configuration of this app's tunnel extensions
    private func loadAll() async throws -> [NETunnelProviderManager] {
        let all = try await NETunnelProviderManager.loadAllFromPreferences()
        return all.filter { Self.bundleID(of: $0).map(providers.all.contains) ?? false }
    }

    private static func bundleID(of manager: NETunnelProviderManager) -> String? {
        (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
    }

    private func watch(_ manager: NETunnelProviderManager) {
        watcher?.cancel()
        let connection = manager.connection
        watcher = Task { [weak self] in
            let changes = NotificationCenter.default.notifications(
                named: .NEVPNStatusDidChange, object: connection)
            for await _ in changes {
                await self?.statusChanged(connection.status)
            }
        }
        statusChanged(connection.status)
    }

    private func statusChanged(_ status: NEVPNStatus) {
        Self.log.notice("engine: system status \(status.rawValue, privacy: .public)")
        switch status {
        case .connecting:
            stopRequested = false
            publish(.connecting)
        case .connected:
            let since = connectedSince ?? manager?.connection.connectedDate ?? Date()
            connectedSince = since
            publish(.connected(since: since))
            pollCounters()
        case .reasserting:
            publish(.reasserting(since: connectedSince ?? Date()))
        case .disconnecting:
            publish(.disconnecting)
        case .disconnected, .invalid:
            let wasStarting = current.status == .connecting
            let unasked = !stopRequested && current.status != .off
            connectedSince = nil
            counters?.cancel()
            counters = nil
            publish(.off)
            if wasStarting || unasked { Task { await reportStopReason(wasStarting: wasStarting) } }
        @unknown default:
            publish(.off)
        }
    }

    /// Publishes why a tunnel stopped that nobody stopped
    private func reportStopReason(wasStarting: Bool) async {
        guard let connection = manager?.connection else { return }
        let error = await Self.lastDisconnectError(of: connection)
        Self.log.notice("engine: stop reason \(error.map { String(describing: $0) } ?? "none", privacy: .public)")
        guard current.status == .off else { return }
        if let error {
            let detail = TunnelStopRecord().explanation()
            publish(.failed(reason: [Self.reason(error), detail].compactMap { $0 }.joined(separator: "\n")))
        } else if wasStarting {
            publish(.failed(reason: UIL10n.string(
                "The system stopped the tunnel before it connected and gave no reason. Check that gryonixNexus is allowed in System Settings → VPN, then try again.")))
        } else if !runsAsSystemExtension, TunnelStopRecord().read() == nil {
            publish(.failed(reason: TunnelSession.stoppedByItselfMarker))
        }
    }

    /// The system's answer, or nil when it stays silent
    private static func lastDisconnectError(of connection: NEVPNConnection) async -> Error? {
        await withCheckedContinuation { done in
            let once = FirstAnswer(done)
            connection.fetchLastDisconnectError { once.resume($0) }
            DispatchQueue.global().asyncAfter(deadline: .now() + stopReasonWait) { once.resume(nil) }
        }
    }

    /// How long the stop reason is waited for
    private static let stopReasonWait: TimeInterval = 2

    /// The tunnel's own message, not NetworkExtension's wrapper
    static func reason(_ error: Error) -> String {
        let wrapped = error as NSError
        let inner = wrapped.userInfo[NSUnderlyingErrorKey] as? NSError
        return inner?.localizedDescription ?? wrapped.localizedDescription
    }

    private func pollCounters() {
        guard counters == nil else { return }
        counters = Task { [weak self] in
            while !Task.isCancelled {
                await self?.readCounters()
                try? await Task.sleep(for: Self.counterInterval)
            }
        }
    }

    private func readCounters() async {
        guard let session = manager?.connection as? NETunnelProviderSession,
              session.status == .connected || session.status == .reasserting
        else { return }
        let reply: Data? = await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(TunnelProviderMessage.statisticsRequest) {
                    continuation.resume(returning: $0)
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }
        guard let answer = TunnelProviderMessage.Statistics.decoded(reply) else { return }
        var next = current
        next.statistics = TunnelStatistics(received: answer.received,
                                           sent: answer.sent,
                                           lastHandshake: answer.lastHandshake)
        current = next
        broadcast()
    }

    // MARK: - The stream

    private func publish(_ status: TunnelStatus) {
        guard current.status != status else { return }
        current.status = status
        current.profileID = status == .off ? nil : currentProfileID
        if case .connecting = status { current.statistics = .zero }
        broadcast()
    }

    private func broadcast() {
        for continuation in listeners.values { continuation.yield(current) }
    }

    private func register(id: UUID, continuation: AsyncStream<TunnelEngineState>.Continuation) {
        listeners[id] = continuation
        continuation.yield(current)
    }

    private func unregister(id: UUID) { listeners[id] = nil }
}

/// Resumes a continuation from whichever caller comes first
private final class FirstAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Error?, Never>?

    init(_ continuation: CheckedContinuation<Error?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Error?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
