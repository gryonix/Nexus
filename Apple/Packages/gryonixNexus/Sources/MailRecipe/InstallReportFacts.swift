import Foundation
import ServiceCatalog

/// Facts read back out of an install report
public enum InstallReportFacts {
    /// The deployment's domain, as the report states it
    public static func domain(inReport report: String) -> String? {
        for language in AppLanguage.allCases {
            let label = L10nScripts.domainLabel(language).trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            for line in report.split(separator: "\n", omittingEmptySubsequences: true) {
                let text = line.trimmingCharacters(in: .whitespaces)
                guard text.hasPrefix(label) else { continue }
                let value = text.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
                guard let candidate = sanitised(value) else { continue }
                return candidate
            }
        }
        return nil
    }

    /// What may be taken as a domain
    private static func sanitised(_ value: String) -> String? {
        let candidate = value.lowercased()
        guard candidate.contains("."),
              !candidate.contains(" "),
              !candidate.contains("/"),
              !candidate.contains(":"),
              !candidate.hasPrefix("."),
              !candidate.hasSuffix("."),
              candidate.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" })
        else { return nil }
        return candidate
    }
}
