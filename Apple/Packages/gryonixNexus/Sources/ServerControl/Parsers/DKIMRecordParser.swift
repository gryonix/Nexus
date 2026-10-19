import Foundation

public struct DKIMRecord: Sendable, Hashable {
    /// Record name, e.g
    public let name: String
    public let value: String
    public var type: String { "TXT" }

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// Extracts DKIM records from an install report
public enum DKIMRecordParser: Sendable {
    static let marker = "GRYONIXNEXUS_DKIM"

    public static func parse(_ report: String) -> [DKIMRecord] {
        report.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(marker + " ") else { return nil }
            let rest = trimmed.dropFirst(marker.count + 1)
            guard let separator = rest.firstIndex(of: " ") else { return nil }
            let name = String(rest[rest.startIndex..<separator])
            let value = String(rest[rest.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty else { return nil }
            return DKIMRecord(name: name, value: value)
        }
    }

    public static func stripMarkers(from report: String) -> String {
        report.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(marker + " ") }
            .joined(separator: "\n")
    }
}
