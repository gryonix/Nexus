import Foundation
import ServiceCatalog

public struct TunnelProfile: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let serverID: UUID
    public var serverName: String
    public let protocolID: ServiceID
    public let deviceID: String
    public var deviceName: String

    /// `host:port` the tunnel dials
    public var endpoint: String
    /// The interface's own addresses, e.g
    public var addresses: [String]
    public var dns: [String]
    /// `["0.0.0.0/0", "::/0"]` for a full tunnel
    public var allowedIPs: [String]
    public var mtu: Int?
    public var isObfuscated: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(),
                serverID: UUID,
                serverName: String,
                protocolID: ServiceID,
                deviceID: String,
                deviceName: String,
                endpoint: String,
                addresses: [String],
                dns: [String] = [],
                allowedIPs: [String] = [],
                mtu: Int? = nil,
                isObfuscated: Bool = false,
                createdAt: Date = Date()) {
        self.id = id
        self.serverID = serverID
        self.serverName = serverName
        self.protocolID = protocolID
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.endpoint = endpoint
        self.addresses = addresses
        self.dns = dns
        self.allowedIPs = allowedIPs
        self.mtu = mtu
        self.isObfuscated = isObfuscated
        self.createdAt = createdAt
    }

    public var secretAccount: String {
        "tunnel.\(serverID.uuidString).\(protocolID.rawValue).\(deviceID)"
    }

    public var displayName: String { deviceName }

    public var subtitle: String {
        "\(serverName) · \(protocolID.displayName)"
    }

    /// Name in system VPN settings: server, then protocol
    public var systemName: String {
        let server = serverName.isEmpty ? Self.host(of: endpoint) : serverName
        return "\(server) · \(protocolID.displayName)"
    }

    /// Endpoint without its port
    static func host(of endpoint: String) -> String {
        if endpoint.hasPrefix("["), let close = endpoint.firstIndex(of: "]") {
            return String(endpoint[endpoint.index(after: endpoint.startIndex)..<close])
        }
        guard endpoint.filter({ $0 == ":" }).count == 1, let colon = endpoint.lastIndex(of: ":") else {
            return endpoint
        }
        return String(endpoint[..<colon])
    }

    public func describesSameTunnel(as other: TunnelProfile) -> Bool {
        secretAccount == other.secretAccount
    }
}

/// Which RUNTIME carries a protocol
public enum TunnelDatapath: String, Sendable, CaseIterable {
    case wireGuardKit
    case xray
    /// OpenVPN 3, through `OpenVPNAdapter`
    case openVPN
}

public enum TunnelCapableProtocols {
    public static let all: [ServiceID] = [
        .wireguardVPN, .amneziaWG, .shadowsocks, .xrayReality, .openVPN
    ]

    public static func carries(_ id: ServiceID) -> Bool { datapath(for: id) != nil }

    public static func datapath(for id: ServiceID) -> TunnelDatapath? {
        switch id {
        case .wireguardVPN, .amneziaWG: return .wireGuardKit
        case .shadowsocks, .xrayReality: return .xray
        case .openVPN: return .openVPN
        default: return nil
        }
    }

    /// The datapaths whose runtime this BUILD actually links
    public static let integrated: Set<TunnelDatapath> = [.wireGuardKit, .xray]

    /// Can this build bring this protocol up itself, right now?
    public static func isIntegrated(_ id: ServiceID) -> Bool {
        guard let datapath = datapath(for: id) else { return false }
        return integrated.contains(datapath)
    }
}
