import AgentClient
import Foundation

/// A data folder a restore set aside
public struct PreRestoreCopy: Equatable, Sendable, Identifiable {
    public let serviceID: String
    public let path: String
    public let sizeBytes: UInt64
    /// False when the agent ran out of time measuring it
    public let sizeKnown: Bool
    public let movedAside: Date

    public var id: String { path }

    /// The folder's own name
    public var name: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    public init(_ copy: Gryonixnexusd_V1_PreRestoreCopy) {
        serviceID = copy.serviceID
        path = copy.path
        sizeBytes = copy.sizeBytes
        sizeKnown = copy.sizeKnown
        movedAside = Date(timeIntervalSince1970: TimeInterval(copy.movedAsideUnix))
    }
}

public struct AgentPreRestoreOperations: Sendable {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    /// The old copies of one service, newest first
    public func copies(serviceID: String) async throws -> [PreRestoreCopy] {
        let list = try await gated { try await client.listPreRestoreCopies(serviceID: serviceID) }
        return Self.newestFirst(list)
    }

    /// Deletes one copy, returns the remaining ones
    public func delete(_ copy: PreRestoreCopy) async throws -> [PreRestoreCopy] {
        let list = try await gated { try await client.deletePreRestoreCopy(path: copy.path) }
        return Self.newestFirst(list)
    }

    static func newestFirst(_ list: Gryonixnexusd_V1_PreRestoreCopyList) -> [PreRestoreCopy] {
        list.copies.map(PreRestoreCopy.init).sorted { $0.movedAside > $1.movedAside }
    }

    private func gated<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        guard let gate else { return try await body() }
        return try await gate.withSlot(body)
    }
}
