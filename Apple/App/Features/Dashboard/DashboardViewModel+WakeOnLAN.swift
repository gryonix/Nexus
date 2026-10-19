import AgentClient
import Foundation
import ServerControl
import gryonixNexusCore

extension DashboardViewModel {
    /// What a send attempt has to say for itself
    struct WakeOutcome {
        let sent: Bool
        let message: String
    }

    /// Reads the address from the machine and keeps it
    func readWakeOnLAN() async -> Deployment? {
        guard let host = wakeTarget?.sshHost else { return nil }
        let info: (mac: String, broadcast: String?)?
        if let fromAgent = await wakeInfoFromAgent(host: host) {
            info = fromAgent
        } else {
            info = await wakeInfoOverSSH(host: host)
        }
        guard let info else { return nil }
        guard info.mac != deployment.wakeOnLANMAC || info.broadcast != deployment.wakeOnLANBroadcast
        else { return deployment }
        var updated = deployment
        updated.wakeOnLANMAC = info.mac
        updated.wakeOnLANBroadcast = info.broadcast
        applyDeployment(updated)
        return updated
    }

    private func wakeInfoOverSSH(host: SSHHostID) async -> (mac: String, broadcast: String?)? {
        do {
            let runner = try await commandSession()
            return try await StatusOperations(runner: runner, config: config).wakeInfo(on: host)
        } catch {
            return nil
        }
    }

    /// The agent's reading, which also arms the network card
    private func wakeInfoFromAgent(host: SSHHostID) async -> (mac: String, broadcast: String?)? {
        guard deployment.usesAgent, host == deployment.servicesHost, Self.agentTransportAvailable,
              #available(macOS 15.0, *) else { return nil }
        do {
            let runner = try await commandSession()
            let state = try await AgentConnection.client(deployment: deployment, runner: runner).getState()
            guard state.hasWakeOnLan, let mac = WakeOnLAN.normalised(state.wakeOnLan.mac) else { return nil }
            wakeSupport = state.wakeOnLan.support
            let broadcast = state.wakeOnLan.broadcast
            return (mac, broadcast.isEmpty ? nil : broadcast)
        } catch {
            return nil
        }
    }

    /// Refreshes the stored address while the machine is awake
    func refreshWakeOnLANQuietly() async -> Deployment? {
        guard WakeOnLANAvailability.isOffered(for: deployment) else { return nil }
        let before = (deployment.wakeOnLANMAC, deployment.wakeOnLANBroadcast)
        guard let updated = await readWakeOnLAN(),
              (updated.wakeOnLANMAC, updated.wakeOnLANBroadcast) != before else { return nil }
        return updated
    }

    /// One-tap wake; returns the address if newly read
    func wakeUp(readIfMissing: Bool = true) async -> Deployment? {
        guard !wakingUp else { return nil }
        wakingUp = true
        defer { wakingUp = false }
        var read: Deployment?
        if deployment.wakeOnLANMAC == nil, readIfMissing { read = await readWakeOnLAN() }
        guard let mac = deployment.wakeOnLANMAC else {
            quickActionResult = QuickActionResult(
                message: UIL10n.string("The machine has not reported its network card yet. Open this server once while it is on."),
                isError: true)
            return read
        }
        if wakeSupport == .unsupported {
            quickActionResult = QuickActionResult(
                message: UIL10n.string("This machine's network card cannot wake it up, for example over Wi-Fi."),
                isError: true)
            return read
        }
        let outcome = await sendWakeOnLAN(mac: mac)
        quickActionResult = QuickActionResult(message: outcome.message, isError: !outcome.sent)
        return read
    }

    /// Sends from this device and a neighbouring machine
    func sendWakeOnLAN(mac: String) async -> WakeOutcome {
        guard let normalised = WakeOnLAN.normalised(mac),
              let packet = WakeOnLAN.magicPacket(mac: normalised) else {
            return WakeOutcome(sent: false, message: UIL10n.string("That is not a MAC address."))
        }
        let broadcast = await targetBroadcast()
        let targets = WakeOnLAN.deviceTargets(broadcast: broadcast, host: wakeTarget?.endpoint.host)
        let fromDevice = MagicPacketSender.sendBurst(packet, to: targets, ports: WakeOnLAN.ports)
        if let helper = await sendFromNeighbour(normalised, broadcast: broadcast) {
            return WakeOutcome(sent: true, message: UIL10n.string("Wake-up sent from %@.", helper))
        }
        guard fromDevice else {
            return WakeOutcome(sent: false,
                               message: UIL10n.string("This device could not send the packet. iOS allows broadcast only for apps Apple has granted the multicast entitlement."))
        }
        return WakeOutcome(sent: true, message: UIL10n.string("Wake-up sent from this device to %@.", broadcast))
    }

