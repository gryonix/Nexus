import Foundation

public struct ServerAccessOptions: Codable, Hashable, Sendable {
    public var agentForwarding: Bool

    /// Where the file browser opens on this server
    public var sftpDirectory: String?

    public var bastion: BastionHop?

    public var fallback: FallbackAddress?

    public var proxyID: UUID?

    public init(agentForwarding: Bool = false,
                sftpDirectory: String? = nil,
                bastion: BastionHop? = nil,
                fallback: FallbackAddress? = nil,
                proxyID: UUID? = nil) {
        self.agentForwarding = agentForwarding
        self.sftpDirectory = sftpDirectory
        self.bastion = bastion
        self.fallback = fallback
        self.proxyID = proxyID
    }

    /// Nothing chosen — what every server has until somebody opens Advanced
    public static let none = ServerAccessOptions()

    /// Whether anything here is worth storing at all
    public var isEmpty: Bool { self == .none }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agentForwarding = try container.decodeIfPresent(Bool.self, forKey: .agentForwarding) ?? false
        sftpDirectory = try container.decodeIfPresent(String.self, forKey: .sftpDirectory)
        bastion = try container.decodeIfPresent(BastionHop.self, forKey: .bastion)
        fallback = try container.decodeIfPresent(FallbackAddress.self, forKey: .fallback)
        proxyID = try container.decodeIfPresent(UUID.self, forKey: .proxyID)
    }
}

/// The machine a connection is made THROUGH
public struct BastionHop: Codable, Hashable, Sendable {
    public var fleetServerID: UUID?
    /// The typed-in endpoint, when it is not
    public var manual: HostEndpoint?

    public init(fleetServerID: UUID? = nil, manual: HostEndpoint? = nil) {
        self.fleetServerID = fleetServerID
        self.manual = manual
    }

    /// A hop through a server this app manages
    public static func fleetServer(_ id: UUID) -> BastionHop {
        BastionHop(fleetServerID: id)
    }

    /// A hop through a host it does not
    public static func manual(_ endpoint: HostEndpoint) -> BastionHop {
        BastionHop(manual: endpoint)
    }

    public var isUsable: Bool {
        fleetServerID != nil || (manual?.isValid ?? false)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fleetServerID = try container.decodeIfPresent(UUID.self, forKey: .fleetServerID)
        manual = try container.decodeIfPresent(HostEndpoint.self, forKey: .manual)
    }
}

public struct FallbackAddress: Codable, Hashable, Sendable {
    /// The address to try
    public var host: String

    /// The port to try
    public var port: Int?

    /// The jump host this attempt goes through, if any
    public var bastion: BastionHop?

    public init(host: String = "", port: Int? = nil, bastion: BastionHop? = nil) {
        self.host = host
        self.port = port
        self.bastion = bastion
    }

    /// Whether this says anything at all
    public var isUsable: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty || bastion != nil
    }

    public func endpoint(primary: HostEndpoint) -> HostEndpoint {
        let typed = host.trimmingCharacters(in: .whitespaces)
        return HostEndpoint(host: typed.isEmpty ? primary.host : typed,
                            port: port ?? primary.port,
                            user: primary.user)
    }
}

public struct ProxyProfile: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case socks5
        case httpConnect
    }

    public let id: UUID
    public var name: String
    public var kind: Kind
    public var host: String
    public var port: Int
    public var username: String

    public init(id: UUID = UUID(), name: String = "", kind: Kind = .socks5,
                host: String = "", port: Int = 1080, username: String = "") {
        self.id = id
        self.name = name
        self.kind = kind
        self.host = host
        self.port = port
        self.username = username
    }

    /// Enough to dial
    public var isUsable: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && (1...65535).contains(port)
    }

    /// What it is called when nobody named it
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "\(host):\(port)" : trimmed
    }
}
