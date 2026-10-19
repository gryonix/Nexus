import Foundation

/// How long a card waits before calling a server unreachable
enum ConnectionSettings {
    static let silenceKey = "connection.silence"
    static let defaultSilence = 15
    static let silences = [15, 30, 60, 120, 300]
    static let silenceRange = 5...3600

    static let reconnectKey = "connection.reconnect"
    static let defaultReconnect = 90
    /// Zero turns reconnecting off
    static let reconnects = [60, 90, 180, 300, 600, 0]
    static let reconnectRange = 30...86400

    static func silence(_ defaults: UserDefaults = .standard) -> TimeInterval {
        TimeInterval(stored(silenceKey, defaults) { silenceRange.contains($0) } ?? defaultSilence)
    }

    /// nil when reconnecting is off
    static func reconnect(_ defaults: UserDefaults = .standard) -> TimeInterval? {
        let seconds = stored(reconnectKey, defaults) { $0 == 0 || reconnectRange.contains($0) }
            ?? defaultReconnect
        guard seconds > 0 else { return nil }
        return max(TimeInterval(seconds), silence(defaults) * 2)
    }

    /// Wait for the very first answer
    static func firstAnswerGrace(_ defaults: UserDefaults = .standard) -> TimeInterval {
        max(45, silence(defaults))
    }

    /// Minutes and seconds, e.g. 1 minute 30 seconds
    static func title(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.hour, .minute, .second]
        return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds)"
    }

    private static func stored(_ key: String, _ defaults: UserDefaults,
                               allowed: (Int) -> Bool) -> Int? {
        guard defaults.object(forKey: key) != nil else { return nil }
        let value = defaults.integer(forKey: key)
        return allowed(value) ? value : nil
    }
}
