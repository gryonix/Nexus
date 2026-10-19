import Foundation
import gryonixNexusCore

public enum DKIMExport {
    private static let ttl = 3600

    public struct Bundle {
        public let copyText: String
        public let zoneFile: Artifact
        public let csvFile: Artifact
    }

    public static func bundle(from records: [DKIMRecord],
                              zoneSummary: String,
                              csvSummary: String) -> Bundle? {
        guard !records.isEmpty else { return nil }
        return Bundle(copyText: recordsText(records),
                      zoneFile: zoneArtifact(records, summary: zoneSummary),
                      csvFile: csvArtifact(records, summary: csvSummary))
    }

    public static func recordsText(_ records: [DKIMRecord]) -> String {
        records.map { "TXT\t\($0.name)\t\($0.value)" }.joined(separator: "\n")
    }

    private static func zoneArtifact(_ records: [DKIMRecord], summary: String) -> Artifact {
        var lines = [
            "; BIND zone file (DKIM) - import this at your DNS provider.",
            "$TTL \(ttl)"
        ]
        lines += records.map { "\($0.name).    \(ttl)    IN TXT    \(bindTXTRData($0.value))" }
        return Artifact(fileName: "dkim-dns-zone.txt", kind: .dnsRecord,
                        contents: lines.joined(separator: "\n") + "\n",
                        summary: summary)
    }

    private static func csvArtifact(_ records: [DKIMRecord], summary: String) -> Artifact {
        var lines = ["type,name,value,ttl,priority"]
        lines += records.map { "TXT,\(csvField($0.name)),\(csvField($0.value)),\(ttl)," }
        return Artifact(fileName: "dkim-dns-records.csv", kind: .dnsRecord,
                        contents: lines.joined(separator: "\n") + "\n",
                        summary: summary)
    }

    /// RFC 4180 quoting, matching the DNS CSV export
    private static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
