import Foundation

/// Hysteria2 and NaiveProxy share links.

extension SubscriptionImport {
    static func hysteria2(_ link: String) -> Result<AdvancedServer, AdvancedImportReport.Skipped> {
        guard let parts = ProxyLinkParts(link), !parts.host.isEmpty else { return skip(nil, link, "the link is incomplete") }
        let authority = parts.body.split(separator: "@").last.map(String.init) ?? parts.body
        if parts.port == nil, authority.contains(":"), !authority.hasSuffix("]") {
            return skip(parts, link, "port ranges are not supported")
        }
        var fields = ["password": parts.userInfo.removingPercentEncoding ?? parts.userInfo]
        if let name = parts.query["sni"] { fields["sni"] = name }
        if parts.query["insecure"] == "1" { fields["insecure"] = "1" }
        if let obfs = parts.query["obfs"] { fields["obfs"] = obfs }
        if let secret = parts.query["obfs-password"] { fields["obfsPassword"] = secret }
        return .success(AdvancedServer(kind: .hysteria2, name: parts.fragment, host: parts.host,
                                       port: parts.port ?? 443, fields: fields))
    }

    static func naive(_ link: String) -> Result<AdvancedServer, AdvancedImportReport.Skipped> {
        guard let parts = ProxyLinkParts(link), !parts.host.isEmpty else { return skip(nil, link, "the link is incomplete") }
        var fields: [String: String] = [:]
        let login = parts.userInfo.removingPercentEncoding ?? parts.userInfo
        if let colon = login.firstIndex(of: ":") {
            fields["user"] = String(login[..<colon])
            fields["password"] = String(login[login.index(after: colon)...])
        } else if !login.isEmpty {
            fields["user"] = login
        }
        if let name = parts.query["sni"] { fields["sni"] = name }
        return .success(AdvancedServer(kind: .naive, name: parts.fragment, host: parts.host,
                                       port: parts.port ?? 443, fields: fields))
    }
}
