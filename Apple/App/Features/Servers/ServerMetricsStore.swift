import AgentControl
import Foundation
import ServerControl
import ServerControlSSH

struct ServerHostMetricsState: Equatable {
    var snapshot: HostMetricsSnapshot?
    var errorMessage: String?
    /// When the machine last answered
    var lastSeen: Date?
    /// When the current silence began
    var offlineSince: Date?

    /// True until the first reading or failure arrives
    var isConnecting: Bool { snapshot == nil && errorMessage == nil }

    var liveSnapshot: HostMetricsSnapshot? { errorMessage == nil ? snapshot : nil }
}

@MainActor
final class ServerCardMetrics: ObservableObject {
    @Published private(set) var hosts: [SSHHostID: ServerHostMetricsState] = [:]

    func state(for host: SSHHostID) -> ServerHostMetricsState {
        hosts[host] ?? ServerHostMetricsState()
    }

    /// The only way in
    func record(_ state: ServerHostMetricsState, for host: SSHHostID) {
        hosts[host] = state
    }
}

@MainActor
final class ServerMetricsStore: ObservableObject {
    private var cards: [UUID: ServerCardMetrics] = [:]

    func card(for deploymentID: UUID) -> ServerCardMetrics {
        if let existing = cards[deploymentID] { return existing }
        let fresh = ServerCardMetrics()
        cards[deploymentID] = fresh
        return fresh
    }

    private struct Poller {
        let deployment: Deployment
        let task: Task<Void, Never>
    }

    private var pollers: [UUID: Poller] = [:]
    private let pollInterval: Duration = .seconds(5)
    /// Never rebuild one deployment's session more often than this
    static let restartSpacing: TimeInterval = 120
    private var lastRestart: [UUID: Date] = [:]
    /// When each poller started, and each host last answered
    private var pollStarted: [UUID: Date] = [:]
    private var heard: [UUID: [SSHHostID: Date]] = [:]
    private var watchdog: Task<Void, Never>?

    /// The deployment fields the polling session is actually built from
    struct ConnectionFingerprint: Equatable {
        let entry: HostEndpoint
        let homeWGAddress: String?
        let machines: [SSHHostID: HostEndpoint]
        let usesPasswordAuth: Bool
        let usesAgent: Bool
        let quickSeconds: Int

        init(_ deployment: Deployment) {
            entry = deployment.entry
            homeWGAddress = deployment.homeWGAddress
            machines = Dictionary(deployment.nodes.map { ($0.sshHost, $0.endpoint) },
                                  uniquingKeysWith: { first, _ in first })
            usesPasswordAuth = deployment.usesPasswordAuth
            usesAgent = deployment.usesAgent
            quickSeconds = deployment.timeouts.quickSeconds
        }
    }

    func sync(with deployments: [Deployment]) {
        let wanted = Dictionary(deployments.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })

        for (id, poller) in pollers {
            guard let updated = wanted[id] else {
                poller.task.cancel()
                pollers[id] = nil
                continue
            }
            if ConnectionFingerprint(updated) != ConnectionFingerprint(poller.deployment) {
                poller.task.cancel()
                pollers[id] = nil
            } else if updated != poller.deployment {
                pollers[id] = Poller(deployment: updated, task: poller.task)
            }
        }
        cards = cards.filter { wanted[$0.key] != nil }

