import Foundation
import ServiceCatalog

public protocol ServiceRestoreManaging: Sendable {
    /// Restores this service from `archivePath`, streaming the wrapper's output
    @discardableResult
    func restore(_ service: any ManagedService, archivePath: String, passphrase: String?,
                onChunk: @escaping @Sendable (String) -> Void) async throws -> String
}

/// Which implementation a deployment's RESTORES go through
public enum RestoreRouting {
    public static func route(usesAgent: Bool, agentTransportAvailable: Bool) -> ServiceControlRoute {
        ServiceControlRouting.route(usesAgent: usesAgent, agentTransportAvailable: agentTransportAvailable)
    }
}

/// The SSH implementation: the existing catalog-derived command, unchanged
public struct SSHServiceRestore: ServiceRestoreManaging {
    private let runner: any SSHCommandRunner
    private let deployment: Deployment
    private let language: AppLanguage

    public init(runner: any SSHCommandRunner, deployment: Deployment, language: AppLanguage = .en) {
        self.runner = runner
        self.deployment = deployment
        self.language = language
    }

    @discardableResult
    public func restore(_ service: any ManagedService, archivePath: String, passphrase: String?,
                        onChunk: @escaping @Sendable (String) -> Void) async throws -> String {
        try await ServiceOperations(runner: runner, deployment: deployment, service: service, language: language)
            .restore(archivePath: archivePath, passphrase: passphrase, onChunk: onChunk)
    }
}
