package com.skaymer.gryonixnexus.app.servers.demo

import com.skaymer.gryonixnexus.catalog.ServiceID
import gryonixnexusd.v1.VpnClientConfig

/** What a demo server hands a device to connect with */
object DemoVPNConfig {
    private const val PLACEHOLDER_KEY = "DEMO-SERVER-PLACEHOLDER-NOT-A-KEY"

    fun make(protocol: String, clientID: String): VpnClientConfig {
        val octet = clientID.split("-").lastOrNull() ?: "2"
        return when (ServiceID(protocol)) {
            ServiceID.AMNEZIA_WG -> VpnClientConfig(text = amnezia(octet), filename = "gryonix-demo-awg.conf", qr_is_useful = true)
            ServiceID.SHADOWSOCKS -> VpnClientConfig(
                text = "ss://$PLACEHOLDER_KEY@203.0.113.20:8388#gryonixNexus%20demo",
                filename = "gryonix-demo-ss.txt",
                qr_is_useful = true,
            )
            ServiceID.XRAY_REALITY -> VpnClientConfig(
                text = "vless://DEMO-SERVER-PLACEHOLDER-NOT-A-UUID@203.0.113.10:8443" +
                    "?type=tcp&security=reality&sni=www.apple.com" +
                    "&pbk=$PLACEHOLDER_KEY&fp=chrome&sid=0123#gryonixNexus%20demo",
                filename = "gryonix-demo-xray.txt",
                qr_is_useful = true,
            )
            ServiceID.OPEN_VPN -> VpnClientConfig(text = openVPN(), filename = "gryonix-demo.ovpn", qr_is_useful = false)
            else -> VpnClientConfig(text = wireGuard(octet), filename = "gryonix-demo.conf", qr_is_useful = true)
        }
    }

    private fun wireGuard(octet: String) = """
        [Interface]
        PrivateKey = $PLACEHOLDER_KEY
        Address = 10.9.0.$octet/32
        DNS = 10.9.0.1

        [Peer]
        PublicKey = $PLACEHOLDER_KEY
        AllowedIPs = 0.0.0.0/0, ::/0
        Endpoint = 203.0.113.10:51820
        PersistentKeepalive = 25
    """.trimIndent()

    private fun amnezia(octet: String) = """
        [Interface]
        PrivateKey = $PLACEHOLDER_KEY
        Address = 10.10.0.$octet/32
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
        PublicKey = $PLACEHOLDER_KEY
        AllowedIPs = 0.0.0.0/0, ::/0
        Endpoint = 203.0.113.10:51830
        PersistentKeepalive = 25
    """.trimIndent()

    private fun openVPN() = """
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
        $PLACEHOLDER_KEY
        -----END PRIVATE KEY-----
        </key>
    """.trimIndent()
}
