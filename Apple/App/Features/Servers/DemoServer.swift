import Foundation
import ServerControl
import ServiceCatalog

/// The servers shown while the list is empty
enum DemoServer {
    static let enabledKey = "demoFleetEnabled"

    static var isEnabled: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_FLEET"] != nil { return true }
        #endif
        return UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static let id = UUID(uuidString: "6D3E0000-DE40-4000-8000-000000000001")!
    static let relayPairID = UUID(uuidString: "6D3E0000-DE40-4000-8000-000000000002")!
    static let localOnlyID = UUID(uuidString: "6D3E0000-DE40-4000-8000-000000000003")!
    static let sshOnlyID = UUID(uuidString: "6D3E0000-DE40-4000-8000-000000000004")!

    static let domain = "gryonix.com"

    static func deployments() -> [Deployment] {
        [deployment(), relayPair(), localOnly(), sshOnly()]
    }

    static func deployment() -> Deployment {
        Deployment(
            id: id,
            name: domain,
            topology: .singleHost,
            domain: domain,
            entry: HostEndpoint(host: "203.0.113.10", user: "server-user"),
            services: [.mailcow, .vaultwarden, .nextcloud, .immich,
                       .wireguardVPN, .amneziaWG, .xrayReality,
                       .vpnPanel, .adguardHome,
                       .headscale, .tailscaleNode,
                       .homepage, .authelia,
                       .minecraftJava, .craftyController],
            tags: ["demo"],
            usesAgent: true,
            iconSymbol: "sparkles",
            tintName: ServerTint.teal.rawValue)
    }

    static func relayPair() -> Deployment {
        Deployment(
            id: relayPairID,
            name: "b.gryonix.com",
            topology: .vpsRelayWithHomeBackend,
            domain: "b.gryonix.com",
            entry: HostEndpoint(host: "203.0.113.20", user: "server-user"),
            homeWGAddress: "10.8.0.2",
            services: [.dockerMailserver, .nextcloud, .vaultwarden,
                       .wireguardVPN, .shadowsocks, .xrayReality, .openVPN, .vpnPanel],
            tags: ["demo"],
            usesAgent: true,
            tintName: ServerTint.purple.rawValue)
    }

    static func localOnly() -> Deployment {
        Deployment(
            id: localOnlyID,
            name: "home.local",
            topology: .singleHost,
            domain: "home.local",
            entry: HostEndpoint(host: "192.168.1.24", user: "server-user"),
            services: [.seafile, .photoprism, .jellyfin, .pihole],
            tags: ["demo"],
            usesAgent: true,
            iconSymbol: "house.fill",
            tintName: ServerTint.green.rawValue,
            scope: .localOnly)
    }

    static func sshOnly() -> Deployment {
        Deployment(
            id: sshOnlyID,
            name: "lab.gryonix.com",
            topology: .singleHost,
            domain: "lab.gryonix.com",
            entry: HostEndpoint(host: "203.0.113.30", user: "server-user"),
            services: [.forgejo, .psono, .wireguardVPN, .amneziaWG, .vpnPanel],
            tags: ["demo"],
            tintName: ServerTint.orange.rawValue)
    }

    static func isDemo(_ deployment: Deployment) -> Bool {
        isBuiltIn(deployment.id)
            || (isInstalled(deployment.id) && isDocumentationHost(deployment.entry.host))
    }

    static func isDemo(_ deploymentID: UUID) -> Bool {
        isBuiltIn(deploymentID) || isInstalled(deploymentID)
    }

    /// One of the four this app ships
    static func isBuiltIn(_ deployment: Deployment) -> Bool { isBuiltIn(deployment.id) }

    static func isBuiltIn(_ deploymentID: UUID) -> Bool {
        deploymentID == id || deploymentID == relayPairID
            || deploymentID == localOnlyID || deploymentID == sshOnlyID
    }

    // MARK: - Servers a demo installation made

    private static let installedKey = "demoFleetInstalled"

    /// Installed on the emulated machine
    static func isInstalled(_ deploymentID: UUID) -> Bool {
        installedIDs().contains(deploymentID.uuidString)
    }

    static func installedIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: installedKey) ?? [])
    }

    static func remember(installed deploymentID: UUID) {
        var ids = installedIDs()
        ids.insert(deploymentID.uuidString)
        UserDefaults.standard.set(Array(ids).sorted(), forKey: installedKey)
    }

    static func forget(installed deploymentID: UUID) {
        var ids = installedIDs()
        ids.remove(deploymentID.uuidString)
        UserDefaults.standard.set(Array(ids).sorted(), forKey: installedKey)
    }

    /// RFC 5737 documentation ranges: never a real machine
    static func isDocumentationHost(_ host: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        return ["192.0.2.", "198.51.100.", "203.0.113."].contains { trimmed.hasPrefix($0) }
    }

    /// A server with a real address is never emulated
    static func releaseReal(_ deployments: [Deployment]) {
        for deployment in deployments
        where isInstalled(deployment.id) && !isDocumentationHost(deployment.entry.host) {
            forget(installed: deployment.id)
        }
    }

    /// No real server is in the fleet
    static func fleetIsDemoOnly(_ deployments: [Deployment]) -> Bool {
        isEnabled && !deployments.contains { !isDemo($0) }
    }

    /// What kind of machine this one is pretending to be
    static func profile(deploymentID: UUID, host: SSHHostID) -> DemoMachineProfile? {
        switch deploymentID {
        case id: return .busyHost
        case relayPairID: return host == .home ? .homeBackend : .relay
        case localOnlyID: return .mediaVault
        case sshOnlyID: return .smallLab
        default: return nil
        }
    }
}
