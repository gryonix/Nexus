import Foundation

/// DNS over TLS through a loopback bridge, and host rewrites.

public struct AdvancedHostRewrite: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var domain: String
    /// An IP address or another domain
    public var target: String

    public init(id: String = UUID().uuidString, domain: String, target: String) {
        self.id = id
        self.domain = domain
        self.target = target
    }
}

extension AdvancedXrayConfiguration {
    static let dotPort = 853

    struct DoTBridge {
        let inbound: [String: Any]
        let outbound: [String: Any]
        let rule: [String: Any]
    }

    /// DoT upstreams, each needing one loopback port
    public static func dotUpstreams(of profile: AdvancedProfile) -> [AdvancedDNSUpstream] {
        profile.dns.filter { $0.kind == .dot && endpoint(ofDoT: $0.address) != nil }
    }

    /// Host and port of a DoT address like dns.example:853
    public static func endpoint(ofDoT text: String) -> (host: String, port: Int)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "tls://", with: "")
        if trimmed.filter({ $0 == ":" }).count > 1, !trimmed.hasPrefix("[") { return (trimmed, dotPort) }
        guard let parts = ProxyLinkParts("tls://" + trimmed), !parts.host.isEmpty else { return nil }
        return (parts.host, parts.port ?? dotPort)
    }

    static func dotBridges(_ profile: AdvancedProfile, options: Options, proxyTag: String) -> [DoTBridge] {
        dotUpstreams(of: profile).enumerated().compactMap { index, upstream in
            guard let port = options.dotPorts[upstream.id],
                  let (host, remotePort) = endpoint(ofDoT: upstream.address) else { return nil }
            return dotBridge(index: index, host: host, remotePort: remotePort, localPort: port,
                             address: options.resolved[host] ?? host,
                             proxyTag: upstream.viaProxy ? proxyTag : nil)
        }
    }

    private static func dotBridge(index: Int, host: String, remotePort: Int, localPort: Int,
                                  address: String, proxyTag: String?) -> DoTBridge {
        let inboundTag = "dot-in-\(index)", outboundTag = "dot-\(index)"
        let inbound: [String: Any] = [
            "tag": inboundTag, "listen": "127.0.0.1", "port": localPort, "protocol": "dokodemo-door",
            "settings": ["address": address, "port": remotePort, "network": "tcp"],
        ]
        var outbound: [String: Any] = [
            "tag": outboundTag, "protocol": "freedom",
            "streamSettings": ["network": "tcp", "security": "tls", "tlsSettings": ["serverName": host]],
        ]
        if let proxyTag { outbound["proxySettings"] = ["tag": proxyTag] }
        let rule: [String: Any] = ["type": "field", "inboundTag": [inboundTag], "outboundTag": outboundTag]
        return DoTBridge(inbound: inbound, outbound: outbound, rule: rule)
    }

    static func hostsMap(_ profile: AdvancedProfile) -> [String: String]? {
        guard profile.rewritesEnabled else { return nil }
        var map: [String: String] = [:]
        for rewrite in profile.hosts {
            let domain = rewrite.domain.trimmingCharacters(in: .whitespaces)
            let target = rewrite.target.trimmingCharacters(in: .whitespaces)
            guard !domain.isEmpty, !target.isEmpty else { continue }
            map[domain.contains(":") ? domain : "full:\(domain)"] = target
        }
        return map.isEmpty ? nil : map
    }
}
