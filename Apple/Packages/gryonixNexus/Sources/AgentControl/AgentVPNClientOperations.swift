import AgentClient
import ServiceCatalog

/// One VPN client device, in the app's own vocabulary
public struct VPNClientDevice: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let detail: String
    /// The resolvers its configuration carries
    public let dns: [String]

    public init(id: String, name: String, detail: String, dns: [String] = []) {
        self.id = id
        self.name = name
        self.detail = detail
        self.dns = dns
    }
}

/// A client's configuration as its own app imports it
public struct VPNClientConfiguration: Sendable {
    public let text: String
    public let fileName: String
    public let qrIsUseful: Bool
    /// What a proxy link cannot carry itself
    public let dns: [String]

    public init(text: String, fileName: String, qrIsUseful: Bool, dns: [String] = []) {
        self.text = text
        self.fileName = fileName
        self.qrIsUseful = qrIsUseful
        self.dns = dns
    }
}

/// The order the server's DNS relay asks resolvers in
public struct VPNDNSPriority: Sendable, Equatable {
    /// The entry for the deployment's own resolver
    public static let local = "local"

    public var resolvers: [String]
    /// Whether a resolver stands behind `local`
    public var localAvailable: Bool
    /// Per resolver: whether it answered lately
    public var reachable: [Bool]

    public init(resolvers: [String] = [VPNDNSPriority.local, "1.1.1.1"], localAvailable: Bool = false,
                reachable: [Bool] = []) {
        self.resolvers = resolvers
        self.localAvailable = localAvailable
        self.reachable = reachable
    }

    init(_ message: Gryonixnexusd_V1_VpnDnsPriority) {
        self.init(resolvers: message.resolvers, localAvailable: message.localAvailable,
                  reachable: message.reachable)
    }

    /// Whether the resolver at this position answered lately
    public func isReachable(at index: Int) -> Bool {
        reachable.indices.contains(index) ? reachable[index] : true
    }
}

/// The DNS new devices get, and the server's own resolver
public struct VPNDNSDefaults: Sendable, Equatable {
    public var dns: [String]
    /// Where the server's resolver answers; empty when it cannot
    public var localAddress: String
    /// AdGuard Home or Pi-hole, when devices can reach them
    public var localServices: [ServiceID]

    public init(dns: [String] = [], localAddress: String = "", localServices: [ServiceID] = []) {
        self.dns = dns
        self.localAddress = localAddress
        self.localServices = localServices
    }

    init(_ proto: Gryonixnexusd_V1_VpnDns) {
        self.init(dns: proto.dns,
                  localAddress: proto.localAddress,
                  localServices: proto.localServices.map { ServiceID(rawValue: $0) })
    }
}

@available(macOS 15.0, *)
public struct AgentVPNClientOperations: Sendable {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    public func list(protocol id: ServiceID) async throws -> [VPNClientDevice] {
        try await run { try await client.listVPNClients(protocol: id.rawValue) }
    }

    @discardableResult
    public func add(protocol id: ServiceID, named name: String, dns: [String] = []) async throws -> [VPNClientDevice] {
        try await run { try await client.addVPNClient(protocol: id.rawValue, clientName: name, dns: dns) }
    }

    @discardableResult
    public func setDNS(protocol id: ServiceID, clientID: String, dns: [String]) async throws -> [VPNClientDevice] {
        try await run { try await client.setVPNClientDNS(protocol: id.rawValue, clientID: clientID, dns: dns) }
    }

    public func defaultDNS() async throws -> VPNDNSDefaults {
        let client = self.client
        let call = { @Sendable in VPNDNSDefaults(try await client.vpnDefaultDNS()) }
        return if let gate { try await gate.withSlot(call) } else { try await call() }
    }

    @discardableResult
    public func setDefaultDNS(_ dns: [String]) async throws -> VPNDNSDefaults {
        let client = self.client
        let call = { @Sendable in VPNDNSDefaults(try await client.setVPNDefaultDNS(dns)) }
        return if let gate { try await gate.withSlot(call) } else { try await call() }
    }

    public func dnsPriority() async throws -> VPNDNSPriority {
        let client = self.client
        let call = { @Sendable in VPNDNSPriority(try await client.vpnDNSPriority()) }
        return if let gate { try await gate.withSlot(call) } else { try await call() }
    }

    @discardableResult
    public func setDNSPriority(_ resolvers: [String]) async throws -> VPNDNSPriority {
        let client = self.client
        let call = { @Sendable in VPNDNSPriority(try await client.setVPNDNSPriority(resolvers)) }
        return if let gate { try await gate.withSlot(call) } else { try await call() }
    }

    @discardableResult
    public func remove(protocol id: ServiceID, clientID: String) async throws -> [VPNClientDevice] {
        try await run { try await client.deleteVPNClient(protocol: id.rawValue, clientID: clientID) }
    }

    public func configuration(protocol id: ServiceID, clientID: String) async throws -> VPNClientConfiguration {
        let client = self.client
        let call = { @Sendable in try await client.vpnClientConfig(protocol: id.rawValue, clientID: clientID) }
        let response = if let gate { try await gate.withSlot(call) } else { try await call() }
        return VPNClientConfiguration(text: response.text,
                                      fileName: response.filename,
                                      qrIsUseful: response.qrIsUseful,
                                      dns: response.dns)
    }

    private func run(_ call: @escaping @Sendable () async throws -> [Gryonixnexusd_V1_VpnClient]) async throws
        -> [VPNClientDevice] {
        let clients = if let gate { try await gate.withSlot(call) } else { try await call() }
        return clients.map { VPNClientDevice(id: $0.id, name: $0.name, detail: $0.detail, dns: $0.dns) }
    }
}

/// Which catalog services can have client devices at all
public enum VPNClientProtocols {
    public static let all: [ServiceID] = [.wireguardVPN, .amneziaWG, .shadowsocks, .xrayReality, .openVPN]

    public static func installed(in services: Set<ServiceID>) -> [ServiceID] {
        all.filter { services.contains($0) }
    }
}
