import Foundation
import gryonixNexusCore
import ServiceCatalog
import SwiftUI

struct ScenarioOption: Identifiable, Hashable {
    let id: String
    /// The English source string, which is also the catalog key
    let titleKey: String
    var title: LocalizedStringKey { LocalizedStringKey(titleKey) }
    let subtitle: LocalizedStringKey
    let systemImage: String
    let topology: Topology
    let scope: DeploymentScope

    static func == (lhs: ScenarioOption, rhs: ScenarioOption) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func title(topology: Topology, scope: DeploymentScope) -> LocalizedStringKey {
        all.first { $0.topology == topology && $0.scope == scope }?.title
            ?? (topology == .singleHost ? "Public IP" : "VPS + Local server")
    }

    static let all: [ScenarioOption] = [
        ScenarioOption(
            id: "single",
            titleKey: "Public IP",
            subtitle: "One server with a public IP address: the services, TLS and DNS all live on it.",
            systemImage: "server.rack",
            topology: .singleHost,
            scope: .publicInternet
        ),
        ScenarioOption(
            id: "relay",
            titleKey: "Public IP (VPS) + Local server",
            subtitle: "The local server sits behind NAT; the VPS receives the traffic and forwards it over WireGuard.",
            systemImage: "point.3.connected.trianglepath.dotted",
            topology: .vpsRelayWithHomeBackend,
            scope: .publicInternet
        ),
        ScenarioOption(
            id: "localOnly",
            titleKey: "Local Server",
            subtitle: "A server on your own network only — no public IP, no domain, a self-signed certificate. Mail and VPN aren't available, since both need to be reachable from outside.",
            systemImage: "house",
            topology: .singleHost,
            scope: .localOnly
        ),
        ScenarioOption(
            id: "cloudflareTunnel",
            titleKey: "Server without open ports",
            subtitle: "Your domain, reached through a Cloudflare Tunnel: the server dials out, so nothing has to be forwarded to it. Mail and VPN aren't available — a tunnel carries web traffic only.",
            systemImage: "cloud",
            topology: .singleHost,
            scope: .cloudflareTunnel
        ),
        ScenarioOption(
            id: "dynamicDNS",
            titleKey: "Home server with a changing address",
            subtitle: "A real domain and open ports, but your provider hands out a new IP now and then. The server keeps its own DNS records up to date, so the names never go stale. Mail and VPN work here.",
            systemImage: "arrow.triangle.2.circlepath",
            topology: .singleHost,
            scope: .dynamicDNS
        ),
        ScenarioOption(
            id: "meshOnly",
            titleKey: "Only my own devices",
            subtitle: "No public address and no open ports: the services answer only to phones and laptops joined to your private mesh. The certificate is self-signed, since there is no way in for a public one. Mail and VPN aren't available.",
            systemImage: "point.3.filled.connected.trianglepath.dotted",
            topology: .singleHost,
            scope: .meshOnly
        )
    ]
}
