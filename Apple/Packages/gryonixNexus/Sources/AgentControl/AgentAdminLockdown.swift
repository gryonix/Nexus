import AgentClient
import Foundation
import ServerControl

public struct AgentAdminLockdown: AdminLockdownManaging {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    public func status() async throws -> AdminLockdownState {
        try await mapping { Self.state(from: try await client.getLockdown()) }
    }

    public func set(_ enabled: Bool) async throws -> AdminLockdownState {
        try await mapping { Self.state(from: try await client.setLockdown(mode: enabled ? .all : .off)) }
    }

    public func set(hosts: [String]) async throws -> AdminLockdownState {
        if hosts.isEmpty { return try await set(false) }
        let invalid = hosts.filter { !CommandCatalog.AdminLockdown.isValidHost($0) }
        guard invalid.isEmpty else {
            throw ServerControlError.commandFailed(
                command: "lockdown", exitCode: nil,
                stderr: "These names cannot be guarded: \(invalid.joined(separator: ", ")). Nothing was changed.")
        }
        return try await mapping { Self.state(from: try await client.setLockdown(mode: .only, hosts: hosts)) }
    }

    // MARK: - Helpers

    private static func state(from proto: Gryonixnexusd_V1_LockdownState) -> AdminLockdownState {
        switch proto.mode {
        case .off, .unspecified, .UNRECOGNIZED(_): return .off
        case .all: return .all
        case .only: return .only(Set(proto.hosts))
        }
    }

    private func mapping<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        do {
            guard let gate else { return try await body() }
            return try await gate.withSlot(body)
        } catch let error as AgentError {
            guard case .rpc(_, let message) = error, !message.isEmpty else { throw error }
            throw ServerControlError.commandFailed(command: "lockdown", exitCode: nil, stderr: message)
        }
    }
}
