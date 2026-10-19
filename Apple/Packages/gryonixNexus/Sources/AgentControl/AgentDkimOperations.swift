import AgentClient
import Foundation
import ServerControl

public struct AgentDkimOperations: DKIMManaging {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    public func fetchRecords() async throws -> [DKIMRecord] {
        do {
            let records: [Gryonixnexusd_V1_DkimRecord]
            if let gate {
                records = try await gate.withSlot { try await client.getDkimRecords() }
            } else {
                records = try await client.getDkimRecords()
            }
            return records.map { DKIMRecord(name: $0.name, value: $0.value) }
        } catch let error as AgentError {
            guard case .rpc(_, let message) = error, !message.isEmpty else { throw error }
            throw ServerControlError.commandFailed(command: "dkim", exitCode: nil, stderr: message)
        }
    }
}
