import Foundation

/// Reads a subscription body or one link into servers.

public enum SubscriptionImport {
    static let carriedNetworks: Set<String> = ["tcp", "ws", "grpc", "httpupgrade", "xhttp", "splithttp"]
    static let carriedSecurities: Set<String> = ["none", "tls", "reality"]

    /// A subscription: base64 list, plain list, or Clash YAML
    public static func parse(body: String) -> AdvancedImportReport {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if ClashImport.looksLikeClash(text) { return ClashImport.parse(text) }
        if !text.contains("://"), let decoded = LinkBase64.decode(text) {
            if ClashImport.looksLikeClash(decoded) { return ClashImport.parse(decoded) }
            return parse(lines: decoded)
        }
        return parse(lines: text)
    }

    static func parse(lines text: String) -> AdvancedImportReport {
        var report = AdvancedImportReport()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.contains("://") else { continue }
            switch parse(link: line) {
            case .success(let server): report.servers.append(server)
            case .failure(let skip): report.unsupported.append(skip)
            }
        }
        return report
    }

    public static func parse(link: String) -> Result<AdvancedServer, AdvancedImportReport.Skipped> {
        let scheme = link.prefix { $0 != ":" }.lowercased()
        switch scheme {
        case "vless": return vless(link)
        case "vmess": return vmess(link)
        case "trojan": return trojan(link)
        case "ss": return shadowsocks(link)
        case "hysteria2", "hy2": return hysteria2(link)
        case "naive+https": return naive(link)
        default:
            return .failure(.init(name: link.prefix(40).description,
                                  reason: "\(scheme) is not supported by the VPN engine"))
        }
    }

    static func skip(_ parts: ProxyLinkParts?, _ link: String, _ reason: String)
        -> Result<AdvancedServer, AdvancedImportReport.Skipped> {
        .failure(.init(name: parts?.fragment.isEmpty == false ? parts!.fragment : String(link.prefix(40)),
                       reason: reason))
    }

    private static func vless(_ link: String) -> Result<AdvancedServer, AdvancedImportReport.Skipped> {
        guard let parts = ProxyLinkParts(link), let port = parts.port, !parts.host.isEmpty,
              !parts.userInfo.isEmpty else { return skip(nil, link, "the link is incomplete") }
        let security = parts.query["security"] ?? "none"
        let network = parts.query["type"] ?? "tcp"
        guard carriedSecurities.contains(security) else { return skip(parts, link, "security \(security)") }
        guard carriedNetworks.contains(network) else { return skip(parts, link, "transport \(network)") }
        var fields = transportFields(parts.query, security: security, network: network)
        fields["uuid"] = parts.userInfo
        if security != "none", let flow = parts.query["flow"] { fields["flow"] = flow }
        return .success(AdvancedServer(kind: .vless, name: parts.fragment, host: parts.host,
                                       port: port, fields: fields))
    }

    private static func trojan(_ link: String) -> Result<AdvancedServer, AdvancedImportReport.Skipped> {
        guard let parts = ProxyLinkParts(link), let port = parts.port, !parts.host.isEmpty,
              !parts.userInfo.isEmpty else { return skip(nil, link, "the link is incomplete") }
        let security = parts.query["security"] ?? "tls"
        let network = parts.query["type"] ?? "tcp"
        guard carriedSecurities.contains(security) else { return skip(parts, link, "security \(security)") }
        guard carriedNetworks.contains(network) else { return skip(parts, link, "transport \(network)") }
        var fields = transportFields(parts.query, security: security, network: network)
        fields["password"] = parts.userInfo.removingPercentEncoding ?? parts.userInfo
        return .success(AdvancedServer(kind: .trojan, name: parts.fragment, host: parts.host,
                                       port: port, fields: fields))
    }

    static func transportFields(_ query: [String: String], security: String, network: String) -> [String: String] {
        var fields: [String: String] = ["security": security, "network": network]
        let map = ["sni": "sni", "peer": "sni", "fp": "fp", "pbk": "pbk", "sid": "sid", "path": "path",
                   "host": "host", "serviceName": "serviceName", "alpn": "alpn"]
        for (key, name) in map.sorted(by: { $0.key < $1.key }) {
            if let value = query[key], fields[name] == nil { fields[name] = value }
        }
        if query["allowInsecure"] == "1" || query["insecure"] == "1" { fields["insecure"] = "1" }
        return fields
    }

    private static func vmess(_ link: String) -> Result<AdvancedServer, AdvancedImportReport.Skipped> {
        let body = String(link.dropFirst("vmess://".count))
        guard let decoded = LinkBase64.decode(body),
              let object = try? JSONSerialization.jsonObject(with: Data(decoded.utf8)) as? [String: Any],
              let host = object["add"] as? String, let uuid = object["id"] as? String,
              let port = Self.integer(object["port"]) else { return skip(nil, link, "the link is incomplete") }
        let name = object["ps"] as? String ?? ""
        let network = (object["net"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "tcp"
        guard carriedNetworks.contains(network) else { return skip(nil, name.isEmpty ? link : name, "transport \(network)") }
        let tls = (object["tls"] as? String) == "tls"
        var fields = ["uuid": uuid, "network": network, "security": tls ? "tls" : "none",
                      "scy": object["scy"] as? String ?? "auto", "alterId": String(Self.integer(object["aid"]) ?? 0)]
        for (key, name) in ["sni": "sni", "host": "host", "path": "path", "fp": "fp", "alpn": "alpn"] {
            if let value = object[key] as? String, !value.isEmpty { fields[name] = value }
        }
        if network == "grpc", let path = fields["path"] { fields["serviceName"] = path }
        return .success(AdvancedServer(kind: .vmess, name: name, host: host, port: port, fields: fields))
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        return (value as? String).flatMap { Int($0) }
    }

    private static func shadowsocks(_ link: String) -> Result<AdvancedServer, AdvancedImportReport.Skipped> {
        guard let parts = ProxyLinkParts(link) else { return skip(nil, link, "the link is incomplete") }
        guard let found = shadowsocksParts(parts) else { return skip(parts, link, "the link is incomplete") }
        if parts.query["plugin"] != nil { return skip(parts, link, "plugins are not supported") }
        return .success(AdvancedServer(kind: .shadowsocks, name: parts.fragment, host: found.host,
                                       port: found.port,
                                       fields: ["method": found.method, "password": found.password]))
    }

    private static func shadowsocksParts(_ parts: ProxyLinkParts)
        -> (method: String, password: String, host: String, port: Int)? {
        if let port = parts.port, !parts.userInfo.isEmpty, !parts.host.isEmpty {
            let plain = parts.userInfo.removingPercentEncoding ?? parts.userInfo
            let pair = plain.contains(":") ? plain : (LinkBase64.decode(parts.userInfo) ?? "")
            guard let colon = pair.firstIndex(of: ":") else { return nil }
            return (String(pair[..<colon]), String(pair[pair.index(after: colon)...]), parts.host, port)
        }
        guard let decoded = LinkBase64.decode(parts.body), let at = decoded.lastIndex(of: "@"),
              let inner = ProxyLinkParts("ss://" + String(decoded[decoded.index(after: at)...])),
              let port = inner.port else { return nil }
        let pair = decoded[..<at]
        guard let colon = pair.firstIndex(of: ":") else { return nil }
        return (String(pair[..<colon]), String(pair[pair.index(after: colon)...]), inner.host, port)
    }
}
