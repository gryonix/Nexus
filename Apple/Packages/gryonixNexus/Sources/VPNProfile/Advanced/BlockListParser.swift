import Foundation

/// Reads a domain list: plain, hosts-file or adblock lines.

public enum BlockListParser {
    /// Most domains one list may add to the tunnel
    public static let domainLimit = 15_000

    public static func domains(in text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            guard let domain = domain(fromLine: String(raw)), seen.insert(domain).inserted else { continue }
            result.append(domain)
            if result.count >= domainLimit { break }
        }
        return result
    }

    static func domain(fromLine raw: String) -> String? {
        var line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("!") || line.hasPrefix("[") { return nil }
        if let hash = line.firstIndex(of: "#") { line = String(line[..<hash]).trimmingCharacters(in: .whitespaces) }
        if line.hasPrefix("||") {
            line = String(line.dropFirst(2))
            guard let end = line.firstIndex(where: { $0 == "^" || $0 == "$" || $0 == "/" }) else {
                return valid(line)
            }
            let rest = line[end...]
            return rest.hasPrefix("^") && rest.count <= 1 ? valid(String(line[..<end])) : nil
        }
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        if fields.count == 2, ["0.0.0.0", "127.0.0.1", "::"].contains(String(fields[0])) {
            return valid(String(fields[1]))
        }
        return fields.count == 1 ? valid(String(fields[0])) : nil
    }

    private static func valid(_ text: String) -> String? {
        let domain = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard domain.contains("."), domain != "localhost",
              domain.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." || $0 == "_" }),
              !domain.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return domain
    }
}
