import Foundation

public enum NetworkAddress: Sendable, Hashable, CustomStringConvertible {
    case ipv4(String)
    case ipv6(String)
    case hostname(String)

    /// Parses a string, throwing `ValidationError.invalidAddress` on an invalid format
    public init(parsing string: String) throws {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isValidIPv4(trimmed) {
            self = .ipv4(trimmed)
        } else if Self.isValidIPv6(trimmed) {
            self = .ipv6(trimmed.lowercased())
        } else {
            throw ValidationError.invalidAddress(string)
        }
    }

    public init(localOnly string: String) throws {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let literal = try? NetworkAddress(parsing: trimmed) {
            self = literal
        } else if Domain.isValid(trimmed.lowercased()) {
            self = .hostname(trimmed.lowercased())
        } else {
            throw ValidationError.invalidAddress(string)
        }
    }

    public var value: String {
        switch self {
        case .ipv4(let v), .ipv6(let v), .hostname(let v): return v
        }
    }

    public var isIPv4: Bool {
        if case .ipv4 = self { return true }
        return false
    }

    public var description: String { value }

    public static func isValidIPv4(_ candidate: String) -> Bool {
        let octets = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { octet in
            guard !octet.isEmpty, octet.count <= 3, octet.allSatisfy(\.isNumber),
                  let number = Int(octet) else { return false }
            // Disallow leading zeros ("01"), but allow a lone "0".
            guard octet.count == 1 || octet.first != "0" else { return false }
            return number <= 255
        }
    }

    public static func isValidIPv6(_ candidate: String) -> Bool {
        // Deliberately a loose check: hex groups and colons.
        guard candidate.contains(":"), candidate.count >= 2, candidate.count <= 45 else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF:")
        return candidate.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
