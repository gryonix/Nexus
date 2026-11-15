import Foundation

/// Hysteria2, NaiveProxy and blake3 Shadowsocks outbounds.

extension AdvancedXrayConfiguration {
    public static func isShadowsocks2022(_ server: AdvancedServer) -> Bool {
        server.kind == .shadowsocks && (server.fields["method"] ?? "").hasPrefix("2022-")
    }

    /// Members that need a local blake3 Shadowsocks client
    public static func ss2022Members(of profile: AdvancedProfile) -> [AdvancedServer] {
        ((try? members(of: profile)) ?? []).filter(isShadowsocks2022)
    }

    static func localSocksOutbound(tag: String, port: Int, access: LocalProxyAccess) -> [String: Any] {
        let user: [String: Any] = ["user": access.username, "pass": access.password]
        return ["tag": tag, "protocol": "socks",
                "settings": ["servers": [["address": "127.0.0.1", "port": port, "users": [user]]]]]
    }

    static func hysteria2Outbound(_ server: AdvancedServer, tag: String, address: String) -> [String: Any] {
        let fields = server.fields
        var tls: [String: Any] = ["allowInsecure": fields["insecure"] == "1", "alpn": ["h3"]]
        let name = fields["sni"] ?? server.host
        if !name.isEmpty { tls["serverName"] = name }
        var stream: [String: Any] = [
            "network": "hysteria", "security": "tls", "tlsSettings": tls,
            "hysteriaSettings": ["version": 2, "auth": fields["password"] ?? ""],
        ]
        if fields["obfs"] == "salamander", let secret = fields["obfsPassword"] {
            stream["finalmask"] = ["udp": [["type": "salamander", "settings": ["password": secret]]]]
        }
        return ["tag": tag, "protocol": "hysteria",
                "settings": ["version": 2, "address": address, "port": server.port],
                "streamSettings": stream]
    }

    /// HTTP/2 CONNECT over TLS, which NaiveProxy servers accept
    static func naiveOutbound(_ server: AdvancedServer, tag: String, address: String) -> [String: Any] {
        let fields = server.fields
        var settings: [String: Any] = ["address": address, "port": server.port]
        if let user = fields["user"], !user.isEmpty {
            settings["user"] = user
            settings["pass"] = fields["password"] ?? ""
        }
        let tls: [String: Any] = ["serverName": fields["sni"] ?? server.host, "alpn": ["h2", "http/1.1"],
                                  "fingerprint": "chrome", "allowInsecure": fields["insecure"] == "1"]
        return ["tag": tag, "protocol": "http", "settings": settings,
                "streamSettings": ["network": "tcp", "security": "tls", "tlsSettings": tls]]
    }
}
