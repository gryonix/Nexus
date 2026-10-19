import Foundation
import ServiceCatalog

public protocol ServiceUpdateManaging: Sendable {
    func check() async throws -> [ServiceUpdateReport]

    /// Applies one service's update, streaming output as it arrives
    @discardableResult
    func run(_ service: ServiceID,
            onChunk: @escaping @Sendable (String) -> Void) async throws -> ServiceUpdateRunRecord

    /// The stored schedule, or "off" when unset or unreadable
    func loadSchedule() async throws -> AutoUpdateSettings

    /// What the last scheduled (or manual) run left behind
    func loadStatus() async throws -> ServiceUpdateRunLog

    /// Writes a new schedule
    func save(_ settings: AutoUpdateSettings) async throws
}

/// Which implementation a deployment's UPDATES go through
public enum ServiceUpdateRouting {
    public static func route(usesAgent: Bool, agentTransportAvailable: Bool) -> ServiceControlRoute {
        ServiceControlRouting.route(usesAgent: usesAgent,
                                    agentTransportAvailable: agentTransportAvailable)
    }
}

public enum RemovalScope: Sendable, Hashable {
    /// One service, through the uninstall wrapper's per-service arm
    case service
    case everything
}

/// Which implementation a removal goes through
public enum ServiceRemovalRouting {
    public static func route(scope: RemovalScope, usesAgent: Bool,
                             agentTransportAvailable: Bool) -> ServiceControlRoute {
        guard scope == .service else { return .ssh }
        return ServiceControlRouting.route(usesAgent: usesAgent,
                                           agentTransportAvailable: agentTransportAvailable)
    }
}

public protocol ServiceRemovalManaging: Sendable {
    @discardableResult
    func remove(_ service: any ManagedService, purge: PurgeOptions,
               onChunk: @escaping @Sendable (String) -> Void) async throws -> String
}

public struct SSHServiceRemoval: ServiceRemovalManaging {
    private let runner: any SSHCommandRunner
    private let deployment: Deployment
    private let language: AppLanguage

    public init(runner: any SSHCommandRunner, deployment: Deployment, language: AppLanguage = .en) {
        self.runner = runner
        self.deployment = deployment
        self.language = language
    }

    @discardableResult
    public func remove(_ service: any ManagedService, purge: PurgeOptions,
                       onChunk: @escaping @Sendable (String) -> Void) async throws -> String {
        try await ServiceOperations(runner: runner, deployment: deployment, service: service,
                                    language: language)
            .uninstall(purge: purge, onChunk: onChunk)
    }
}
