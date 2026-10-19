import Foundation
import ServiceCatalog

public extension ServiceID {
    /// The VPN protocols and their panel; they move together
    static let vpnFamily: Set<ServiceID> = vpnProtocols.union([.vpnPanel])
}

public extension Deployment {
    /// The relay that publishes this deployment, if any
    var relayNode: DeploymentNode? {
        nodes.first { $0.terminatesPublicTraffic && !$0.runsServices }
    }

    /// Whether the VPN runs on the relay
    var vpnRunsOnRelay: Bool {
        vpnOnRelay == true && relayNode != nil
    }

    /// Whether this deployment can move its VPN to the relay
    var canRunVPNOnRelay: Bool {
        usesAgent && relayNode != nil
    }

    /// The machine the VPN runs on
    var vpnHost: SSHHostID {
        guard vpnRunsOnRelay, let relay = relayNode else { return servicesHost }
        return relay.sshHost
    }

    /// The other machine the VPN could run on
    var otherVPNHost: SSHHostID? {
        guard let relay = relayNode else { return nil }
        return vpnRunsOnRelay ? servicesHost : relay.sshHost
    }

    /// Installed VPN protocols and panel
    var installedVPNServices: Set<ServiceID> {
        services.intersection(ServiceID.vpnFamily)
    }

    /// Installed services whose ports the relay sends home
    var servicesBehindRelay: [any ManagedService] {
        guard vpnRunsOnRelay else { return installedServices }
        return installedServices.filter { !ServiceID.vpnFamily.contains($0.id) }
    }
}

public extension Deployment {
    /// The VPN's directories that hold its keys and devices
    var vpnStateDirectories: [String] {
        let settings = serviceSettings
        let byProtocol: [(ServiceID, String)] = [
            (.amneziaWG, settings.amneziaWGPath), (.shadowsocks, settings.shadowsocksPath),
            (.xrayReality, settings.xrayRealityPath), (.openVPN, settings.openVPNPath),
        ]
        let protocols = byProtocol.filter { services.contains($0.0) }.map(\.1)
        return [VPNPanelService.path] + protocols
    }

    /// This deployment with the VPN moved
    func movingVPN(toRelay: Bool) -> Deployment {
        var moved = self
        moved.vpnOnRelay = toRelay ? true : nil
        return moved
    }
}
