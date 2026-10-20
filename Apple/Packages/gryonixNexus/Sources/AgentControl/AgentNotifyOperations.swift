import AgentClient
import Foundation
import ServerControl

/// Health alerts: channel, checks, this phone's registration
public struct AgentNotifyOperations: Sendable {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    public func settings() async throws -> Gryonixnexusd_V1_NotifySettings {
        try await mapping { try await client.getNotifySettings() }
    }

    @discardableResult
    public func save(_ request: Gryonixnexusd_V1_SetNotifySettingsRequest) async throws -> Gryonixnexusd_V1_NotifySettings {
        try await mapping { try await client.setNotifySettings(request) }
    }

    @discardableResult
    public func register(platform: String, token: String, appVersion: String,
                         locale: String, muted: [String] = [],
                         proof: String = "", name: String = "") async throws -> Gryonixnexusd_V1_NotifySettings {
        try await mapping {
            try await client.registerNotifyDevice(platform: platform, token: token, appVersion: appVersion,
                                                  locale: locale, muted: muted, proof: proof, name: name)
        }
    }

    @discardableResult
    public func unregister(token: String) async throws -> Gryonixnexusd_V1_NotifySettings {
        try await mapping { try await client.unregisterNotifyDevice(token: token) }
    }

    public func test() async throws -> Gryonixnexusd_V1_NotifyTestResult {
        try await mapping { try await client.sendTestNotification() }
    }

    private func mapping<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        do {
            guard let gate else { return try await body() }
            return try await gate.withSlot(body)
        } catch let error as AgentError {
            guard case .rpc(_, let message) = error, !message.isEmpty else { throw error }
            throw ServerControlError.commandFailed(command: "notify", exitCode: nil, stderr: message)
        }
    }
}
