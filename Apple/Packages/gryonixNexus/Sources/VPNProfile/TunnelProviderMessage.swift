import Foundation

public enum VPNTunnelKeys {
    public static let config = "wgQuickConfig"
    public static let datapath = "datapath"
    public static let configAccount = "configAccount"
    public static let profileID = "profileID"
    public static let endpointPinHost = "endpointPinHost"
    public static let endpointPinAddress = "endpointPinAddress"

    public static let wireGuardKit = "wireGuardKit"
    public static let xray = "xray"
    public static let openVPN = "openVPN"
}

public enum TunnelProviderMessage {
    /// What the app sends
    public static let statisticsRequest = Data("statistics".utf8)

    /// What the provider answers with, as JSON
    public struct Statistics: Codable, Sendable, Equatable {
        public var received: Int64
        public var sent: Int64
        /// WireGuard only: when the last handshake completed
        public var lastHandshake: Date?

        public init(received: Int64, sent: Int64, lastHandshake: Date? = nil) {
            self.received = received
            self.sent = sent
            self.lastHandshake = lastHandshake
        }

        public func encoded() -> Data? { try? JSONEncoder().encode(self) }

        public static func decoded(_ data: Data?) -> Statistics? {
            guard let data else { return nil }
            return try? JSONDecoder().decode(Statistics.self, from: data)
        }
    }
}
