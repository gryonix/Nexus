import Foundation
import ServiceCatalog

public protocol ServiceBackupManaging: Sendable {
    /// What is in this service's backup directory, newest first
    func listBackups(of service: any ManagedService) async throws -> [BackupEntry]

    func estimate(of service: any ManagedService) async throws -> BackupEstimate?

    /// Runs one backup
    @discardableResult
    func backup(_ service: any ManagedService, encrypt: Bool?, passphrase: String?,
                onChunk: @escaping @Sendable (String) -> Void) async throws -> BackupOutcome

    /// Deletes one backup
    func deleteBackup(_ service: any ManagedService, path: String) async throws
}

/// Which implementation a deployment's backups go through
public enum BackupRouting {
    public static func route(usesAgent: Bool, agentTransportAvailable: Bool,
                             kind: ServiceOperations.BackupKind) -> ServiceControlRoute {
        guard kind == .wrapper else { return .ssh }
        return ServiceControlRouting.route(usesAgent: usesAgent,
                                           agentTransportAvailable: agentTransportAvailable)
    }
}

/// The SSH implementation: the existing catalog-derived commands, unchanged
public struct SSHServiceBackups: ServiceBackupManaging {
    private let runner: any SSHCommandRunner
    private let deployment: Deployment
    private let language: AppLanguage

    public init(runner: any SSHCommandRunner, deployment: Deployment, language: AppLanguage = .en) {
        self.runner = runner
        self.deployment = deployment
        self.language = language
    }

    private func operations(_ service: any ManagedService) -> ServiceOperations {
        ServiceOperations(runner: runner, deployment: deployment, service: service, language: language)
    }

    public func listBackups(of service: any ManagedService) async throws -> [BackupEntry] {
        try await operations(service).listBackups()
    }

    public func estimate(of service: any ManagedService) async throws -> BackupEstimate? {
        try await operations(service).estimateBackup()
    }

    @discardableResult
    public func backup(_ service: any ManagedService, encrypt: Bool?, passphrase: String?,
                       onChunk: @escaping @Sendable (String) -> Void) async throws -> BackupOutcome {
        try await operations(service).backup(encrypt: encrypt, passphrase: passphrase, onChunk: onChunk)
    }

    public func deleteBackup(_ service: any ManagedService, path: String) async throws {
        try await operations(service).deleteBackup(path: path)
    }
}
