/// Parsed `wg show` output: one interface block plus zero or more peers.
public struct WGStatus: Sendable, Hashable {
    public let interface: WGInterfaceStatus
    public let peers: [WGPeer]

    public init(interface: WGInterfaceStatus, peers: [WGPeer]) {
        self.interface = interface
        self.peers = peers
    }
}

public struct WGInterfaceStatus: Sendable, Hashable {
    public let name: String
    public let publicKey: String?
    public let listeningPort: Int?

    public init(name: String, publicKey: String?, listeningPort: Int?) {
        self.name = name
        self.publicKey = publicKey
        self.listeningPort = listeningPort
    }
}

public struct WGPeer: Sendable, Hashable {
    public let publicKey: String
    public let endpoint: String?
    /// Verbatim human text from wg, e.g
    public let latestHandshake: String?
    /// Verbatim transfer line, e.g
    public let transfer: String?
    public let allowedIPs: [String]

    public init(publicKey: String, endpoint: String?, latestHandshake: String?,
                transfer: String?, allowedIPs: [String]) {
        self.publicKey = publicKey
        self.endpoint = endpoint
        self.latestHandshake = latestHandshake
        self.transfer = transfer
        self.allowedIPs = allowedIPs
    }

    public var freshness: HealthLevel {
        guard let handshake = latestHandshake?.lowercased(),
              !handshake.isEmpty, !handshake.contains("never") else {
            return .critical
        }
        let staleUnits = ["hour", "day", "week", "month", "year"]
        if staleUnits.contains(where: handshake.contains) {
            return .warning
        }
        if handshake.contains("second") || handshake.contains("minute") {
            return .ok
        }
        return .warning
    }
}
