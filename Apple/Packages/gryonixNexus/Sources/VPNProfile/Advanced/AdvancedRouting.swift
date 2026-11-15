import Foundation

/// Routing rules and DNS servers for the advanced xray config.

extension AdvancedXrayConfiguration {
    static func needsIPMatching(_ profile: AdvancedProfile) -> Bool {
        profile.rules.contains { $0.kind == .ip || $0.kind == .geoip }
    }

    /// Country rules without downloaded networks, for the screen
    public static func skippedRules(_ profile: AdvancedProfile) -> [AdvancedRule] {
        profile.rules.filter { $0.kind == .geoip && profile.geoip.networks(for: $0.value) == nil }
    }

    static func target(_ action: AdvancedRule.Action, balanced: Bool) -> [String: Any] {
        switch action {
        case .direct: return ["outboundTag": "direct"]
        case .block: return ["outboundTag": "block"]
        case .proxy: return balanced ? ["balancerTag": balancerTag] : ["outboundTag": "proxy"]
        }
    }

    static func rules(profile: AdvancedProfile, balanced: Bool, options: Options) -> [[String: Any]] {
        var result: [[String: Any]] = [XrayConfiguration.dnsRule]
        var query = target(.proxy, balanced: balanced)
        query["type"] = "field"
        query["inboundTag"] = [XrayConfiguration.dnsQueryTag]
        result.append(query)
        result.append(XrayConfiguration.quicRule)
        result += blockListRules(profile.blockLists)
        result += userRules(profile.rules, balanced: balanced, geoip: profile.geoip)
        result.append(XrayConfiguration.privateRule)
        var final = target(profile.finalAction, balanced: balanced)
        final["type"] = "field"
        final["network"] = "tcp,udp"
        result.append(final)
        return result
    }

    static func blockListRules(_ lists: [AdvancedBlockList]) -> [[String: Any]] {
        let domains = lists.flatMap(\.domains).map { "domain:\($0)" }
        guard !domains.isEmpty else { return [] }
        return [["type": "field", "domain": domains, "outboundTag": "block"]]
    }

    static func userRules(_ rules: [AdvancedRule], balanced: Bool, geoip: AdvancedGeoIP) -> [[String: Any]] {
        var grouped: [(field: String, action: AdvancedRule.Action, values: [String])] = []
        for rule in rules {
            guard let (field, values) = match(rule, geoip: geoip) else { continue }
            if let last = grouped.last, last.field == field, last.action == rule.action {
                grouped[grouped.count - 1].values += values
            } else {
                grouped.append((field, rule.action, values))
            }
        }
        return grouped.map { group in
            var entry = target(group.action, balanced: balanced)
            entry["type"] = "field"
            entry[group.field] = group.values
            return entry
        }
    }

    static func match(_ rule: AdvancedRule, geoip: AdvancedGeoIP) -> (String, [String])? {
        let value = rule.value.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        switch rule.kind {
        case .domain: return ("domain", ["full:\(value)"])
        case .domainSuffix: return ("domain", ["domain:\(value)"])
        case .keyword: return ("domain", ["keyword:\(value)"])
        case .ip: return ("ip", [value])
        case .geoip: return geoip.networks(for: value).map { ("ip", $0) }
        }
    }

    // MARK: DNS

    static func dnsSection(_ profile: AdvancedProfile, options: Options) -> [String: Any] {
        let upstreams = profile.dns.filter { $0.kind != .dot || options.dotPorts[$0.id] != nil }
        let scoped = upstreams.filter { !$0.domains.isEmpty }
        let global = upstreams.filter { $0.domains.isEmpty }
        var servers: [Any] = scoped.map { server(for: $0, scoped: true, options: options) }
        servers += global.map { server(for: $0, scoped: false, options: options) }
        servers += options.dns as [Any]
        var section: [String: Any] = ["servers": servers, "queryStrategy": "UseIP", "tag": XrayConfiguration.dnsQueryTag]
        if let hosts = hostsMap(profile) { section["hosts"] = hosts }
        return section
    }

    static func address(of upstream: AdvancedDNSUpstream, options: Options) -> String {
        let text = upstream.address.trimmingCharacters(in: .whitespaces)
        switch upstream.kind {
        case .plain: return text
        case .dot: return "tcp+local://127.0.0.1:\(options.dotPorts[upstream.id] ?? 0)"
        case .tcp: return "tcp\(upstream.viaProxy ? "" : "+local")://\(text)"
        case .doq: return "quic+local://\(text)"
        case .doh:
            let full = text.hasPrefix("https://") ? text : "https://\(text)/dns-query"
            return upstream.viaProxy ? full : full.replacingOccurrences(of: "https://", with: "https+local://")
        }
    }

    static func server(for upstream: AdvancedDNSUpstream, scoped: Bool, options: Options) -> Any {
        let address = address(of: upstream, options: options)
        guard scoped else { return address }
        let domains = upstream.domains.map { $0.contains(":") ? $0 : "domain:\($0)" }
        return ["address": address, "domains": domains, "skipFallback": true] as [String: Any]
    }
}
