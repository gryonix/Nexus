import Foundation

/// Why the agent refused, as a stable id with values
public struct AgentRefusal: Sendable, Equatable {
    public let reason: String
    public let args: [String]
    public let message: String

    public init(reason: String, args: [String], message: String) {
        self.reason = reason
        self.args = args
        self.message = message
    }
}

/// Recent refusals, found again by the text shown
public final class AgentRefusals: @unchecked Sendable {
    public static let shared = AgentRefusals()
    private static let kept = 32

    private let lock = NSLock()
    private var recent: [AgentRefusal] = []

    public init() {}

    public func remember(_ refusal: AgentRefusal) {
        guard !refusal.reason.isEmpty, !refusal.message.isEmpty else { return }
        lock.withLock {
            recent.removeAll { $0.message == refusal.message }
            recent.append(refusal)
            if recent.count > Self.kept { recent.removeFirst(recent.count - Self.kept) }
        }
    }

    /// The newest refusal whose words the text carries
    public func find(in text: String) -> AgentRefusal? {
        lock.withLock { recent.last { text.contains($0.message) } }
    }

    /// Reads reason and args from an error body
    static func note(_ object: [String: Any]) {
        guard let reason = object["reason"] as? String else { return }
        shared.remember(AgentRefusal(reason: reason, args: object["args"] as? [String] ?? [],
                                     message: object["message"] as? String ?? ""))
    }
}
