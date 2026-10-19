import Foundation

public struct Domain: Sendable, Hashable, CustomStringConvertible {
    public let name: String

    public init(_ value: String) throws {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard Self.isValid(normalized) else {
            throw ValidationError.invalidDomain(value)
        }
        self.name = normalized
    }

    public init(localOnly value: String) throws {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard Self.isValid(normalized, allowLocalAddress: true) else {
            throw ValidationError.invalidDomain(value)
        }
        self.name = normalized
    }

    public var description: String { name }

    public static func isValid(_ candidate: String) -> Bool {
        guard candidate.count <= 253 else { return false }
        let labels = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard (1...63).contains(label.count) else { return false }
            guard label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return false }
            guard label.first != "-", label.last != "-" else { return false }
        }
        // TLD: letters only, at least 2 characters.
        guard let tld = labels.last, tld.count >= 2, tld.allSatisfy(\.isLetter) else { return false }
        return true
    }

    public static func isValid(_ candidate: String, allowLocalAddress: Bool) -> Bool {
        isValid(candidate) || (allowLocalAddress && (try? NetworkAddress(parsing: candidate)) != nil)
    }
}