    /// The sleeping machine's broadcast, without waiting long
    private func targetBroadcast() async -> String {
        guard let target = wakeTarget else { return WakeOnLAN.limitedBroadcast }
        let host = target.endpoint.host
        if let stored = deployment.wakeOnLANBroadcast, WakeOnLAN.broadcastAddress(for: stored) != nil {
            return stored
        }
        if let derived = WakeOnLAN.broadcastAddress(for: host) { return derived }
        let resolved = await Self.within(seconds: 2) { await WakeOnLAN.resolveIPv4(host) }
        return WakeOnLAN.broadcast(stored: nil, host: host, resolved: resolved)
    }

    /// Asks an awake machine on that network to send it
    private func sendFromNeighbour(_ mac: String, broadcast: String) async -> String? {
        for (owner, node) in await Self.neighbours(of: deployment, on: broadcast) {
            let model = owner.id == deployment.id ? self : DashboardViewModel(deployment: owner)
            let sent = await Self.within(seconds: 10) {
                await model.sendFromHere(mac, broadcast: broadcast, host: node.sshHost) ? true : nil
            }
            if sent == true { return node.name.isEmpty ? node.endpoint.host : node.name }
        }
        return nil
    }

    /// Runs the send on one of this deployment's machines
    func sendFromHere(_ mac: String, broadcast: String, host: SSHHostID) async -> Bool {
        do {
            let runner = try await commandSession()
            try await StatusOperations(runner: runner, config: config)
                .sendWakeOnLAN(mac: mac, broadcast: broadcast, from: host)
            return true
        } catch {
            return false
        }
    }

    /// Machines of any saved server on the same network
    private static func neighbours(of deployment: Deployment,
                                   on broadcast: String) async -> [(Deployment, DeploymentNode)] {
        let sleeping = WakeOnLANAvailability.target(in: deployment)?.sshHost
        let fleet = (try? FileDeploymentStore().load()) ?? [deployment]
        var found: [(Deployment, DeploymentNode)] = []
        for owner in fleet {
            for node in owner.nodes where !(owner.id == deployment.id && node.sshHost == sleeping) {
                if await networkBroadcast(of: node) == broadcast { found.append((owner, node)) }
            }
        }
        return found.sorted { lhs, _ in lhs.0.id == deployment.id }
    }

    private static func networkBroadcast(of node: DeploymentNode) async -> String? {
        let host = node.endpoint.host
        if let derived = WakeOnLAN.broadcastAddress(for: host) { return derived }
        guard WakeOnLAN.isLocalNetwork(host) else { return nil }
        let resolved = await within(seconds: 2) { await WakeOnLAN.resolveIPv4(host) }
        return resolved.flatMap(WakeOnLAN.broadcastAddress(for:))
    }

    /// The result, or nil when it takes too long
    static func within<T: Sendable>(seconds: Double,
                                    _ work: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Shuts down the machine Wake on LAN brings back
    func powerOffWakeTarget() async {
        guard let host = wakeTarget?.sshHost else { return }
        do {
            let runner = try await commandSession()
            try await StatusOperations(runner: runner, config: config).powerOff(on: host)
            quickActionResult = QuickActionResult(
                message: UIL10n.string("Shutdown sent. Wake on LAN turns the machine back on."), isError: false)
        } catch ServerControlError.sudoPasswordRequired {
            quickActionResult = QuickActionResult(
                message: UIL10n.string("This server does not let the app shut it down yet. Update the agent, then try again."),
                isError: true)
        } catch {
            quickActionResult = QuickActionResult(message: Self.message(for: error), isError: true)
        }
        invalidateSession()
    }

    private var wakeTarget: DeploymentNode? {
        WakeOnLANAvailability.target(in: deployment)
    }
}
