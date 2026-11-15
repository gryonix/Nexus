import Foundation

public enum AgentVersion {
    /// Numeric components, ignoring anything that is not a number
    static func components(_ version: String) -> [Int]? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first?.isNumber == true else { return nil }
        let parts = trimmed
            .split(whereSeparator: { ".-+".contains($0) })
            .map { $0.prefix { $0.isNumber } }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.compactMap { Int($0) }
    }

    /// Is `candidate` a LATER version than `installed`?
    public static func isNewer(_ candidate: String, than installed: String, now: Date = Date()) -> Bool {
        guard let a = components(candidate).map({ orderingKey($0, now: now) }),
              let b = components(installed).map({ orderingKey($0, now: now) }) else { return false }
        for index in 0 ..< max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    /// Old November counters sort below dated 26.11.D versions
    static func orderingKey(_ parts: [Int], now: Date) -> [Int] {
        guard parts.count >= 3, parts[0] == 26, parts[1] == 11 else { return parts }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        let dayInFuture = (today.year ?? 0, today.month ?? 0, today.day ?? 0) < (2026, 11, parts[2])
        return dayInFuture ? [26, 11, 0] + parts[2...] : parts
    }
}
