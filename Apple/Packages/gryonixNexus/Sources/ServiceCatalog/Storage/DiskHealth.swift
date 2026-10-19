import Foundation

/// What a disk says about itself through SMART
public struct DiskHealth: Sendable, Hashable {
    public enum Verdict: Sendable, Hashable { case good, watch, failing, unknown }

    public let path: String
    public let passed: Bool?
    public let temperature: Int?
    public let powerOnHours: Int?
    /// NVMe wear, 0–100 and beyond
    public let wornPercent: Int?
    /// Reallocated, pending and uncorrectable sectors, or NVMe media errors
    public let badSectors: Int
    public let criticalWarning: Int

    public var verdict: Verdict {
        if passed == false || criticalWarning != 0 { return .failing }
        if passed == nil && temperature == nil && powerOnHours == nil { return .unknown }
        if badSectors > 0 || (wornPercent ?? 0) >= 90 || (temperature ?? 0) >= 65 { return .watch }
        return .good
    }

    public static let doneMarker = "GRYONIXNEXUS_SMART_DONE"
    static let header = "### "

    /// Installs smartmontools if needed, then reads every disk
    public static func script(paths: [String]) -> String {
        var lines = [
            "#!/bin/bash",
            "set -uo pipefail",
            "if ! command -v smartctl >/dev/null 2>&1; then",
            "  export DEBIAN_FRONTEND=noninteractive",
            "  \(Apt.quiet) install -y -qq --no-install-recommends smartmontools >/dev/null 2>&1 \\",
            "    || { echo \"smartmontools could not be installed\"; exit 3; }",
            "fi",
        ]
        for path in paths {
            let quoted = ShellQuoting.singleQuoted(path)
            lines.append("echo \"\(header)\"\(quoted); smartctl --json=c -H -A -i \(quoted); echo")
        }
        lines.append("echo \(doneMarker)")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func parse(_ output: String) -> [DiskHealth] {
        var result: [DiskHealth] = []
        var path: String?
        for line in output.split(separator: "\n").map(String.init) {
            if line.hasPrefix(header) {
                path = String(line.dropFirst(header.count))
            } else if let current = path, line.hasPrefix("{"),
                      let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result.append(health(path: current, json))
                path = nil
            }
        }
        return result
    }

    private static func health(path: String, _ json: [String: Any]) -> DiskHealth {
        let status = json["smart_status"] as? [String: Any]
        let nvme = json["nvme_smart_health_information_log"] as? [String: Any]
        let attributes = ((json["ata_smart_attributes"] as? [String: Any])?["table"] as? [[String: Any]]) ?? []
        func raw(_ id: Int) -> Int {
            let row = attributes.first { ($0["id"] as? Int) == id }
            return ((row?["raw"] as? [String: Any])?["value"] as? Int) ?? 0
        }
        let ataBad = raw(5) + raw(197) + raw(198)
        return DiskHealth(
            path: path,
            passed: status?["passed"] as? Bool,
            temperature: ((json["temperature"] as? [String: Any])?["current"] as? Int) ?? nvme?["temperature"] as? Int,
            powerOnHours: ((json["power_on_time"] as? [String: Any])?["hours"] as? Int) ?? nvme?["power_on_hours"] as? Int,
            wornPercent: nvme?["percentage_used"] as? Int,
            badSectors: ataBad + ((nvme?["media_errors"] as? Int) ?? 0),
            criticalWarning: (nvme?["critical_warning"] as? Int) ?? 0)
    }
}
