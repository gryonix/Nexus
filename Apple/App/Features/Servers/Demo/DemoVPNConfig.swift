import AgentClient
import Foundation
import ServiceCatalog

/// What a demo server hands a device to connect with
enum DemoVPNConfig {
    static func make(protocol id: String, clientID: String) -> Gryonixnexusd_V1_VpnClientConfig {
        let octet = clientID.split(separator: "-").last.map(String.init) ?? "2"
        var config = Gryonixnexusd_V1_VpnClientConfig()
        config.qrIsUseful = true
        switch ServiceID(rawValue: id) {
        case .amneziaWG:
            config.text = amnezia(octet: octet)
            config.filename = "gryonix-demo-awg.conf"
        case .shadowsocks:
            config.text = "ss://DEMO-SERVER-PLACEHOLDER-NOT-A-KEY@203.0.113.20:8388"
                + "#gryonixNexus%20demo"
            config.filename = "gryonix-demo-ss.txt"
        case .xrayReality:
            config.text = "vless://DEMO-SERVER-PLACEHOLDER-NOT-A-UUID@203.0.113.10:8443"
                + "?type=tcp&security=reality&sni=www.apple.com"
                + "&pbk=DEMO-SERVER-PLACEHOLDER-NOT-A-KEY&fp=chrome&sid=0123#gryonixNexus%20demo"
            config.filename = "gryonix-demo-xray.txt"
        case .openVPN:
            config.text = openVPN()
            config.filename = "gryonix-demo.ovpn"
            config.qrIsUseful = false
        default:
            config.text = wireGuard(octet: octet)
            config.filename = "gryonix-demo.conf"
        }
        return config
    }

    private static func wireGuard(octet: String) -> String {
        """
        [Interface]
        PrivateKey = DEMO-SERVER-PLACEHOLDER-NOT-A-KEY
        Address = 10.9.0.\(octet)/32
        DNS = 10.9.0.1

        [Peer]
        PublicKey = DEMO-SERVER-PLACEHOLDER-NOT-A-KEY
        AllowedIPs = 0.0.0.0/0, ::/0
        Endpoint = 203.0.113.10:51820
        PersistentKeepalive = 25
        """
    }

    private static func amnezia(octet: String) -> String {
        """
        [Interface]
        PrivateKey = DEMO-SERVER-PLACEHOLDER-NOT-A-KEY
        Address = 10.10.0.\(octet)/32
        DNS = 10.10.0.1
        Jc = 4
        Jmin = 40
        Jmax = 70
        S1 = 82
        S2 = 145
        H1 = 1148834274
        H2 = 1156008014
        H3 = 1712813268
        H4 = 1972823447

        [Peer]
        PublicKey = DEMO-SERVER-PLACEHOLDER-NOT-A-KEY
        AllowedIPs = 0.0.0.0/0, ::/0
        Endpoint = 203.0.113.10:51830
        PersistentKeepalive = 25
        """
    }

    private static func openVPN() -> String {
        """
        client
        dev tun
        proto udp
        remote 203.0.113.20 1194
        resolv-retry infinite
        nobind
        persist-key
        persist-tun
        remote-cert-tls server
        cipher AES-256-GCM
        verb 3

        <ca>
        -----BEGIN CERTIFICATE-----
        DEMO-SERVER-PLACEHOLDER-NOT-A-CERTIFICATE
        -----END CERTIFICATE-----
        </ca>
        <cert>
        -----BEGIN CERTIFICATE-----
        DEMO-SERVER-PLACEHOLDER-NOT-A-CERTIFICATE
        -----END CERTIFICATE-----
        </cert>
        <key>
        -----BEGIN PRIVATE KEY-----
        DEMO-SERVER-PLACEHOLDER-NOT-A-KEY
        -----END PRIVATE KEY-----
        </key>
        """
    }
}
