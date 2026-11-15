#if GRYONIX_PROXY_TUNNEL
import Foundation
@preconcurrency import NetworkExtension
import VPNProfile

/// The advanced profile: many servers, rules, balancer, stats
extension XrayDatapath {
    static func removeAccessLog() { try? FileManager.default.removeItem(at: accessLogURL) }

    private static var accessLogURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("access.log")
    }

    func startAdvanced(json: String, dns: [String], access: LocalProxyAccess,
                       on provider: NEPacketTunnelProvider) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profile = try decoder.decode(AdvancedProfile.self, from: Data(json.utf8))
        let servers = try AdvancedXrayConfiguration.members(of: profile)
        let dotHosts = AdvancedXrayConfiguration.dotUpstreams(of: profile)
            .compactMap { AdvancedXrayConfiguration.endpoint(ofDoT: $0.address)?.host }
        let resolved = await Self.resolve(servers.map(\.host) + dotHosts)
        let remote = servers.first.flatMap { resolved[$0.host] } ?? servers.first?.host ?? "127.0.0.1"
        try await provider.setTunnelNetworkSettings(Self.networkSettings(remote: remote, dns: dns))
        try? FileManager.default.removeItem(at: Self.accessLogURL)
        var options = AdvancedXrayConfiguration.Options(
            dns: ProxyTunnelText.reachableDNS(dns), resolved: resolved,
            statsPort: profile.collectsTraffic ? AdvancedXrayConfiguration.statsAPIPort : nil,
            accessLogPath: profile.collectsTraffic ? Self.accessLogURL.path : nil)
        options.dotPorts = Dictionary(uniqueKeysWithValues: AdvancedXrayConfiguration.dotUpstreams(of: profile)
            .map { ($0.id, LocalProxyAccess.freeLoopbackPort()) })
        do {
            options.ss2022Ports = try Self.startShadowsocksClients(profile, resolved: resolved, access: access)
            try Self.runCore(json: try AdvancedXrayConfiguration.json(profile: profile, access: access, options: options))
        } catch {
            _ = Self.answer(GryonixSSStop())
            throw error
        }
    }

    private static func resolve(_ hosts: [String]) async -> [String: String] {
        var resolved: [String: String] = [:]
        for host in Set(hosts) {
            if let address = await Task.detached(operation: { numericAddress(of: host) }).value {
                resolved[host] = address
            }
        }
        return resolved
    }

    /// One local client per blake3 Shadowsocks member
    private static func startShadowsocksClients(_ profile: AdvancedProfile, resolved: [String: String],
                                                access: LocalProxyAccess) throws -> [String: Int] {
        var ports: [String: Int] = [:]
        for server in AdvancedXrayConfiguration.ss2022Members(of: profile) {
            let port = LocalProxyAccess.freeLoopbackPort()
            let host = resolved[server.host] ?? server.host
            let remote = host.contains(":") ? "[\(host)]:\(server.port)" : "\(host):\(server.port)"
            try check(GryonixSSStart("127.0.0.1:\(port)", remote, server.fields["method"] ?? "",
                                     server.fields["password"] ?? "", access.username, access.password))
            ports[server.id] = port
        }
        return ports
    }

    func advancedTraffic() async -> AdvancedTraffic {
        var traffic = AdvancedTraffic()
        let address = "http://127.0.0.1:\(AdvancedXrayConfiguration.statsAPIPort)/debug/vars"
        if let url = URL(string: address), let (data, _) = try? await URLSession.shared.data(from: url) {
            traffic = AdvancedTraffic.counters(fromMetrics: data)
        }
        if let log = Self.recentLog() { traffic.requests = AdvancedTraffic.requests(fromLog: log) }
        return traffic
    }

    private static func recentLog() -> String? {
        guard let handle = try? FileHandle(forReadingFrom: accessLogURL) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
        return (try? handle.readToEnd()).flatMap { String(data: $0, encoding: .utf8) }
    }
}
#endif
