import ServiceCatalog

/// What one run from the Apps tab installs, in order
enum ServiceInstallPlan {
    struct Step {
        let service: any ManagedService
        /// Other new VPN protocols this step installs too
        let alsoProtocols: Set<ServiceID>

        var displayNames: [String] {
            [service.displayName]
                + alsoProtocols.compactMap { ServiceRegistry.service($0)?.displayName }.sorted()
        }
    }

    /// New services only; new VPN protocols as one step
    static func steps(for services: [any ManagedService], installed: Set<ServiceID>) -> [Step] {
        var seen = Set<ServiceID>()
        let fresh = services.filter { !installed.contains($0.id) && seen.insert($0.id).inserted }
        let protocols = fresh.map(\.id).filter(ServiceID.vpnProtocols.contains)
        return fresh.compactMap { service in
            guard ServiceID.vpnProtocols.contains(service.id) else {
                return Step(service: service, alsoProtocols: [])
            }
            guard service.id == protocols.first else { return nil }
            return Step(service: service, alsoProtocols: Set(protocols.dropFirst()))
        }
    }

    /// Repair and reinstall: every service again, tunnel kept
    static func rerun(_ installed: [any ManagedService]) -> [Step] {
        let chosen = agentRun(chosen: installed.filter { $0.id != .cloudflared }, onHost: [])
        return steps(for: chosen, installed: [])
    }

    /// What setup sends the agent; VPN protocols once
    static func agentRun(chosen: [any ManagedService], onHost: Set<ServiceID>) -> [any ManagedService] {
        let protocols = chosen.map(\.id).filter(ServiceID.vpnProtocols.contains)
        let vpnNeeded = protocols.contains { !onHost.contains($0) }
        return chosen.filter { service in
            if ServiceID.vpnProtocols.contains(service.id) {
                return vpnNeeded && service.id == protocols.first
            }
            if service.id == .vpnPanel {
                return protocols.isEmpty && !onHost.contains(service.id)
            }
            return !onHost.contains(service.id)
        }
    }
}
