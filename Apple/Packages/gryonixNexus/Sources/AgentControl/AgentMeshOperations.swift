import AgentClient
import Foundation

/// One device in the mesh, in the app's own vocabulary
public struct MeshNode: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    /// The addresses it answers on inside the mesh
    public let addresses: [String]
    /// Which mesh user it belongs to
    public let user: String
    public let isOnline: Bool
    public let lastSeen: Date?

    public init(id: String, name: String, addresses: [String], user: String,
                isOnline: Bool, lastSeen: Date?) {
        self.id = id
        self.name = name
        self.addresses = addresses
        self.user = user
        self.isOnline = isOnline
        self.lastSeen = lastSeen
    }
}

/// A mesh user — what join keys belong to
public struct MeshUser: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A freshly minted join key
public struct MeshName: Sendable, Hashable, Identifiable {
    public let name: String
    public let address: String
    public var id: String { name }

    public init(name: String, address: String) {
        self.name = name
        self.address = address
    }
}

public struct MeshAuthKey: Sendable {
    public let key: String
    public let isReusable: Bool
    /// nil when the server did not say
    public let expiresAt: Date?

    public init(key: String, isReusable: Bool, expiresAt: Date?) {
        self.key = key
        self.isReusable = isReusable
        self.expiresAt = expiresAt
    }
}

@available(macOS 15.0, *)
public struct AgentMeshOperations: Sendable {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    public func users() async throws -> [MeshUser] {
        let client = self.client
        return try await run { try await client.listMeshUsers() }.map { MeshUser(id: $0.id, name: $0.name) }
    }

    @discardableResult
    public func createUser(named name: String) async throws -> [MeshUser] {
        let client = self.client
        return try await run { try await client.createMeshUser(name: name) }
            .map { MeshUser(id: $0.id, name: $0.name) }
    }

    public func mintAuthKey(userID: String, reusable: Bool,
                            expirationHours: UInt32) async throws -> MeshAuthKey {
        let client = self.client
        let call = { @Sendable in
            try await client.createMeshAuthKey(userID: userID, reusable: reusable,
                                               expirationHours: expirationHours)
        }
        let response = if let gate { try await gate.withSlot(call) } else { try await call() }
        return MeshAuthKey(key: response.key,
                           isReusable: response.reusable,
                           expiresAt: response.expiresAt == 0
                               ? nil : Date(timeIntervalSince1970: TimeInterval(response.expiresAt)))
    }

    public func nodes() async throws -> [MeshNode] {
        let client = self.client
        return try await runNodes { try await client.listMeshNodes() }
    }

    @discardableResult
    public func removeNode(id: String) async throws -> [MeshNode] {
        let client = self.client
        return try await runNodes { try await client.deleteMeshNode(nodeID: id) }
    }

    @discardableResult
    public func publishNames(_ names: [String], nodeName: String = "") async throws -> [MeshName] {
        let client = self.client
        let call: @Sendable () async throws -> [Gryonixnexusd_V1_MeshName] = {
            try await client.publishMeshNames(names, nodeName: nodeName)
        }
        let records = if let gate { try await gate.withSlot(call) } else { try await call() }
        return records.map { MeshName(name: $0.name, address: $0.address) }
    }

    private func run(_ call: @escaping @Sendable () async throws -> [Gryonixnexusd_V1_MeshUser])
        async throws -> [Gryonixnexusd_V1_MeshUser] {
        if let gate { return try await gate.withSlot(call) }
        return try await call()
    }

    private func runNodes(_ call: @escaping @Sendable () async throws -> [Gryonixnexusd_V1_MeshNode])
        async throws -> [MeshNode] {
        let nodes = if let gate { try await gate.withSlot(call) } else { try await call() }
        return nodes.map {
            MeshNode(id: $0.id,
                     name: $0.name,
                     addresses: $0.addresses,
                     user: $0.user,
                     isOnline: $0.online,
                     lastSeen: $0.lastSeen == 0
                         ? nil : Date(timeIntervalSince1970: TimeInterval($0.lastSeen)))
        }
    }
}
