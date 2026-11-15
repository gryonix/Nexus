import Foundation

/// A proxy link stored with its DNS
public enum ProxyTunnelText {
    private static let prefix = "dns="
    private static let advancedPrefix = "advanced="

    public static let fallbackDNS = ["1.1.1.1", "8.8.8.8"]

    public static func compose(link: String, dns: [String], advanced: String? = nil) -> String {
        var text = dns.isEmpty ? link : link + "\n" + prefix + dns.joined(separator: ",")
        if let advanced { text += "\n" + advancedPrefix + advanced }
        return text
    }

    /// The advanced profile JSON kept beside the link, if any
    public static func advancedJSON(in text: String) -> String? {
        text.split(whereSeparator: \.isNewline).first { $0.hasPrefix(advancedPrefix) }
            .map { String($0.dropFirst(advancedPrefix.count)) }
    }

    /// The link alone, and the DNS kept beside it
    public static func split(_ text: String) -> (link: String, dns: [String]) {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let link = lines.first { !$0.hasPrefix(prefix) && !$0.hasPrefix(advancedPrefix) } ?? ""
        let dns = lines.first { $0.hasPrefix(prefix) }
            .map { $0.dropFirst(prefix.count).split(separator: ",").map(String.init) } ?? []
        return (link, dns.isEmpty ? fallbackDNS : dns)
    }

    /// IPv4 resolvers when any: proxy servers may lack IPv6
    public static func reachableDNS(_ dns: [String]) -> [String] {
        let ipv4 = dns.filter { !$0.contains(":") }
        return ipv4.isEmpty ? dns : ipv4
    }
}
