import AgentClient
import Foundation
import ServerControl

public struct AgentDeviceOperations: Sendable {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    public func listDevices() async throws -> [Gryonixnexusd_V1_Device] {
        try await mapping { try await client.listDevices() }
    }

    @discardableResult
    public func revoke(deviceID: String) async throws -> Bool {
        try await mapping { try await client.revoke(deviceID: deviceID) }
    }

    public func createTransfer(validMinutes: Int32) async throws -> Gryonixnexusd_V1_CreateTransferResponse {
        try await mapping { try await client.createTransfer(validMinutes: validMinutes) }
    }

    public func sessionPolicy() async throws -> Gryonixnexusd_V1_SessionPolicy {
        try await mapping { try await client.sessionPolicy() }
    }

    @discardableResult
    public func setSessionPolicy(months: Int32) async throws -> Gryonixnexusd_V1_SessionPolicy {
        try await mapping { try await client.setSessionPolicy(months: months) }
    }

    // MARK: - Helpers

    private func mapping<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        do {
            guard let gate else { return try await body() }
            return try await gate.withSlot(body)
        } catch let error as AgentError {
            guard case .rpc(_, let message) = error, !message.isEmpty else { throw error }
            throw ServerControlError.commandFailed(command: "devices", exitCode: nil, stderr: message)
        }
    }
}
