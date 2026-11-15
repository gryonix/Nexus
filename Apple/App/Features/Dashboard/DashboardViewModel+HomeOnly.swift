import AgentClient
import AgentControl
import Foundation
import ServerControl
import ServiceCatalog

extension DashboardViewModel {
    /// Whether this service can be closed to the internet
    func offersHomeOnly(_ service: any ManagedService) -> Bool {
        let context = deployment.serviceContext
        if let ingress = service.webIngress(context) { return !ingress.homeOnly }
        guard deployment.closesServicesAtHome else { return false }
        return !ForwardedPorts.tcp(services: [service], context: context).filter { $0 != 80 }.isEmpty
            || !ForwardedPorts.udp(services: [service], context: context).isEmpty
    }

    func isHomeOnly(_ id: ServiceID) -> Bool {
        deployment.homeOnlyServices.contains(id)
    }

    func isNoVPN(_ id: ServiceID) -> Bool {
        deployment.homeOnlyNoVPN.contains(id)
    }

    func isDNSRemoved(_ id: ServiceID) -> Bool {
        deployment.homeOnlyDNSRemoved.contains(id)
    }

    /// Toggles a service's relay ports and re-syncs
    func setHomeOnly(_ service: any ManagedService, _ homeOnly: Bool) async -> Deployment {
        var changed = deployment
        let hadNoVPN = changed.homeOnlyNoVPN.contains(service.id)
        if homeOnly { changed.homeOnlyServices.insert(service.id) } else {
            changed.homeOnlyServices.remove(service.id)
            changed.homeOnlyNoVPN.remove(service.id)
        }
        let portsChanged = Self.forwardedPorts(of: deployment) != Self.forwardedPorts(of: changed)
        replaceDeployment(changed)
        var failures: [String] = []
        if let host = service.webIngress(changed.serviceContext)?.hostname, homeOnly || hadNoVPN {
            if let failure = await guardSite(host, clearingDeny: !homeOnly) { failures.append(failure) }
        }
        if portsChanged, changed.hasRelayIngress, #available(macOS 15.0, *) {
            do { _ = try await reprovisionRelay() } catch { failures.append(Self.message(for: error)) }
        }
        if let failure = await syncHomeOnlyPorts(of: changed) { failures.append(failure) }
        homeOnlyFailures[service.id] = failures.isEmpty ? nil : failures.joined(separator: "\n")
        if homeOnly { await probePublicPorts(of: service) } else { publicPortVerdicts[service.id] = nil }
        return changed
    }

    func setNoVPN(_ service: any ManagedService, _ noVPN: Bool) async -> Deployment {
        var changed = deployment
        if noVPN { changed.homeOnlyNoVPN.insert(service.id) } else { changed.homeOnlyNoVPN.remove(service.id) }
        replaceDeployment(changed)
        if let host = service.webIngress(changed.serviceContext)?.hostname {
            homeOnlyFailures[service.id] = await guardSite(host, clearingDeny: !noVPN)
        }
        return changed
    }

    /// Guards the site; says why it could not
    private func guardSite(_ host: String, clearingDeny: Bool) async -> String? {
        if adminLockdown.value == nil { await refreshAdminLockdown() }
        guard adminLockdown.value != nil else { return adminLockdown.errorMessage }
        await setLockdown(host: host, guarded: true, clearingDeny: clearingDeny)
        return adminLockdown.errorMessage
    }

    /// Remembers that a service's public record is gone, or back
    func markDNSRemoved(_ service: any ManagedService, _ removed: Bool) -> Deployment {
        var changed = deployment
        if removed { changed.homeOnlyDNSRemoved.insert(service.id) } else { changed.homeOnlyDNSRemoved.remove(service.id) }
        replaceDeployment(changed)
        return changed
    }

    func probePublicPorts(of service: any ManagedService) async {
        let ports = PublicPortProbe.ports(of: service, in: deployment)
        publicPortVerdicts[service.id] = nil
        guard !ports.isEmpty, deployment.hasRelayIngress, #available(macOS 15.0, *) else { return }
        do {
            let runner = try await session()
            let client = try await AgentConnection.client(deployment: deployment, runner: runner, host: .vps)
            let host = deployment.entry.host
            let gate = agentGate
            let answer = try await gate.withSlot {
                try await client.probePublicPorts(host: host, ports: ports.map { UInt32($0) })
            }
            let open = answer.ports.filter(\.open).map { Int($0.port) }
            publicPortVerdicts[service.id] = PublicPortProbe.verdict(asked: ports, open: open)
        } catch {
            publicPortVerdicts[service.id] = nil
        }
    }

    /// Hands the agent every home-only port; says why not
    func syncHomeOnlyPorts(of changed: Deployment) async -> String? {
        guard #available(macOS 15.0, *) else { return nil }
        let services = ServiceRegistry.services(changed.homeOnlyServices)
        let ports = HomeOnlyPorts.of(services, context: changed.serviceContext).map { (proto: $0.proto.rawValue, port: $0.port) }
        do {
            let runner = try await session()
            let client = try await AgentConnection.client(deployment: changed, runner: runner)
            try await agentGate.withSlot { try await client.setHomeOnlyPorts(ports) }
            return nil
        } catch where "\(error)".contains("unknown method") {
            let enforcedByRelay = changed.hasRelayIngress || ports.isEmpty
            return enforcedByRelay ? nil : UIL10n.string("Update the agent on this server to use this.")
        } catch {
            return Self.message(for: error)
        }
    }

    /// Sites with a .local name, or nil to set one
    func localAliases(setting host: String? = nil, on: Bool = false) async throws -> [String: String] {
        guard #available(macOS 15.0, *) else {
            throw ServerControlError.notConfigured(UIL10n.string("This needs a newer system."))
        }
        let runner = try await session()
        let client = try await AgentConnection.client(deployment: deployment, runner: runner)
        let gate = agentGate
        if let host {
            return try await gate.withSlot { try await client.setLocalAlias(host: host, on: on) }
        }
        return try await gate.withSlot { try await client.getLocalAliases() }
    }

    /// The server's own root certificate, as the agent reads it
    func fetchLocalRootCA() async throws -> String {
        guard #available(macOS 15.0, *) else {
            throw ServerControlError.notConfigured(UIL10n.string("This needs a newer system."))
        }
        let runner = try await session()
        let client = try await AgentConnection.client(deployment: deployment, runner: runner)
        let gate = agentGate
        let pem = try await gate.withSlot { try await client.getLocalRootCA() }
        guard !pem.isEmpty else {
            throw ServerControlError.notConfigured(UIL10n.string("This server has no certificate of its own yet."))
        }
        return pem
    }
}
