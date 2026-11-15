import Foundation

public enum AIBudgetState: Equatable, Sendable {
    case unlimited, ok, nearLimit, reached
}

/// Tokens used per calendar month, kept on this device.
public struct AITokenLedger: Codable, Equatable, Sendable {
    public var months: [String: Int] = [:]

    public init() {}

    public static func monthKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    public mutating func add(tokens: Int, at date: Date) {
        months[Self.monthKey(date), default: 0] += max(0, tokens)
    }

    public func used(at date: Date) -> Int { months[Self.monthKey(date)] ?? 0 }

    public static func state(used: Int, limit: Int) -> AIBudgetState {
        guard limit > 0 else { return .unlimited }
        if used >= limit { return .reached }
        return used * 10 >= limit * 8 ? .nearLimit : .ok
    }
}
