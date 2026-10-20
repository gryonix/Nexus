import Foundation

/// The session card the tunnel moves through the relay
public struct TunnelActivityTicket: Codable, Equatable, Sendable {
    public static let fileName = "tunnel-activity-ticket"

    public var token: String
    public var relayURL: String
    /// Session start, seconds since the reference date
    public var since: Double

    public init(token: String, relayURL: String, since: Date) {
        self.token = token
        self.relayURL = relayURL
        self.since = since.timeIntervalSinceReferenceDate
    }

    public static func url(groupIdentifier: String = AppGroup.identifier) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent(fileName)
    }

    public static func load(from url: URL? = url()) -> TunnelActivityTicket? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TunnelActivityTicket.self, from: data)
    }

    public func save(to url: URL? = Self.url()) {
        guard let url, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public static func clear(at url: URL? = url()) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
