import AgentClient
import Foundation
import ServerControl

public struct AgentVaultOperations: Sendable {
    private let client: AgentClient
    private let gate: AgentChannelGate?
    private let deviceUID: String

    public init(client: AgentClient, gate: AgentChannelGate? = nil, deviceUID: String = "") {
        self.client = client
        self.gate = gate
        self.deviceUID = deviceUID
    }

    /// What the server holds
    public func entries() async throws -> [Gryonixnexusd_V1_VaultEntry] {
        try await snapshot().entries.filter { !$0.deleted }
    }

    public func snapshot() async throws -> Gryonixnexusd_V1_VaultSnapshot {
        try await mapping { try await client.vault() }
    }

    @discardableResult
    public func save(_ entries: [Gryonixnexusd_V1_VaultEntry]) async throws
        -> Gryonixnexusd_V1_VaultSnapshot {
        let stamped = entries.map { entry -> Gryonixnexusd_V1_VaultEntry in
            var copy = entry
            if copy.updatedBy.isEmpty {
                copy.updatedBy = deviceUID
            }
            return copy
        }
        return try await mapping { try await client.putVaultEntries(stamped) }
    }

    @discardableResult
    public func delete(id: String) async throws -> Gryonixnexusd_V1_VaultSnapshot {
        try await mapping { try await client.deleteVaultEntry(id: id, deviceUID: deviceUID) }
    }

    private func mapping<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        do {
            guard let gate else { return try await body() }
            return try await gate.withSlot(body)
        } catch let error as AgentError {
            guard case .rpc(_, let message) = error, !message.isEmpty else { throw error }
            throw ServerControlError.commandFailed(command: "vault", exitCode: nil, stderr: message)
        }
    }
}

public enum VaultMerge {
    public static func merged(local: [Gryonixnexusd_V1_VaultEntry],
                              remote: [Gryonixnexusd_V1_VaultEntry])
        -> [Gryonixnexusd_V1_VaultEntry] {
        resolved(local: local, remote: remote).filter { !$0.deleted }
    }

    /// The same answer WITH the tombstones still in it
    public static func resolved(local: [Gryonixnexusd_V1_VaultEntry],
                                remote: [Gryonixnexusd_V1_VaultEntry])
        -> [Gryonixnexusd_V1_VaultEntry] {
        var byID: [String: Gryonixnexusd_V1_VaultEntry] = [:]
        for entry in local + remote {
            guard !entry.id.isEmpty else { continue }
            if let held = byID[entry.id], !isNewer(entry, than: held) { continue }
            byID[entry.id] = entry
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    public static func toPush(local: [Gryonixnexusd_V1_VaultEntry],
                              remote: [Gryonixnexusd_V1_VaultEntry])
        -> [Gryonixnexusd_V1_VaultEntry] {
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, b in
            isNewer(a, than: b) ? a : b
        })
        return local
            .filter { entry in
                guard !entry.id.isEmpty else { return false }
                guard let theirs = remoteByID[entry.id] else { return true }
                return isNewer(entry, than: theirs)
            }
            .sorted { $0.id < $1.id }
    }

    private static func isNewer(_ lhs: Gryonixnexusd_V1_VaultEntry,
                                than rhs: Gryonixnexusd_V1_VaultEntry) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.updatedBy > rhs.updatedBy
    }
}
