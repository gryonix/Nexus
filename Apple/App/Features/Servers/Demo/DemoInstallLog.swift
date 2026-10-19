import Foundation
import MailRecipe
import ServerControl

/// The log an emulated installation writes
enum DemoInstallLog {
    struct Line {
        let text: String
        var delay: Int = 220
    }

    /// Step markers and stage titles, in order
    static func lines(script: String, services: [String], domain: String) -> [Line] {
        let steps = stages(in: script)
        var lines: [Line] = [Line(text: "==> Reading the machine", delay: 500)]
        for (index, stage) in steps.enumerated() {
            lines.append(Line(text: "\(SetupMarkers.step) \(index + 1)/\(steps.count + 1)",
                              delay: 60))
            lines.append(Line(text: "==> \(stage)", delay: 520))
            lines.append(Line(text: "  ok", delay: 240))
        }
        lines.append(Line(text: "\(SetupMarkers.step) \(steps.count + 1)/\(steps.count + 1)",
                          delay: 60))
        lines.append(contentsOf: report(services: services, domain: domain))
        lines.append(Line(text: SetupMarkers.done, delay: 200))
        lines.append(Line(text: "\(SetupProgressParser.exitMarker)0", delay: 60))
        return lines
    }

    /// What the script's own log calls say
    static func stages(in script: String) -> [String] {
        var found: [String] = []
        for raw in script.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("log \""), line.hasSuffix("\"") else { continue }
            let text = String(line.dropFirst(5).dropLast())
            guard !text.isEmpty, !text.contains("$"), !found.contains(text) else { continue }
            found.append(text)
        }
        return found.isEmpty ? fallbackStages : found
    }

    private static let fallbackStages = [
        "Reading the distribution",
        "Installing packages",
        "Firewall (nftables, default-deny)",
        "Web server and certificates",
        "Services"
    ]

    private static func report(services: [String], domain: String) -> [Line] {
        var lines = [Line(text: SetupMarkers.reportBegin, delay: 300)]
        lines.append(Line(text: "GRYONIXNEXUS_REPORT", delay: 40))
        lines.append(Line(text: "Domain: \(domain)", delay: 40))
        lines.append(Line(text: "Services: \(services.joined(separator: ", "))", delay: 40))
        lines.append(Line(text: "Admin user: admin@\(domain)", delay: 40))
        lines.append(Line(text: "Nothing here touched a real machine — this server is emulated.",
                          delay: 40))
        lines.append(Line(text: SetupMarkers.reportEnd, delay: 60))
        return lines
    }
}