        for deployment in deployments where pollers[deployment.id] == nil {
            start(deployment)
        }
    }

    func restartPoller(for deploymentID: UUID) {
        guard let poller = pollers[deploymentID] else { return }
        poller.task.cancel()
        pollers[deploymentID] = nil
        start(poller.deployment)
    }

    func retryFailedHosts() {
        for (id, poller) in pollers where isFailing(id) {
            poller.task.cancel()
            pollers[id] = nil
            start(poller.deployment)
        }
    }

    private func isFailing(_ id: UUID) -> Bool {
        let card = cards[id]
        guard let states = card?.hosts.values, !states.isEmpty else { return false }
        return states.allSatisfy { $0.errorMessage != nil }
    }

    /// Pull-to-refresh: stop waiting and probe every server NOW
    func reconnectAll(_ deployments: [Deployment]) async {
        for poller in pollers.values { poller.task.cancel() }
        pollers = [:]
        for deployment in deployments { start(deployment) }
    }

    func stopAll() {
        for poller in pollers.values { poller.task.cancel() }
        pollers = [:]
        DashboardSessionFactory.invalidateAll()
    }

    private func start(_ deployment: Deployment) {
        let hosts: [SSHHostID] = deployment.nodes.map(\.sshHost)
        publishCached(deployment, hosts: hosts)
        pollStarted[deployment.id] = Date()
        heard[deployment.id] = nil
        startWatchdog()
        if DemoHostMetrics.covers(deployment) {
            startDemo(deployment, hosts: hosts)
            return
        }
        if deployment.usesAgent, #available(macOS 15.0, *) {
            startAgent(deployment)
            return
        }
        startSSH(deployment, hosts: hosts)
    }

    /// Keeps when the machine last answered, without its numbers
    private func publishCached(_ deployment: Deployment, hosts: [SSHHostID]) {
        for host in hosts where state(forID: deployment.id, host: host).lastSeen == nil {
            guard let row = MetricsCache.shared.latestPoint(deploymentID: deployment.id, host: host)
            else { continue }
            var state = state(forID: deployment.id, host: host)
            state.lastSeen = row.date
            card(for: deployment.id).record(state, for: host)
        }
    }

    private func startWatchdog() {
        guard watchdog == nil else { return }
        watchdog = Task { [weak self, pollInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                self?.markSilentHosts()
            }
        }
    }

    /// Silent hosts go offline; a hung stream is restarted
    private func markSilentHosts(now: Date = Date()) {
        for (id, poller) in pollers {
            guard let started = pollStarted[id] else { continue }
            var restart = false
            let silence = ConnectionSettings.silence()
            let grace = ConnectionSettings.firstAnswerGrace()
            let reconnect = ConnectionSettings.reconnect()
            for host in poller.deployment.nodes.map(\.sshHost) {
                let last = heard[id]?[host]
                let quiet = now.timeIntervalSince(last ?? started)
                guard quiet > (last == nil ? grace : silence) else { continue }
                if state(forID: id, host: host).errorMessage == nil {
                    fail(id, hosts: [host], error: SilentHost())
                }
                if last != nil, let reconnect, quiet > reconnect { restart = true }
            }
            let spacing = max(Self.restartSpacing, reconnect ?? 0)
            if restart, now.timeIntervalSince(lastRestart[id] ?? .distantPast) > spacing {
                lastRestart[id] = now
                restartPoller(for: id)
            }
        }
    }

    /// The machine stopped answering without an error
    struct SilentHost: LocalizedError {
        var errorDescription: String? {
            UIL10n.string("The server has not answered for %lld seconds.", Int(ConnectionSettings.silence()))
        }
    }

    private func startSSH(_ deployment: Deployment, hosts: [SSHHostID]) {
        let task = Task(operation: sshLoop(deployment, hosts: hosts))
        pollers[deployment.id] = Poller(deployment: deployment, task: task)
    }

    /// Probes the given machines over SSH until cancelled
    private func sshLoop(_ deployment: Deployment,
                         hosts: [SSHHostID]) -> @Sendable @MainActor () async -> Void {
        { [weak self, pollInterval] in
            var runner: (any SSHCommandRunner & RemoteFileBrowser)?
            var previous: [SSHHostID: HostMetricsSample] = [:]
            var consecutiveFailures = 0
            var seeded = false

            while !Task.isCancelled {
                let active: any SSHCommandRunner & RemoteFileBrowser
                if let runner {
                    active = runner
                } else {
                    do {
                        active = try await DashboardSessionFactory.makeRunnerDetached(deployment: deployment)
                        runner = active
                    } catch {
                        self?.fail(deployment.id, hosts: hosts, error: error)
                        try? await Task.sleep(for: pollInterval)
                        continue
                    }
                }
                if !seeded {
                    seeded = true
                    let reader = MetricsHistoryProbe(
                        runner: active, timeout: .seconds(deployment.timeouts.quickSeconds))
                    for host in hosts {
                        await self?.seedFromCollector(deployment.id, host: host, reader: reader)
                    }
                }
                let probe = HostMetricsProbe(runner: active,
                                             timeout: .seconds(deployment.timeouts.quickSeconds))
                var failed: [SSHHostID] = []
                for host in hosts {
                    if Task.isCancelled { break }
                    do {
                        let sample = try await probe.sample(on: host)
                        let snapshot = HostMetricsSnapshot(current: sample, previous: previous[host])
                        previous[host] = sample
                        self?.publish(deployment.id, host: host,
                                      state: ServerHostMetricsState(snapshot: snapshot))
                    } catch is CancellationError {
                        break
                    } catch {
                        previous[host] = nil
                        failed.append(host)
                        self?.fail(deployment.id, hosts: [host], error: error)
                    }
                }
                switch MetricsPollRecovery.after(failed: failed) {
                case .none:
                    break
                case .rebuildRunner:
                    await DashboardSessionFactory.release(active, deploymentID: deployment.id)
                    runner = nil
                case .dropLinks(let hosts):
                    guard let citadel = active as? CitadelCommandRunner else { break }
                    for host in hosts { await citadel.invalidate(host) }
                }
                if !failed.isEmpty {
                    consecutiveFailures = min(consecutiveFailures + 1, 3)
                } else {
                    consecutiveFailures = 0
                }
                try? await Task.sleep(for: pollInterval * (1 << consecutiveFailures))
            }
            await DashboardSessionFactory.release(runner, deploymentID: deployment.id)
        }
    }

    @available(macOS 15.0, *)
    private func startAgent(_ deployment: Deployment) {
        let host = deployment.servicesHost
        let others = deployment.nodes.map(\.sshHost).filter { $0 != host }
        let agent = agentLoop(deployment, host: host)
        let ssh = others.isEmpty ? nil : sshLoop(deployment, hosts: others)
        let task = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await agent() }
                if let ssh { group.addTask { await ssh() } }
            }
        }
        pollers[deployment.id] = Poller(deployment: deployment, task: task)
    }

    /// Streams the agent machine's numbers until cancelled
    @available(macOS 15.0, *)
    private func agentLoop(_ deployment: Deployment,
                           host: SSHHostID) -> @Sendable @MainActor () async -> Void {
        { [weak self, pollInterval] in
            var consecutiveFailures = 0
            var seeded = false
            while !Task.isCancelled {
                var session: AgentConnection.Session?
                var failed = false
                do {
                    let opened = try await AgentConnection.open(deployment: deployment, shared: true)
                    session = opened
                    if !seeded {
                        seeded = true
                        let reader = AgentMetricsHistory(client: opened.client,
                                                         gate: .shared(for: deployment.id),
                                                         window: Self.seedWindow)
                        Task { [weak self] in
                            await self?.seedFromCollector(deployment.id, host: host, reader: reader)
                        }
                    }
                    var accumulator = AgentMetricsAccumulator()
                    var previous: HostMetricsSample?
                    for try await sample in opened.client.hostMetrics() {
                        if Task.isCancelled { break }
                        let current = accumulator.hostSample(from: sample)
                        let snapshot = HostMetricsSnapshot(current: current, previous: previous)
                        previous = current
                        consecutiveFailures = 0
                        self?.publish(deployment.id, host: host,
                                      state: ServerHostMetricsState(snapshot: snapshot))
                    }
                } catch is CancellationError {
                    await DashboardSessionFactory.release(session?.runner,
                                                          deploymentID: deployment.id)
                    break
                } catch {
                    self?.fail(deployment.id, hosts: [host], error: error)
                    consecutiveFailures = min(consecutiveFailures + 1, 3)
                    failed = true
                }
                if failed {
                    await DashboardSessionFactory.release(session?.runner,
                                                          deploymentID: deployment.id)
                }
                if Task.isCancelled { break }
                try? await Task.sleep(for: pollInterval * (1 << consecutiveFailures))
            }
        }
    }

    private func publish(_ id: UUID, host: SSHHostID, state: ServerHostMetricsState) {
        let now = Date()
        var state = state
        state.lastSeen = now
        heard[id, default: [:]][host] = now
        card(for: id).record(state, for: host)
    }

    /// How far back the seed read looks
    private static let seedWindow: TimeInterval = 120

    private func seedFromCollector(_ id: UUID, host: SSHHostID,
                                   reader: any MetricsHistoryReading) async {
        guard let rows = try? await reader.history(bucket: .tenSeconds, on: host),
              let row = rows.last else { return }
        MetricsCache.shared.store(rows, for: MetricPanel.Source(deploymentID: id,
                                                               host: host,
                                                               bucket: .tenSeconds))
        guard state(forID: id, host: host).snapshot?.isPartial ?? true else { return }
        publish(id, host: host,
                state: ServerHostMetricsState(snapshot: HostMetricsSnapshot(collectorRow: row)))
    }

    private func state(forID id: UUID, host: SSHHostID) -> ServerHostMetricsState {
        card(for: id).state(for: host)
    }

    private func fail(_ id: UUID, hosts: [SSHHostID], error: Error) {
        let box = card(for: id)
        for host in hosts {
            var state = box.state(for: host)
            if state.errorMessage == nil { state.offlineSince = Date() }
            state.errorMessage = error.localizedDescription
            box.record(state, for: host)
        }
    }

    func state(for deployment: Deployment, host: SSHHostID) -> ServerHostMetricsState {
        card(for: deployment.id).state(for: host)
    }

    private func startDemo(_ deployment: Deployment, hosts: [SSHHostID]) {
        let task = Task { [weak self, pollInterval] in
            var tick: UInt64 = 1
            while !Task.isCancelled {
                for host in hosts {
                    if DemoHostMetrics.isSilent(deployment, host: host) {
                        self?.fail(deployment.id, hosts: [host], error: SilentHost())
                        continue
                    }
                    self?.publish(deployment.id, host: host,
                                  state: ServerHostMetricsState(
                                      snapshot: DemoHostMetrics.snapshot(
                                          deploymentID: deployment.id, host: host, tick: tick)))
                }
                tick += 1
                try? await Task.sleep(for: pollInterval)
            }
        }
        pollers[deployment.id] = Poller(deployment: deployment, task: task)
    }
}

