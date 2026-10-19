import Foundation

/// The long disk task a server runs in the background
public struct DiskJob: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable { case running, done, failed }

    /// The array change it carries out
    public let action: String
    /// The array it works on
    public let target: String
    public let started: Date?
    public let outcome: Outcome
    /// The newest lines of its log
    public let lastLines: [String]

    public static let unit = "gryonixnexus-disk-job"
    public static let log = "/var/log/gryonixnexus-disk-job.log"
    public static let file = "/var/lib/gryonixnexus-disk-job.sh"
    static let startMarker = "GRYONIXNEXUS_DISK_JOB_START"
    static let doneMarker = "GRYONIXNEXUS_DISK_JOB_DONE"
    static let failedMarker = "GRYONIXNEXUS_DISK_JOB_FAILED"

    /// Probe line: unit state, first log line, last log lines
    static let probeLine = "echo \"diskjob=$(systemctl is-active \(unit) 2>/dev/null)|"
        + "$(head -n 1 \(log) 2>/dev/null)|$(tail -n 3 \(log) 2>/dev/null | tr '\\n' '|')\""

    /// Running, or started within the last three days
    public func isRecent(now: Date = Date()) -> Bool {
        guard outcome != .running, let started else { return true }
        return now.timeIntervalSince(started) < 3 * 24 * 3600
    }

    static func parse(_ field: String) -> DiskJob? {
        let parts = field.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { return nil }
        let start = parts[1].split(separator: " ").map(String.init)
        guard start.count >= 3, start[0] == startMarker else { return nil }
        let tail = parts.dropFirst(2).filter { !$0.isEmpty }
        let last = tail.last ?? ""
        let outcome: Outcome = last.hasPrefix(doneMarker) ? .done
            : last.hasPrefix(failedMarker) ? .failed
            : parts[0] == "active" || parts[0] == "activating" ? .running : .failed
        return DiskJob(action: start[1], target: start[2],
                       started: start.count > 3 ? Double(start[3]).map(Date.init(timeIntervalSince1970:)) : nil,
                       outcome: outcome,
                       lastLines: tail.filter { !$0.hasPrefix(doneMarker) && !$0.hasPrefix(failedMarker) })
    }

    /// Refuses while another disk job runs
    static let busyGuard = [
        "if systemctl is-active -q \(unit); then",
        "  echo \"Another disk job is still running. Wait until it ends.\"",
        "  exit 3",
        "fi",
    ]

    /// Writes the body to a file and starts its unit
    static func launchLines(action: String, target: String, variables: [String], body: [String]) -> [String] {
        [
            "cat > \(file) <<'GNX_JOB'",
            "#!/bin/bash",
            "set -eEuo pipefail",
            "exec >> \(log) 2>&1",
            "trap 'echo \"\(failedMarker) $(date +%s)\"' ERR",
            "echo \"\(startMarker) \(action) \(target) $(date +%s)\"",
        ] + variables + body + [
            "echo \"\(doneMarker) $(date +%s)\"",
            "GNX_JOB",
            ": > \(log)",
            "chmod 644 \(log)",
            "systemctl reset-failed \(unit) >/dev/null 2>&1 || true",
            "systemd-run --quiet --collect --unit=\(unit) /bin/bash \(file)",
        ]
    }
}
