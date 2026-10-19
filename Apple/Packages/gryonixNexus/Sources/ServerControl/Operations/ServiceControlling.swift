import Foundation
import ServiceCatalog

public enum ServicePowerAction: String, Sendable, Hashable, CaseIterable {
    case start
    case stop
    case restart
}

public protocol ServiceControlling: Sendable {
    func status(of service: any ManagedService) async throws -> [ContainerStatus]

    @discardableResult
    func power(_ action: ServicePowerAction, on service: any ManagedService,
               onProgress: @escaping @Sendable (String) -> Void) async throws -> [ContainerStatus]
}

public extension ServiceControlling {
    @discardableResult
    func power(_ action: ServicePowerAction, on service: any ManagedService) async throws -> [ContainerStatus] {
        try await power(action, on: service, onProgress: { _ in })
    }
}

/// Which implementation a deployment's management goes through
public enum ServiceControlRoute: String, Sendable, Hashable {
    case ssh
    case agent
}

public enum ServiceControlRouting {
    public static func route(usesAgent: Bool, agentTransportAvailable: Bool) -> ServiceControlRoute {
        usesAgent && agentTransportAvailable ? .agent : .ssh
    }
}

/// The SSH implementation: the existing catalog-derived commands, unchanged
public struct SSHServiceControl: ServiceControlling {
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

    public func status(of service: any ManagedService) async throws -> [ContainerStatus] {
        try await operations(service).status()
    }

    @discardableResult
    public func power(_ action: ServicePowerAction, on service: any ManagedService,
                      onProgress: @escaping @Sendable (String) -> Void) async throws -> [ContainerStatus] {
        let operations = operations(service)
        switch action {
        case .start: try await operations.start()
        case .stop: try await operations.stop()
        case .restart: try await operations.restart()
        }
        return try await operations.status()
    }
}
