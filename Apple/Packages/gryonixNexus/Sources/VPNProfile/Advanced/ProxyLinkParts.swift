import Foundation

/// A proxy link cut into its parts without URL validation.
struct ProxyLinkParts {
    let scheme: String
    let userInfo: String
    let host: String
    let port: Int?
    let query: [String: String]
    let fragment: String
    /// Everything between the scheme and the query, for base64 forms
    let body: String

    init?(_ text: String) {
        guard let schemeEnd = text.range(of: "://") else { return nil }
        scheme = text[..<schemeEnd.lowerBound].lowercased()
        var rest = String(text[schemeEnd.upperBound...])
        if let hash = rest.firstIndex(of: "#") {
            fragment = String(rest[rest.index(after: hash)...]).removingPercentEncoding
                ?? String(rest[rest.index(after: hash)...])
            rest = String(rest[..<hash])
        } else {
            fragment = ""
        }
        var queryText = ""
        if let mark = rest.firstIndex(of: "?") {
            queryText = String(rest[rest.index(after: mark)...])
            rest = String(rest[..<mark])
        }
        query = Self.parse(query: queryText)
        body = rest.hasSuffix("/") ? String(rest.dropLast()) : rest
        var authority = body
        if let at = authority.lastIndex(of: "@") {
            userInfo = String(authority[..<at])
            authority = String(authority[authority.index(after: at)...])
        } else {
            userInfo = ""
        }
        (host, port) = Self.split(authority: authority)
    }

    private static func split(authority: String) -> (String, Int?) {
        if authority.hasPrefix("["), let close = authority.firstIndex(of: "]") {
            let host = String(authority[authority.index(after: authority.startIndex)..<close])
            let tail = authority[authority.index(after: close)...]
            return (host, tail.hasPrefix(":") ? Int(tail.dropFirst()) : nil)
        }
        guard let colon = authority.lastIndex(of: ":") else { return (authority, nil) }
        return (String(authority[..<colon]), Int(authority[authority.index(after: colon)...]))
    }

    private static func parse(query text: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            if !value.isEmpty { result[String(parts[0])] = value }
        }
        return result
    }
}

enum LinkBase64 {
    static func decode(_ text: String) -> String? {
        var normal = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rest = normal.count % 4
        if rest > 0 { normal += String(repeating: "=", count: 4 - rest) }
        guard let data = Data(base64Encoded: normal) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
