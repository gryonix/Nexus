import Foundation

/// Builds the xray JSON for an advanced profile.

public enum AdvancedXrayConfiguration {
    static let balancerTag = "auto"
    static let probeURL = "https://www.gstatic.com/generate_204"
    static let memberLimit = 40
    public static let statsAPIPort = 10085

    public struct Options: Sendable {
        public var dns: [String]
        /// Host to IP, resolved before the tunnel is up
        public var resolved: [String: String]
        public var statsPort: Int?
        public var accessLogPath: String?
        /// Server id to its local Shadowsocks client port
        public var ss2022Ports: [String: Int]
        /// DNS upstream id to its local DoT bridge port
        public var dotPorts: [String: Int]

        public init(dns: [String] = ProxyTunnelText.fallbackDNS, resolved: [String: String] = [:],
                    statsPort: Int? = nil, accessLogPath: String? = nil,
                    ss2022Ports: [String: Int] = [:], dotPorts: [String: Int] = [:]) {
            self.dns = dns
            self.resolved = resolved
            self.statsPort = statsPort
            self.accessLogPath = accessLogPath
            self.ss2022Ports = ss2022Ports
            self.dotPorts = dotPorts
        }
    }

    public enum BuildError: Error, Equatable {
        case noActiveServer
    }

    /// The servers the active target runs, in order
    public static func members(of profile: AdvancedProfile) throws -> [AdvancedServer] {
        switch profile.activeTarget {
        case .server(let server): return [server]
        case .group(let group):
            let all = group.memberIDs.compactMap(profile.server)
            guard !all.isEmpty else { throw BuildError.noActiveServer }
            if group.mode == .auto { return Array(all.prefix(memberLimit)) }
            return all.first { $0.id == group.chosenID }.map { [$0] } ?? []
        case nil: throw BuildError.noActiveServer
        }
    }

    public static func usesBalancer(_ profile: AdvancedProfile) -> Bool {
        if case .group(let group) = profile.activeTarget, group.mode == .auto { return true }
        return false
    }

