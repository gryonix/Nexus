import Foundation

/// Removes secrets from text before it leaves the device.
public enum Redactor {
    private static let keyWords =
        "password|passwd|passphrase|pwd|secret|token|credential|apikey|(?<![A-Za-z0-9])key(?![A-Za-z])|[_.-]key"

    private static let rules: [(NSRegularExpression, String)] = [
        ("-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|\\z)",
         "[REDACTED PRIVATE KEY]"),
        ("(\\b(?:proxy-)?authorization\\b)(\\s*[:=]\\s*)(?:(?:bearer|basic|token|digest)\\s+)?[^\\s,;\"']+",
         "$1$2[REDACTED]"),
        ("\\bbearer\\s+[A-Za-z0-9._~+/=-]{8,}", "Bearer [REDACTED]"),
        ("\\beyJ[A-Za-z0-9_-]{5,}\\.[A-Za-z0-9_-]{5,}\\.[A-Za-z0-9_-]*", "[REDACTED JWT]"),
        ("(?<=://)[^/\\s:@]+:[^/\\s@]+@", "[REDACTED]@"),
        ("(--?(?:password|passwd|token|secret|api-key|apikey)[ =])\\S+", "$1[REDACTED]"),
        ("([A-Za-z0-9_.-]*(?:\(keyWords))[A-Za-z0-9_.-]*)([\"']?\\s*[:=]\\s*)(\"[^\"]*\"|'[^']*'|[^\\s,;]+)",
         "$1$2[REDACTED]")
    ].map { (try! NSRegularExpression(pattern: $0.0, options: [.caseInsensitive]), $0.1) }

    private static let longToken = try! NSRegularExpression(
        pattern: "(?<![A-Za-z0-9+/_=-])[A-Za-z0-9+/_=-]{32,}(?![A-Za-z0-9+/_=-])")

    public static func redact(_ text: String) -> String {
        var result = text
        for (regex, template) in rules {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return redactLongTokens(result)
    }

    private static func redactLongTokens(_ text: String) -> String {
        let ns = text as NSString
        var result = text
        let matches = longToken.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            let token = ns.substring(with: match.range)
            guard looksSecret(token), let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: "[REDACTED]")
        }
        return result
    }

    private static func looksSecret(_ token: String) -> Bool {
        token.contains(where: \.isNumber) && token.contains(where: \.isLetter)
    }
}
