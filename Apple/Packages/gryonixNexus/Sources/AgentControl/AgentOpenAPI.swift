import AgentClient
import Foundation
import ServerControl

/// One service's paths open past the VPN guard
public struct OpenAPISite: Sendable, Hashable {
    public let serviceID: String
    public let paths: [String]
    public let editable: Bool

    public init(serviceID: String, paths: [String], editable: Bool) {
        self.serviceID = serviceID
        self.paths = paths
        self.editable = editable
    }
}

/// Reads and changes which API paths answer without the VPN
public struct AgentOpenAPI: Sendable {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    public func sites() async throws -> [String: OpenAPISite] {
        try await mapping { Self.sites(from: try await client.getOpenAPI()) }
    }

    public func set(serviceID: String, paths: [String]) async throws -> [String: OpenAPISite] {
        try await mapping { Self.sites(from: try await client.setOpenAPI(serviceID: serviceID, paths: paths)) }
    }

    static func sites(from state: Gryonixnexusd_V1_OpenAPIState) -> [String: OpenAPISite] {
        Dictionary(state.sites.map {
            ($0.serviceID, OpenAPISite(serviceID: $0.serviceID, paths: $0.paths, editable: $0.editable))
        }) { first, _ in first }
    }

    private func mapping<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        do {
            guard let gate else { return try await body() }
            return try await gate.withSlot(body)
        } catch let error as AgentError {
            guard case .rpc(_, let message) = error, !message.isEmpty else { throw error }
            throw ServerControlError.commandFailed(command: "open API", exitCode: nil, stderr: message)
        }
    }
}
