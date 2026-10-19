import Foundation

/// Disk and internet speed of a server
public enum SpeedTest {
    public static let doneMarker = "GRYONIXNEXUS_SPEED_DONE"
    /// On the system disk and writable without root
    public static let systemDirectory = "/var/tmp"
    static let diskMegabytes = 256
    static let downloadBytes = 50_000_000
    static let uploadBytes = 25_000_000
    static let endpoint = "https://speed.cloudflare.com"

    public struct DiskResult: Sendable, Hashable, Codable {
        public let writeBytesPerSecond: Double
        public let readBytesPerSecond: Double
        /// Direct I/O refused; numbers include the page cache
        public let cached: Bool
    }

    public struct InternetResult: Sendable, Hashable, Codable {
        public let downloadBitsPerSecond: Double
        public let uploadBitsPerSecond: Double
        public let latencySeconds: Double
    }

    /// Writes and reads a temporary file in `directory`
    public static func diskScript(directory: String) -> String {
        let dd = "LC_ALL=C dd bs=1M"
        return ([
            "#!/bin/bash",
            "set -uo pipefail",
            "F=\(ShellQuoting.singleQuoted(directory))/.gryonixnexus-speedtest.$$",
            "trap 'rm -f \"$F\"' EXIT",
            "if w=$(\(dd) if=/dev/zero of=\"$F\" count=\(diskMegabytes) oflag=direct conv=fdatasync 2>&1); then",
            "  r=$(\(dd) if=\"$F\" of=/dev/null iflag=direct 2>&1); mode=direct",
            "else",
            "  w=$(\(dd) if=/dev/zero of=\"$F\" count=\(diskMegabytes) conv=fdatasync 2>&1)",
            "  r=$(\(dd) if=\"$F\" of=/dev/null 2>&1); mode=cached",
            "fi",
            "echo \"write $(printf '%s' \"$w\" | tail -n 1)\"",
            "echo \"read $(printf '%s' \"$r\" | tail -n 1)\"",
            "echo \"mode $mode\"",
            "echo \(doneMarker)",
        ]).joined(separator: "\n") + "\n"
    }

    /// Downloads and uploads against a public speed endpoint
    public static let internetScript = ([
        "#!/bin/bash",
        "set -uo pipefail",
        "command -v curl >/dev/null 2>&1 || { echo nocurl; exit 0; }",
        "echo \"down $(curl -s -o /dev/null -w '%{speed_download} %{http_code}' --max-time 20 '\(endpoint)/__down?bytes=\(downloadBytes)'; true)\"",
        "echo \"up $(head -c \(uploadBytes) /dev/zero | curl -s -o /dev/null -w '%{speed_upload} %{http_code}' --max-time 20 --data-binary @- '\(endpoint)/__up'; true)\"",
        "echo \"ping $(curl -s -o /dev/null -w '%{time_connect}' --max-time 10 '\(endpoint)/__down?bytes=0'; true)\"",
        "echo \(doneMarker)",
    ]).joined(separator: "\n") + "\n"

    public static func parseDisk(_ output: String) -> DiskResult? {
        let fields = keyed(output)
        guard let write = fields["write"].flatMap(ddRate), let read = fields["read"].flatMap(ddRate)
        else { return nil }
        return DiskResult(writeBytesPerSecond: write, readBytesPerSecond: read,
                          cached: fields["mode"] == "cached")
    }

    public static func parseInternet(_ output: String) -> InternetResult? {
        let fields = keyed(output)
        let down = fields["down"].flatMap(answered) ?? 0
        let up = fields["up"].flatMap(answered) ?? 0
        guard down > 0 || up > 0 else { return nil }
        return InternetResult(downloadBitsPerSecond: down * 8, uploadBitsPerSecond: up * 8,
                              latencySeconds: fields["ping"].flatMap(Double.init) ?? 0)
    }

    /// Bytes per second from "rate code", only for HTTP 200
    static func answered(_ field: String) -> Double? {
        let parts = field.split(separator: " ")
        guard parts.count == 2, parts[1] == "200" else { return nil }
        return Double(parts[0])
    }

    /// Bytes per second from dd's summary line
    static func ddRate(_ line: String) -> Double? {
        let words = line.split(separator: " ")
        guard let bytes = words.first.flatMap({ Double($0) }),
              let copied = words.firstIndex(where: { $0.hasPrefix("copied") }),
              words.index(after: copied) < words.endIndex,
              let seconds = Double(words[words.index(after: copied)]), seconds > 0 else { return nil }
        return bytes / seconds
    }

    private static func keyed(_ output: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            fields[String(parts[0])] = String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
        return fields
    }
}
