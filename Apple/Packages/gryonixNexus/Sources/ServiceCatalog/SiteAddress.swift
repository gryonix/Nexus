import Foundation

/// A web address a person types for a service
public enum SiteAddress {
    /// A host name Caddy and DNS both accept
    public static func isValid(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.count <= 253, labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { ($0.isASCII && $0.isLetter) || ($0.isASCII && $0.isNumber) || $0 == "-" }
        }
    }

    /// The typed address, trimmed and lowercased
    public static func normalized(_ typed: String) -> String {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
