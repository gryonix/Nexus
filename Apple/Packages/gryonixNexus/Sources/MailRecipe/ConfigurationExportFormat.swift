import Foundation
import gryonixNexusCore

public enum ConfigurationExportFormat {
    // MARK: - DNS

    public static func recordsText(_ records: [DNSRecord], in domain: String) -> String {
        records.map { record in
            let priority = record.priority.map { " \($0)" } ?? ""
            return "\(record.type.rawValue.uppercased())\t\(nameField(for: record.name, in: domain))\t\(record.value)\(priority)"
        }.joined(separator: "\n")
    }

    public static func nameField(for name: String, in domain: String) -> String {
        if name == domain { return "@" }
        if name.hasSuffix(".\(domain)") { return String(name.dropLast(domain.count + 1)) }
        return name
    }

    // MARK: - Ports

    /// One `PORT/PROTO purpose` line per requirement — what "Copy" hands over
    public static func portsText(_ requirements: [OpenPortRequirement]) -> String {
        requirements.map { "\($0.port)/\($0.proto.rawValue)\t\($0.purpose)" }
            .joined(separator: "\n")
    }

    /// A human-readable list for a provider's firewall form
    public static func portsTextArtifact(_ requirements: [OpenPortRequirement],
                                         summary: String) -> Artifact {
        var lines = [
            "# Inbound ports to allow on the server (hoster firewall / security group).",
            "# Port/Proto    Purpose"
        ]
        lines += requirements.map { "\($0.port)/\($0.proto.rawValue)    \($0.purpose)" }
        return Artifact(fileName: "gryonixnexus-ports.txt", kind: .firewallRules,
                        contents: lines.joined(separator: "\n") + "\n",
                        summary: summary)
    }

    public static func portsCSVArtifact(_ requirements: [OpenPortRequirement],
                                        summary: String) -> Artifact {
        var lines = ["port,protocol,purpose"]
        lines += requirements.map { "\($0.port),\($0.proto.rawValue),\(csvField($0.purpose))" }
        return Artifact(fileName: "gryonixnexus-ports.csv", kind: .firewallRules,
                        contents: lines.joined(separator: "\n") + "\n",
                        summary: summary)
    }

    public static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
