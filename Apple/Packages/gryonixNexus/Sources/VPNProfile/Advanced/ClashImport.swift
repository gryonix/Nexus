import Foundation

/// Reads a Clash profile: proxies and a subset of rules.

public enum ClashImport {
    public static func looksLikeClash(_ text: String) -> Bool {
        text.contains("proxies:") && !text.hasPrefix("vless://")
    }

    public static func parse(_ text: String) -> AdvancedImportReport {
        var report = AdvancedImportReport()
        let root = MiniYAML.parse(text)
        for entry in root["proxies"]?.list ?? [] {
            switch server(from: entry) {
            case .success(let server): report.servers.append(server)
            case .failure(let skip): report.unsupported.append(skip)
            }
        }
        for line in root["rules"]?.list ?? [] {
            guard let raw = line.string else { continue }
            switch rule(from: raw) {
            case .success(let rule): report.rules.append(rule)
            case .failure(let skip): report.unsupported.append(skip)
            }
        }
        return report
    }

    // MARK: Proxies

    static func server(from entry: YAMLValue) -> Result<AdvancedServer, AdvancedImportReport.Skipped> {
        let name = entry["name"]?.string ?? ""
        let type = entry["type"]?.string?.lowercased() ?? ""
        guard let host = entry["server"]?.string, let port = entry["port"]?.string.flatMap(Int.init) else {
            return .failure(.init(name: name, reason: "the proxy is incomplete"))
        }
        let result: [String: String]?
        let kind: AdvancedServer.Kind
        switch type {
        case "ss": kind = .shadowsocks; result = shadowsocks(entry)
        case "vmess": kind = .vmess; result = stream(entry, secret: "uuid")
        case "vless": kind = .vless; result = stream(entry, secret: "uuid")
        case "trojan": kind = .trojan; result = stream(entry, secret: "password")
        case "wireguard": kind = .wireguard; result = wireguard(entry)
        case "hysteria2": kind = .hysteria2; result = hysteria2(entry)
        default:
            return .failure(.init(name: name, reason: "\(type) is not supported by the VPN engine"))
        }
        guard var fields = result else {
            return .failure(.init(name: name, reason: reason(for: entry, type: type)))
        }
        addProtocolFields(&fields, entry: entry, type: type)
        return .success(AdvancedServer(kind: kind, name: name, host: host, port: port, fields: fields))
    }

    private static func reason(for entry: YAMLValue, type: String) -> String {
        if type == "ss" { return entry["plugin"] != nil ? "plugins are not supported" : "the proxy is incomplete" }
        if type == "hysteria2" { return "the proxy is incomplete" }
        let network = entry["network"]?.string ?? "tcp"
        return "transport \(network) is not supported"
    }

    private static func addProtocolFields(_ fields: inout [String: String], entry: YAMLValue, type: String) {
        if type == "vmess" {
            fields["alterId"] = entry["alterId"]?.string ?? "0"
            fields["scy"] = entry["cipher"]?.string ?? "auto"
        }
        if type == "vless", let flow = entry["flow"]?.string { fields["flow"] = flow }
    }

    private static func shadowsocks(_ entry: YAMLValue) -> [String: String]? {
        guard entry["plugin"] == nil, let method = entry["cipher"]?.string,
              let password = entry["password"]?.string else { return nil }
        return ["method": method, "password": password]
    }

    private static func hysteria2(_ entry: YAMLValue) -> [String: String]? {
        guard let password = entry["password"]?.string else { return nil }
        var fields = ["password": password]
        if let name = entry["sni"]?.string { fields["sni"] = name }
        if entry["skip-cert-verify"]?.string == "true" { fields["insecure"] = "1" }
        if let obfs = entry["obfs"]?.string { fields["obfs"] = obfs }
        if let secret = entry["obfs-password"]?.string { fields["obfsPassword"] = secret }
        return fields
    }

    private static func wireguard(_ entry: YAMLValue) -> [String: String]? {
        guard let key = entry["private-key"]?.string, let peer = entry["public-key"]?.string,
              let address = entry["ip"]?.string else { return nil }
        var fields = ["secretKey": key, "publicKey": peer, "address": address]
        if let mtu = entry["mtu"]?.string { fields["mtu"] = mtu }
        if let shared = entry["pre-shared-key"]?.string { fields["preSharedKey"] = shared }
        if let reserved = entry["reserved"]?.list {
            fields["reserved"] = reserved.compactMap(\.string).joined(separator: ",")
        }
        return fields
    }

    private static func stream(_ entry: YAMLValue, secret: String) -> [String: String]? {
        guard let value = entry[secret]?.string else { return nil }
        let network = entry["network"]?.string ?? "tcp"
        guard SubscriptionImport.carriedNetworks.contains(network) else { return nil }
        let reality = entry["reality-opts"]
        let tls = entry["tls"]?.string == "true" || entry["type"]?.string == "trojan"
        var fields = [secret: value, "network": network,
                      "security": reality != nil ? "reality" : (tls ? "tls" : "none")]
        let names = ["servername": "sni", "sni": "sni", "client-fingerprint": "fp"]
        for (key, name) in names.sorted(by: { $0.key < $1.key }) {
            if let text = entry[key]?.string, fields[name] == nil { fields[name] = text }
        }
        if entry["skip-cert-verify"]?.string == "true" { fields["insecure"] = "1" }
        if let key = reality?["public-key"]?.string { fields["pbk"] = key }
        if let id = reality?["short-id"]?.string { fields["sid"] = id }
        addTransport(&fields, entry: entry)
        return fields
    }

    private static func addTransport(_ fields: inout [String: String], entry: YAMLValue) {
        if let ws = entry["ws-opts"] {
            if let path = ws["path"]?.string { fields["path"] = path }
            if let host = ws["headers"]?["Host"]?.string { fields["host"] = host }
        }
        if let name = entry["grpc-opts"]?["grpc-service-name"]?.string { fields["serviceName"] = name }
        if let upgrade = entry["http-upgrade-opts"] ?? entry["httpupgrade-opts"] {
            if let path = upgrade["path"]?.string { fields["path"] = path }
            if let host = upgrade["host"]?.string { fields["host"] = host }
        }
    }

    // MARK: Rules

    static func rule(from line: String) -> Result<AdvancedRule, AdvancedImportReport.Skipped> {
        let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let kinds: [String: AdvancedRule.Kind] = [
            "DOMAIN": .domain, "DOMAIN-SUFFIX": .domainSuffix, "DOMAIN-KEYWORD": .keyword,
            "IP-CIDR": .ip, "IP-CIDR6": .ip, "GEOIP": .geoip,
        ]
        guard parts.count >= 3, let kind = kinds[parts[0].uppercased()] else {
            let head = parts.first ?? ""
            let final = head.uppercased() == "MATCH" || head.uppercased() == "FINAL"
            return .failure(.init(name: line, reason: final ? "set the final rule by hand"
                                                            : "\(head) rules are not supported"))
        }
        return .success(AdvancedRule(kind: kind, value: parts[1], action: action(forPolicy: parts[2])))
    }

    public static func action(forPolicy policy: String) -> AdvancedRule.Action {
        switch policy.uppercased() {
        case "DIRECT": return .direct
        case "REJECT", "REJECT-DROP", "REJECT-TINYGIF": return .block
        default: return .proxy
        }
    }
}
