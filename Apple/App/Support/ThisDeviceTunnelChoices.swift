import AgentControl
import Foundation
import ServerControl
import ServiceCatalog
import VPNTunnel

enum ThisDeviceTunnelChoices {
    static var agentTransportAvailable: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    static func manageableServers(in deployments: [Deployment]) -> [Deployment] {
        guard agentTransportAvailable else { return [] }
        return VPNSectionView.manageable(in: deployments).filter { deployment in
            VPNClientProtocols.installed(in: deployment.services)
                .contains { TunnelCapableProtocols.isIntegrated($0) }
        }
    }

    static func protocols(for deployment: Deployment) -> [ServiceID] {
        VPNClientProtocols.installed(in: deployment.services)
            .filter { TunnelCapableProtocols.isIntegrated($0) }
    }

    struct Pair: Hashable {
        let deployment: Deployment
        let protocolID: ServiceID
    }

    static func pairs(in deployments: [Deployment]) -> [Pair] {
        manageableServers(in: deployments).flatMap { deployment in
            protocols(for: deployment).map { Pair(deployment: deployment, protocolID: $0) }
        }
    }

    /// The current protocol when offered, else the first one
    static func landingProtocol(among available: [ServiceID], keeping current: ServiceID) -> ServiceID? {
        available.contains(current) ? current : available.first
    }

    /// A tunnel already kept here for the pair, own first
    static func keptProfile(in profiles: [TunnelProfile], serverID: UUID, protocolID: ServiceID,
                            ownName: String) -> TunnelProfile? {
        let pair = profiles.filter { $0.serverID == serverID && $0.protocolID == protocolID }
        return pair.first { $0.deviceName == ownName } ?? pair.first
    }

    /// Server devices other than this device's own
    static func otherDevices(_ devices: [VPNClientDevice], ownDeviceID: String?) -> [VPNClientDevice] {
        devices.filter { $0.id != ownDeviceID }
    }

    /// A protocol's name; plain WireGuard marked when obfuscated
    static func protocolLabel(_ id: ServiceID, obfuscated: Bool) -> String {
        guard obfuscated, id != .amneziaWG else { return id.displayName }
        return UIL10n.string("%@ (obfuscated)", id.displayName)
    }

    /// The DNS the server lists, else the profile's
    static func dns(of profile: TunnelProfile, listed devices: [VPNClientDevice]) -> [String] {
        let listed = devices.first { $0.id == profile.deviceID }?.dns ?? []
        return LocalDNS.chosen(listed.isEmpty ? profile.dns : listed)
    }
}
