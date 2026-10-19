import Foundation
import ServiceCatalog

public protocol MailboxManaging: Sendable {
    var isAvailable: Bool { get }

    func list() async throws -> [Mailbox]
    func add(address: String, password: String) async throws
    func delete(address: String) async throws
    func setPassword(address: String, password: String) async throws
}

/// Which implementation a deployment's mailbox screen goes through
public enum MailboxRouting {
    public static func route(usesAgent: Bool, agentTransportAvailable: Bool,
                             hasEngine: Bool) -> ServiceControlRoute {
        guard hasEngine else { return .ssh }
        return ServiceControlRouting.route(usesAgent: usesAgent,
                                           agentTransportAvailable: agentTransportAvailable)
    }
}

/// Mailbox management for the docker-mailserver engine
public struct MailboxOperations: MailboxManaging, Sendable {
    private let runner: any SSHCommandRunner
    private let deployment: Deployment
    private let language: AppLanguage

    public init(runner: any SSHCommandRunner, deployment: Deployment,
                language: AppLanguage = .en) {
        self.runner = runner
        self.deployment = deployment
        self.language = language
    }

    /// The machine the mail engine runs on
    private var host: SSHHostID { deployment.host(running: .dockerMailserver) }

    private func timeout(_ timeoutClass: ServiceCommand.TimeoutClass) -> Duration {
        deployment.timeouts.duration(for: timeoutClass)
    }

    public var isAvailable: Bool {
        deployment.services.contains(.dockerMailserver)
    }

    // MARK: - Reading

    public func list() async throws -> [Mailbox] {
        try requireEngine()
        let command = CommandCatalog.DockerMailserver.listMailboxes
        let result = try await runner.run(command, on: host, timeout: timeout(.quick))
        guard result.succeeded else {
            throw ServerControlError.commandFailure(command: command,
                                                    exitCode: result.exitCode,
                                                    stderr: Self.readable(result.stderr))
        }
        return MailboxListParser.parse(result.stdout)
    }

    // MARK: - Writing

    /// Creates a mailbox
    public func add(address: String, password: String) async throws {
        try validate(address: address)
        try requirePassword(password)
        try await mutate(CommandCatalog.DockerMailserver.addMailbox(address: address),
                         label: "add mailbox", password: password,
                         timeout: timeout(.restart))
    }

    /// Removes a mailbox and everything in it
    public func delete(address: String) async throws {
        try validate(address: address)
        try await mutate(CommandCatalog.DockerMailserver.deleteMailbox(address: address),
                         label: "delete mailbox", password: nil,
                         timeout: timeout(.long))
    }

    public func setPassword(address: String, password: String) async throws {
        try validate(address: address)
        try requirePassword(password)
        try await mutate(CommandCatalog.DockerMailserver.setMailboxPassword(address: address),
                         label: "change mailbox password", password: password,
                         timeout: timeout(.restart))
    }

    // MARK: - Helpers

    private func mutate(_ command: String, label: String, password: String?,
                        timeout: Duration) async throws {
        let result = if let password {
            try await runner.run(command, feeding: password, on: host, timeout: timeout)
        } else {
            try await runner.run(command, on: host, timeout: timeout)
        }
        let stderr = Self.readable(Self.redacting(password, in: result.stderr))
        guard result.succeeded else {
            throw ServerControlError.commandFailure(command: label,
                                                    exitCode: result.exitCode,
                                                    stderr: stderr)
        }
        guard result.stdout.contains(CommandCatalog.DockerMailserver.mailboxDoneMarker) else {
            throw ServerControlError.commandFailed(
                command: label, exitCode: result.exitCode,
                stderr: stderr.isEmpty
                    ? OutputTail.tail(Self.readable(Self.redacting(password, in: result.stdout)))
                    : stderr)
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

    /// Makes an engine message fit to be shown as-is
    static func readable(_ text: String) -> String {
        ANSIStripper.strip(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func redacting(_ password: String?, in text: String) -> String {
        guard let password, !password.isEmpty, text.contains(password) else { return text }
        return text.replacingOccurrences(of: password, with: "***")
    }
}
