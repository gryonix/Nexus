import Foundation

public struct TunnelStopRecord {
    public static let fileName = "tunnel-stop-reason"
    public static let detailFileName = "tunnel-stop-detail"
    public static let heartbeatFileName = "tunnel-heartbeat"
    public static let crashFileName = "tunnel-go-crash"

    let url: URL?

    public init(groupIdentifier: String = AppGroup.identifier) {
        url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent(Self.fileName)
    }

    init(url: URL?) {
        self.url = url
    }

    private var detailURL: URL? {
        url?.deletingLastPathComponent().appendingPathComponent(Self.detailFileName)
    }

    private var heartbeatURL: URL? {
        url?.deletingLastPathComponent().appendingPathComponent(Self.heartbeatFileName)
    }

    /// Where the Go runtime writes a fatal panic
    public var crashURL: URL? {
        url?.deletingLastPathComponent().appendingPathComponent(Self.crashFileName)
    }

    /// The tunnel's latest sign of life
    public func heartbeat(_ line: String) {
        guard let heartbeatURL else { return }
        try? Data(line.utf8).write(to: heartbeatURL, options: .atomic)
    }

    public func clear() {
        for file in [url, detailURL, heartbeatURL, crashURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Adds one line about why the tunnel stopped
    public func note(_ line: String) {
        guard let detailURL else { return }
        let kept = (try? String(contentsOf: detailURL, encoding: .utf8)) ?? ""
        try? Data((kept.isEmpty ? line : kept + "\n" + line).utf8).write(to: detailURL, options: .atomic)
    }

    /// The tunnel's own notes and the system's stop reason
    public func explanation() -> String? {
        let notes = detailURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        var lines = notes.split(separator: "\n").map(String.init)
        if let reason = read() {
            lines.append("Stop reason: \(Self.reasonName(reason)) (\(reason))")
        } else if let alive = heartbeatURL.flatMap({ try? String(contentsOf: $0, encoding: .utf8) }) {
            lines.append("Ended abruptly; last alive \(alive)")
        }
        let crash = crashURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        lines += crash.split(separator: "\n").prefix(Self.crashLines).map(String.init)
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// The panic and its first frames
    static let crashLines = 12

    /// `NEProviderStopReason` by its raw value
    public static func reasonName(_ raw: Int) -> String {
        let names = ["none", "userInitiated", "providerFailed", "noNetworkAvailable",
                     "unrecoverableNetworkChange", "providerDisabled", "authenticationCanceled",
                     "configurationFailed", "idleTimeout", "configurationDisabled", "configurationRemoved",
                     "superceded", "userLogout", "userSwitch", "connectionFailed", "sleep", "appUpdate",
                     "internalError"]
        return names.indices.contains(raw) ? names[raw] : "unknown"
    }

    public func write(reason: Int) {
        guard let url else { return }
        try? Data(String(reason).utf8).write(to: url, options: .atomic)
    }

    /// `nil` when the tunnel ended without its stop handler
    public func read() -> Int? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return Int(String(decoding: data, as: UTF8.self))
    }
}
