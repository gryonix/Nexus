import AgentClient
import Foundation
import ServerControl

public struct AgentDynamicDNSOperations: Sendable {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    public func state() async throws -> Gryonixnexusd_V1_DynamicDNSState {
        try await mapping { try await client.getDynamicDNS() }
    }

    /// Turns it on for `names`
    @discardableResult
    public func enable(zone: String,
                       names: [String],
                       token: String = "") async throws -> Gryonixnexusd_V1_DynamicDNSState {
        try await mapping { try await client.setDynamicDNS(zone: zone, names: names, token: token) }
    }

    /// Turns it off
    @discardableResult
    public func disable() async throws -> Gryonixnexusd_V1_DynamicDNSState {
        try await mapping { try await client.setDynamicDNS(zone: "", names: [], token: "") }
    }

    // MARK: - Helpers

    private func mapping<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        do {
            guard let gate else { return try await body() }
            return try await gate.withSlot(body)
        } catch let error as AgentError {
            guard case .rpc(_, let message) = error, !message.isEmpty else { throw error }
            throw ServerControlError.commandFailed(command: "dynamic-dns", exitCode: nil, stderr: message)
        }
    }
}
