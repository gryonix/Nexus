import Foundation

struct StoredInstallReport: Codable, Identifiable, Hashable {
    var host: String
    var text: String
    var savedAt = Date()

    var id: String { host }
}

struct DeploymentReportStore {
    private let account: String
    private let keychain: KeychainStore

    init(deploymentID: UUID, keychain: KeychainStore = KeychainStore()) {
        self.account = "install-report-\(deploymentID.uuidString)"
        self.keychain = keychain
    }

    func load() -> [StoredInstallReport] {
        guard let data = try? keychain.data(for: account),
              let reports = try? JSONDecoder().decode([StoredInstallReport].self, from: data) else {
            return []
        }
        return reports
    }

    func save(host: String, text: String) {
        var reports = load().filter { $0.host != host }
        reports.append(StoredInstallReport(host: host, text: text))
        if let data = try? JSONEncoder().encode(reports) {
            try? keychain.set(data, for: account)
        }
    }

    func delete() {
        try? keychain.delete(account)
    }
}

/// Lenient parser of the report text into copyable fields
enum InstallReportParser {
    struct Section: Identifiable, Hashable {
        var title: String
        var fields: [Field] = []
        var id: String { title }
    }

    struct Field: Identifiable, Hashable {
        var label: String
        var value: String
        var id: String { label + value }
    }

    static func sections(from text: String) -> [Section] {
        var result: [Section] = []
        var current: Section?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let indented = line.first?.isWhitespace == true
            if !indented {
                // "Mailcow:      https://…" or "VPN Panel: https://…"
                if let colon = trimmed.range(of: ": ") {
                    if let section = current, !section.fields.isEmpty { result.append(section) }
                    var section = Section(title: String(trimmed[..<colon.lowerBound]))
                    let rest = trimmed[colon.upperBound...].trimmingCharacters(in: .whitespaces)
                    if !rest.isEmpty {
                        section.fields.append(Field(label: "URL", value: rest))
                    }
                    current = section
                } else if trimmed.hasSuffix(":") {
                    if let section = current, !section.fields.isEmpty { result.append(section) }
                    current = Section(title: String(trimmed.dropLast()))
                }
                continue
            }
            guard var section = current, let colon = trimmed.range(of: ": ") else { continue }
            let label = String(trimmed[..<colon.lowerBound])
            let value = trimmed[colon.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, !label.isEmpty else { continue }
            section.fields.append(Field(label: label, value: value))
            current = section
        }
        if let section = current, !section.fields.isEmpty { result.append(section) }
        return result
    }
}
