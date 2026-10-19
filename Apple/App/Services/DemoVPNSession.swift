#if DEBUG
import Foundation
import ServiceCatalog
import VPNTunnel
#if os(iOS)
import ActivityKit
#endif

/// Brings up a demonstration VPN session for screenshots
enum DemoVPNSession {
    static var isAsked: Bool {
        ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_VPN_SESSION"] != nil
    }

    private static let configuration = """
    [Interface]
    PrivateKey = mInDaw06K0NgfULRObHJjkWD3ahUC8XC1tVjIf6W+Vo=
    Address = 10.9.0.4/32

    [Peer]
    PublicKey = JRI8Xc0zKP9kXk8qP84NdUQA04h6DLfFbwJn4g+/PFs=
    Endpoint = vpn.example.com:51820
    AllowedIPs = 0.0.0.0/0
    """

    private static let serverID = UUID(uuidString: "6D3A1C52-0E7B-4E4E-9B0A-5F1C2B3D4E5F") ?? UUID()

    @MainActor
    static func start() async {
        let tunnel = TunnelController.shared
        guard let profile = try? tunnel.adopt(configurationText: configuration,
                                              protocolID: .wireguardVPN,
                                              serverID: serverID,
                                              serverName: "gvps.example.net",
                                              deviceID: "demo-session",
                                              deviceName: "iPhone") else { return }
        await tunnel.connect(profile)
        #if os(iOS)
        try? await Task.sleep(for: .seconds(10))
        await expandIsland()
        #endif
    }

    #if os(iOS)
    /// An alert opens the island in its expanded form
    private static func expandIsland() async {
        for activity in Activity<TunnelActivityAttributes>.activities {
            let alert = AlertConfiguration(title: "VPN", body: "gvps.example.net", sound: .default)
            await activity.update(activity.content, alertConfiguration: alert)
        }
    }
    #endif
}
#endif
