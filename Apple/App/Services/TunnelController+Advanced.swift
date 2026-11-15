import Foundation
import ServiceCatalog
import VPNProfile
import VPNTunnel

extension TunnelController {
    static let advancedServerID = UUID(uuidString: "6AD0C0DE-0000-4000-8000-00000000AD01")!

    /// Stores the advanced profile as the tunnel the button runs
    @discardableResult
    func adoptAdvanced(_ advanced: AdvancedProfile) throws -> TunnelProfile {
        let members = try AdvancedXrayConfiguration.members(of: advanced)
        guard let first = members.first else { throw AdvancedXrayConfiguration.BuildError.noActiveServer }
        let secret = ProxyTunnelText.compose(link: "advanced", dns: Self.importedProxyDNS,
                                             advanced: try AdvancedProfileCoding.encode(advanced))
        let profile = TunnelProfile(serverID: Self.advancedServerID, serverName: "Advanced",
                                    protocolID: .xrayReality, deviceID: "advanced",
                                    deviceName: "Advanced", endpoint: "\(first.host):\(first.port)",
                                    addresses: [], dns: Self.importedProxyDNS)
        try secrets.store(secret, for: profile.secretAccount)
        let stored = try profileStore.store(profile)
        reloadProfiles()
        return stored
    }

    func advancedTraffic() async -> AdvancedTraffic? {
        await (engine as? SystemTunnelEngine)?.advancedTraffic()
    }
}
