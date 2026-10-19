import Foundation

public enum XrayConfiguration {
    /// The JSON text for a tunnel carrying this link
    public static func json(forLink text: String,
                            access: LocalProxyAccess,
                            dns: [String] = ["1.1.1.1", "8.8.8.8"],
                            serverAddress: String? = nil) throws -> String {
        let link = try ProxyLinkConfig(parsing: text)
        let document: [String: Any] = [
            "log": ["loglevel": "warning"],
            "inbounds": [inbound(access: access)],
            "outbounds": [outbound(for: link, address: serverAddress ?? link.host), dnsOutbound, blockOutbound],
            "dns": ["servers": dns, "queryStrategy": "UseIP", "tag": dnsQueryTag],
            "routing": ["domainStrategy": "AsIs", "rules": [dnsRule, dnsQueryRule, quicRule, privateRule]],
            "policy": ["levels": ["0": ["connIdle": idleSeconds, "bufferSize": bufferKilobytes]]],
        ]
        let data = try JSONSerialization.data(withJSONObject: document,
                                              options: [.sortedKeys, .prettyPrinted])
        return String(decoding: data, as: UTF8.self)
    }

    /// Idle connections close sooner, keeping the tunnel's memory small
    static let idleSeconds = 30
    static let bufferKilobytes = 4

    /// Xray's own resolver: one shared connection, answers cached
    static let dnsOutbound: [String: Any] = [
        "tag": "dns-out",
        "protocol": "dns",
        "settings": ["rules": [
            ["action": "hijack", "qType": "1,28"],
            ["action": "return", "rCode": 0],
        ]],
    ]

    static let blockOutbound: [String: Any] = ["tag": "block", "protocol": "blackhole"]

    /// QUIC refused: apps fall back to TCP, far cheaper here
    static let quicRule: [String: Any] = [
        "type": "field",
        "network": "udp",
        "port": "443",
        "outboundTag": "block",
    ]

    /// Xray's resolver reaches its servers through the server
    static let dnsQueryTag = "dns-query"
    static let dnsQueryRule: [String: Any] = [
        "type": "field",
        "inboundTag": [dnsQueryTag],
        "outboundTag": "proxy",
    ]

    /// Refused here, since the server holds them a minute
    static let privateRule: [String: Any] = [
        "type": "field",
        "ip": privateRanges,
        "outboundTag": "block",
    ]

    static let privateRanges = [
        "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16",
        "172.16.0.0/12", "192.168.0.0/16", "198.18.0.0/15", "224.0.0.0/3",
        "::1/128", "fc00::/7", "fe80::/10", "ff00::/8",
    ]

    /// Every DNS question from the device goes to that resolver
    static let dnsRule: [String: Any] = [
        "type": "field",
        "inboundTag": ["socks-in"],
        "port": "53",
        "outboundTag": "dns-out",
    ]

    static func inbound(access: LocalProxyAccess) -> [String: Any] {
        [
            "tag": "socks-in",
            "listen": "127.0.0.1",
            "port": access.port,
            "protocol": "socks",
            "settings": [
                "auth": "password",
                "accounts": [["user": access.username, "pass": access.password]],
                "udp": true,
            ],
            "sniffing": ["enabled": true, "destOverride": ["http", "tls", "quic"]],
        ]
    }

    /// The one outbound: the server this link points at
    static func outbound(for link: ProxyLinkConfig, address: String? = nil) -> [String: Any] {
        let address = address ?? link.host
        switch link.credential {
        case .shadowsocks(let method, let password):
            return [
                "tag": "proxy",
                "protocol": "shadowsocks",
                "settings": ["servers": [[
                    "address": address,
                    "port": link.port,
                    "method": method,
                    "password": password,
                    "uot": true,
                ]]],
            ]
        case .vless(let vless):
            var outbound: [String: Any] = [
                "tag": "proxy",
                "protocol": "vless",
                "settings": ["vnext": [[
                    "address": address,
                    "port": link.port,
                    "users": [user(vless)],
                ]]],
            ]
            outbound["streamSettings"] = streamSettings(
                vless, fallbackName: address == link.host ? nil : link.host)
            return outbound
        }
    }

    /// The VLESS user
    private static func user(_ vless: ProxyLinkConfig.VLESSParameters) -> [String: Any] {
        var user: [String: Any] = ["id": vless.uuid, "encryption": "none"]
        if !vless.flow.isEmpty { user["flow"] = vless.flow }
        return user
    }

    private static func streamSettings(
        _ vless: ProxyLinkConfig.VLESSParameters, fallbackName: String?) -> [String: Any] {
        let name = vless.sni.isEmpty ? (fallbackName ?? "") : vless.sni
        var stream: [String: Any] = ["network": vless.network]
        switch vless.network {
        case "ws":
            var ws: [String: Any] = ["path": vless.path.isEmpty ? "/" : vless.path]
            if !vless.host.isEmpty { ws["headers"] = ["Host": vless.host] }
            stream["wsSettings"] = ws
        case "grpc":
            stream["grpcSettings"] = ["serviceName": vless.serviceName]
        default:
            break
        }
        switch vless.security {
        case "reality":
            stream["security"] = "reality"
            var reality: [String: Any] = [
                "publicKey": vless.publicKey,
                "shortId": vless.shortID,
                "fingerprint": vless.fingerprint.isEmpty ? "chrome" : vless.fingerprint,
            ]
            if !name.isEmpty { reality["serverName"] = name }
            stream["realitySettings"] = reality
        case "tls":
            stream["security"] = "tls"
            var tls: [String: Any] = ["allowInsecure": false]
            if !name.isEmpty { tls["serverName"] = name }
            if !vless.fingerprint.isEmpty { tls["fingerprint"] = vless.fingerprint }
            stream["tlsSettings"] = tls
        default:
            break
        }
        return stream
    }
}