enum DemoHostMetrics {
    static var isEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_METRICS"] != nil
        #else
        return false
        #endif
    }

    /// The demo home machine stays silent, for wake-up checks
    static func isSilent(_ deployment: Deployment, host: SSHHostID) -> Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_SILENT_HOME"] != nil
            && WakeOnLANAvailability.target(in: deployment)?.sshHost == host
        #else
        false
        #endif
    }

    /// Whether THIS deployment's readings are generated
    static func covers(_ deployment: Deployment) -> Bool {
        DemoServer.isDemo(deployment) || isEnabled
    }

    /// Seconds between two generated samples
    private static let tickSeconds: Double = 5

    private static func profile(deploymentID: UUID, host: SSHHostID) -> DemoMachineProfile {
        if let named = DemoServer.profile(deploymentID: deploymentID, host: host) { return named }
        return .derived(seed: seed(deploymentID: deploymentID, host: host))
    }

    /// A system disk and a data array for the demo
    static func diskHistory(_ points: [MetricsHistoryPoint]) -> [DiskHistoryPoint] {
        points.enumerated().flatMap { index, point -> [DiskHistoryPoint] in
            let system = Int64(point.diskUsedFraction * 256_000_000_000)
            let storage = Int64((0.55 + 0.1 * sin(Double(index) / 40)) * 4_000_000_000_000)
            return [DiskHistoryPoint(date: point.date, mount: "/", usedBytes: system, totalBytes: 256_000_000_000),
                    DiskHistoryPoint(date: point.date, mount: "/srv/gryonixnexus-storage",
                                     usedBytes: storage, totalBytes: 4_000_000_000_000)]
        }
    }

    /// Stores a parts estimate matching the demo machine's size
    @MainActor
    static func detectPower(deploymentID: UUID, host: SSHHostID) {
        guard EnergySettings.shared.needsDetection(deploymentID, host) else { return }
        let machine = profile(deploymentID: deploymentID, host: host)
        var hardware = PowerHardware()
        hardware.processor = machine.cores <= 4 ? "Intel(R) N100"
            : machine.cores <= 12 ? "AMD Ryzen 5 5600X 6-Core Processor" : "Intel(R) Xeon(R) Silver 4210R CPU"
        hardware.coresPerSocket = machine.cores <= 12 ? min(machine.cores, 6) : 10
        hardware.sockets = machine.cores > 20 ? 2 : 1
        hardware.threads = machine.cores
        hardware.memoryBytes = machine.memTotalBytes
        hardware.chassis = machine.cores <= 4 ? 35 : machine.cores <= 12 ? 3 : 23
        hardware.nvme = 1
        hardware.hdd = machine.cores <= 4 ? 0 : 2
        EnergySettings.shared.setEstimate(PowerEstimate(hardware), deploymentID, host)
    }

    /// The number the demo readings are generated from
    private static func seed(deploymentID: UUID, host: SSHHostID) -> UInt64 {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325          // FNV-1a offset basis
        func mix(_ byte: UInt8) {
            value = (value ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        withUnsafeBytes(of: deploymentID.uuid) { $0.forEach(mix) }
        host.persistedRaw.utf8.forEach(mix)
        return value
    }

    static func snapshot(deploymentID: UUID, host: SSHHostID, tick: UInt64) -> HostMetricsSnapshot {
        let machine = profile(deploymentID: deploymentID, host: host)
        let seed = seed(deploymentID: deploymentID, host: host)
        let current = sample(profile: machine, seed: seed, tick: tick)
        let previous = tick > 0 ? sample(profile: machine, seed: seed, tick: tick - 1) : nil
        return HostMetricsSnapshot(current: current, previous: previous)
    }

    private static func wander(seed: UInt64, salt: Double, tick: UInt64) -> Double {
        let phase = Double(seed % 628) / 100
        let t = Double(tick)
        return 0.6 * sin(t / 7 + phase + salt) + 0.4 * sin(t / 23 + phase * 2 + salt)
    }

    private static func sample(profile: DemoMachineProfile, seed: UInt64, tick: UInt64) -> HostMetricsSample {
        func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
            min(max(value, range.lowerBound), range.upperBound)
        }
        func busy(_ atTick: UInt64) -> Double {
            clamp(profile.cpuBusy + profile.cpuSwing * wander(seed: seed, salt: 0.4, tick: atTick),
                  0.01...0.98)
        }
        var sample = HostMetricsSample()
        sample.cpuCores = profile.cores
        sample.cpuTotalTicks = Int64(tick) * 1000
        sample.cpuIdleTicks = Int64((0..<tick).reduce(0.0) { $0 + (1 - busy($1)) } * 1000)
        sample.memTotalBytes = profile.memTotalBytes
        let memUsed = clamp(profile.memUsedFraction
                            + profile.memSwing * wander(seed: seed, salt: 1.7, tick: tick),
                            0.05...0.97)
        sample.memUsedBytes = Int64(Double(profile.memTotalBytes) * memUsed)
        sample.swapTotalBytes = profile.memTotalBytes / 4
        sample.swapUsedBytes = profile.memTotalBytes / 40
        sample.uptimeSeconds = profile.uptimeDays * 86_400 + Double(tick) * tickSeconds
        let load = Double(profile.cores) * busy(tick)
        sample.load1 = load
        sample.load5 = load * 0.85 + 0.05
        sample.load15 = load * 0.7 + 0.05
        func counter(_ perSecond: Double, salt: Double, offset: Double) -> Int64 {
            let sinceStart = (0..<tick).reduce(0.0) { total, at in
                let factor = 0.7 + 0.3 * (0.5 + 0.5 * wander(seed: seed, salt: salt, tick: at))
                return total + perSecond * factor * tickSeconds
            }
            let carriedDays = min(profile.uptimeDays, 7)
            return Int64(perSecond * carriedDays * 86_400 * offset + sinceStart)
        }
        sample.netReceivedBytes = counter(profile.netReceivedPerSecond, salt: 2.9, offset: 0.6)
        sample.netSentBytes = counter(profile.netSentPerSecond, salt: 4.1, offset: 0.6)
        sample.diskReadBytes = counter(profile.diskReadPerSecond, salt: 5.3, offset: 0.4)
        sample.diskWrittenBytes = counter(profile.diskWrittenPerSecond, salt: 6.7, offset: 0.4)
        sample.mounts = [DiskMount(target: "/", sizeBytes: profile.diskTotalBytes,
                                   usedBytes: Int64(Double(profile.diskTotalBytes)
                                                    * profile.diskUsedFraction),
                                   usedPercent: 0)]
        sample.osID = profile.osID
        sample.osPrettyName = profile.osPrettyName
        if let temperature = profile.temperatureCelsius {
            sample.temperatureCelsius = temperature + 3 * wander(seed: seed, salt: 9.1, tick: tick)
        }
        return sample
    }

    static func history(deploymentID: UUID, host: SSHHostID,
                        bucket: MetricsHistoryBucket) -> [MetricsHistoryPoint] {
        let machine = profile(deploymentID: deploymentID, host: host)
        let seed = seed(deploymentID: deploymentID, host: host)
        let count = 180
        let end = Date()
        return (0..<count).map { index in
            let t = Double(index)
            func around(_ resting: Double, salt: Double, spread: Double) -> Double {
                let phase = Double(seed % 7)
                let shape = 0.65 * sin(t / 13 + salt + phase) + 0.35 * sin(t / 37 + salt * 2 + phase)
                return max(0, resting * (1 + spread * shape))
            }
            let spike = t.truncatingRemainder(dividingBy: 47) < 2 ? 1.9 : 1
            let cpu = min(97, around(machine.cpuBusy * 100,
                                     salt: 0.4,
                                     spread: machine.cpuSwing / max(machine.cpuBusy, 0.01)) * spike)
            return MetricsHistoryPoint(
                date: end.addingTimeInterval(-Double(count - 1 - index) * bucket.pointInterval),
                cpuPercent: cpu,
                memUsedBytes: Int64(Double(machine.memTotalBytes)
                                    * min(0.97, around(machine.memUsedFraction, salt: 1.7, spread: 0.12))),
                memTotalBytes: machine.memTotalBytes,
                diskUsedBytes: Int64(Double(machine.diskTotalBytes)
                                     * (machine.diskUsedFraction - (1 - t / Double(count)) * 0.04)),
                diskTotalBytes: machine.diskTotalBytes,
                netReceivedPerSecond: around(machine.netReceivedPerSecond, salt: 2.9, spread: 0.7) * spike,
                netSentPerSecond: around(machine.netSentPerSecond, salt: 4.1, spread: 0.7) * spike,
                diskReadPerSecond: around(machine.diskReadPerSecond, salt: 5.3, spread: 0.8),
                diskWrittenPerSecond: around(machine.diskWrittenPerSecond, salt: 6.7, spread: 0.8),
                load1: around(Double(machine.cores) * machine.cpuBusy, salt: 7.9, spread: 0.5) * spike,
                temperatureCelsius: machine.temperatureCelsius.map {
                    around($0, salt: 9.1, spread: 0.09)
                }
            )
        }
    }
}
