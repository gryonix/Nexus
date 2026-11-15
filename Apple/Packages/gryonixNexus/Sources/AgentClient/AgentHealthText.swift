import Foundation

/// Plain text for the agent's own memory, uptime and add-ons.
public enum AgentHealthText {
    public static func bytes(_ count: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: count), countStyle: .memory)
    }

    public static func startedAt(_ milliseconds: Int64) -> Date? {
        milliseconds > 0 ? Date(timeIntervalSince1970: Double(milliseconds) / 1000) : nil
    }

    public static func runningSince(_ milliseconds: Int64, now: Date = Date(),
                                    locale: Locale = .current) -> String? {
        guard let date = startedAt(milliseconds) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