    public static func json(profile: AdvancedProfile, access: LocalProxyAccess,
                            options: Options = Options()) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: try document(profile: profile, access: access, options: options),
                                              options: [.sortedKeys, .prettyPrinted])
        return String(decoding: data, as: UTF8.self)
    }

    public static func document(profile: AdvancedProfile, access: LocalProxyAccess,
                                options: Options) throws -> [String: Any] {
        let servers = try members(of: profile)
        guard !servers.isEmpty else { throw BuildError.noActiveServer }
        let balanced = usesBalancer(profile)
        let tags = servers.indices.map { balanced ? "s\($0)" : "proxy" }
        let bridges = dotBridges(profile, options: options, proxyTag: tags[0])
        var outbounds = zip(servers, tags).map { outbound(for: $0, tag: $1, options: options, access: access) }
        outbounds += [XrayConfiguration.dnsOutbound, XrayConfiguration.blockOutbound, ["tag": "direct", "protocol": "freedom"]]
        outbounds += bridges.map(\.outbound)
        var routing: [String: Any] = [
            "domainStrategy": needsIPMatching(profile) ? "IPIfNonMatch" : "AsIs",
            "rules": bridges.map(\.rule) + rules(profile: profile, balanced: balanced, options: options),
        ]
        if balanced { routing["balancers"] = [balancer(tags: tags)] }
        var document: [String: Any] = [
            "log": ["loglevel": "warning"],
            "inbounds": [XrayConfiguration.inbound(access: access)] + bridges.map(\.inbound),
            "outbounds": outbounds,
            "dns": dnsSection(profile, options: options),
            "routing": routing,
            "policy": ["levels": ["0": ["connIdle": XrayConfiguration.idleSeconds,
                                        "bufferSize": XrayConfiguration.bufferKilobytes]]],
        ]
        if balanced { document["observatory"] = observatory(tags: tags) }
        if let path = options.accessLogPath { document["log"] = ["loglevel": "warning", "access": path] }
        if let port = options.statsPort { addStats(&document, port: port) }
        return document
    }

    // MARK: Outbounds

    static func outbound(for server: AdvancedServer, tag: String, options: Options,
                         access: LocalProxyAccess) -> [String: Any] {
        let address = options.resolved[server.host] ?? server.host
        if isShadowsocks2022(server) {
            return localSocksOutbound(tag: tag, port: options.ss2022Ports[server.id] ?? 0, access: access)
        }
        switch server.kind {
        case .hysteria2: return hysteria2Outbound(server, tag: tag, address: address)
        case .naive: return naiveOutbound(server, tag: tag, address: address)
        default: break
        }
        let fields = server.fields
        var result: [String: Any] = ["tag": tag, "protocol": server.kind.rawValue]
        switch server.kind {
        case .vless:
            var user: [String: Any] = ["id": fields["uuid"] ?? "", "encryption": "none"]
            if let flow = fields["flow"] { user["flow"] = flow }
            result["settings"] = ["vnext": [["address": address, "port": server.port, "users": [user]]]]
        case .vmess:
            let user: [String: Any] = ["id": fields["uuid"] ?? "", "security": fields["scy"] ?? "auto",
                                       "alterId": Int(fields["alterId"] ?? "0") ?? 0]
            result["settings"] = ["vnext": [["address": address, "port": server.port, "users": [user]]]]
        case .trojan:
            result["settings"] = ["servers": [["address": address, "port": server.port,
                                               "password": fields["password"] ?? ""]]]
        case .shadowsocks:
            result["settings"] = ["servers": [["address": address, "port": server.port,
                                               "method": fields["method"] ?? "", "password": fields["password"] ?? "",
                                               "uot": true]]]
        case .wireguard:
            result["settings"] = wireguardSettings(server, address: address)
        case .hysteria2, .naive: break
        }
        if server.kind != .wireguard && server.kind != .shadowsocks {
            result["streamSettings"] = streamSettings(server, address: address, options: options)
        }
        return result
    }

    private static func wireguardSettings(_ server: AdvancedServer, address: String) -> [String: Any] {
        let fields = server.fields
        var peer: [String: Any] = ["publicKey": fields["publicKey"] ?? "",
                                   "endpoint": "\(address.contains(":") ? "[\(address)]" : address):\(server.port)",
                                   "allowedIPs": ["0.0.0.0/0", "::/0"]]
        if let shared = fields["preSharedKey"] { peer["preSharedKey"] = shared }
        var settings: [String: Any] = [
            "secretKey": fields["secretKey"] ?? "",
            "address": (fields["address"] ?? "").split(separator: ",").map(String.init),
            "peers": [peer],
            "mtu": Int(fields["mtu"] ?? "") ?? Tun2SocksConfiguration.mtu,
        ]
        if let reserved = fields["reserved"] {
            settings["reserved"] = reserved.split(separator: ",").compactMap { Int($0) }
        }
        return settings
    }

    static func streamSettings(_ server: AdvancedServer, address: String, options: Options) -> [String: Any] {
        let fields = server.fields
        let network = fields["network"] ?? "tcp"
        let xrayNetwork = network == "xhttp" ? "splithttp" : network
        var stream: [String: Any] = ["network": xrayNetwork]
        let path = fields["path"].flatMap { $0.isEmpty ? nil : $0 } ?? "/"
        switch xrayNetwork {
        case "ws":
            var ws: [String: Any] = ["path": path]
            if let host = fields["host"] { ws["headers"] = ["Host": host] }
            stream["wsSettings"] = ws
        case "grpc":
            stream["grpcSettings"] = ["serviceName": fields["serviceName"] ?? ""]
        case "httpupgrade", "splithttp":
            var settings: [String: Any] = ["path": path]
            if let host = fields["host"] { settings["host"] = host }
            stream[xrayNetwork == "httpupgrade" ? "httpupgradeSettings" : "splithttpSettings"] = settings
        default: break
        }
        let name = fields["sni"] ?? (address == server.host ? "" : server.host)
        switch fields["security"] ?? "none" {
        case "reality":
            stream["security"] = "reality"
            var reality: [String: Any] = ["publicKey": fields["pbk"] ?? "", "shortId": fields["sid"] ?? "",
                                          "fingerprint": fields["fp"] ?? "chrome"]
            if !name.isEmpty { reality["serverName"] = name }
            stream["realitySettings"] = reality
        case "tls":
            stream["security"] = "tls"
            var tls: [String: Any] = ["allowInsecure": fields["insecure"] == "1"]
            if !name.isEmpty { tls["serverName"] = name }
            if let fingerprint = fields["fp"] { tls["fingerprint"] = fingerprint }
            if let alpn = fields["alpn"] { tls["alpn"] = alpn.split(separator: ",").map(String.init) }
            stream["tlsSettings"] = tls
        default: break
        }
        return stream
    }

    // MARK: Balancer

    static func balancer(tags: [String]) -> [String: Any] {
        ["tag": balancerTag, "selector": tags, "strategy": ["type": "leastPing"], "fallbackTag": tags.first ?? "direct"]
    }

    static func observatory(tags: [String]) -> [String: Any] {
        ["subjectSelector": tags, "probeURL": probeURL, "probeInterval": "5m", "enableConcurrency": true]
    }

    // MARK: Stats

    private static func addStats(_ document: inout [String: Any], port: Int) {
        document["stats"] = [String: Any]()
        document["metrics"] = ["listen": "127.0.0.1:\(port)"]
        var policy = document["policy"] as? [String: Any] ?? [:]
        policy["system"] = ["statsOutboundUplink": true, "statsOutboundDownlink": true]
        document["policy"] = policy
    }
}
