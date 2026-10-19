import AgentClient
import Foundation
import ServerControl
import ServiceCatalog

public struct AgentMailboxOperations: MailboxManaging {
    private let client: AgentClient
    private let gate: AgentChannelGate?
    private let engineInstalled: Bool
    private let language: AppLanguage

    public init(client: AgentClient, engineInstalled: Bool,
                gate: AgentChannelGate? = nil, language: AppLanguage = .en) {
        self.client = client
        self.engineInstalled = engineInstalled
        self.gate = gate
        self.language = language
    }

    public var isAvailable: Bool { engineInstalled }

    public func list() async throws -> [Mailbox] {
        try requireEngine()
        return try await mapping { try await client.listMailboxes().map(Mailbox.init(agent:)) }
    }

    public func add(address: String, password: String) async throws {
        try validate(address: address)
        try requirePassword(password)
        _ = try await mapping { try await client.createMailbox(address: address, password: password) }
    }

    public func delete(address: String) async throws {
        try validate(address: address)
        _ = try await mapping { try await client.deleteMailbox(address: address) }
    }

    public func setPassword(address: String, password: String) async throws {
        try validate(address: address)
        try requirePassword(password)
        _ = try await mapping { try await client.setMailboxPassword(address: address, password: password) }
    }

    // MARK: - Helpers

    private func mapping<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        do {
            guard let gate else { return try await body() }
            return try await gate.withSlot(body)
        } catch let error as AgentError {
            guard case .rpc(_, let message) = error, !message.isEmpty else { throw error }
            throw ServerControlError.commandFailed(command: "mailboxes", exitCode: nil, stderr: message)
        }
    }

    private func validate(address: String) throws {
        try requireEngine()
        guard CommandCatalog.DockerMailserver.isValidAddress(address) else {
            throw ServerControlError.notConfigured(
                L10nOperations.mailboxInvalidAddress(language, address: address))
        }
    }

    private func requirePassword(_ password: String) throws {
        guard !password.isEmpty else {
            throw ServerControlError.notConfigured(L10nOperations.mailboxPasswordEmpty(language))
        }
    }

    private func requireEngine() throws {
        guard isAvailable else {
            throw ServerControlError.notConfigured(L10nOperations.mailboxesNotAvailable(language))
        }
    }
}

extension Mailbox {
    /// The agent's row in the shape the screen already reads
    init(agent mailbox: Gryonixnexusd_V1_Mailbox) {
        self.init(address: mailbox.address,
                  detail: mailbox.detail.isEmpty ? nil : mailbox.detail)
    }
}
