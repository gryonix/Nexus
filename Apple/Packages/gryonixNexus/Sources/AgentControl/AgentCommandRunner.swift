import AgentClient
import Foundation
import ServerControl
import ServiceCatalog

public struct AgentCommandRunner: ServiceControlling {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    public static func agentID(for service: any ManagedService) -> String? {
        AgentServiceMapping.agentID(for: service.id)
    }

    public func status(of service: any ManagedService) async throws -> [ContainerStatus] {
        let id = try agentID(service)
        let response = try await withSlot { try await client.serviceStatus(serviceID: id) }
        guard response.installed else { return [] }
        return response.service.containers.map(ContainerStatus.init(agent:))
    }

    @discardableResult
    public func power(_ action: ServicePowerAction, on service: any ManagedService,
                      onProgress: @escaping @Sendable (String) -> Void) async throws -> [ContainerStatus] {
        let id = try agentID(service)
        let wire = Self.wireAction(action)
        let client = self.client
        return try await withSlot {
            var containers: [ContainerStatus] = []
            do {
                for try await event in client.controlService(serviceID: id, action: wire) {
                    switch event.phase {
                    case .progress:
                        onProgress(event.text.hasSuffix("\n") ? event.text : event.text + "\n")
                    case .completed:
                        containers = event.service.containers.map(ContainerStatus.init(agent:))
                    case .started, .unspecified, .UNRECOGNIZED:
                        break
                    }
                }
            } catch {
                guard !containers.isEmpty else { throw error }
                throw AgentControlError.operationFailed(underlying: Self.asAgentError(error),
                                                        status: containers)
            }
            return containers
        }
    }

    private static func asAgentError(_ error: Error) -> AgentError {
        error as? AgentError ?? .transport("\(error)")
    }

    private func withSlot<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        guard let gate else { return try await body() }
        return try await gate.withSlot(body)
    }

    private func agentID(_ service: any ManagedService) throws -> String {
        guard let id = Self.agentID(for: service) else {
            throw AgentControlError.unsupportedService(service.displayName)
        }
        return id
    }

    private static func wireAction(_ action: ServicePowerAction) -> Gryonixnexusd_V1_ServiceAction {
        switch action {
        case .start: return .start
        case .stop: return .stop
        case .restart: return .restart
        }
    }
}

public enum AgentControlError: Error, Sendable, Equatable, LocalizedError {
    case unsupportedService(String)

    case operationFailed(underlying: AgentError, status: [ContainerStatus])

    case backupFailed(underlying: AgentError, backups: [BackupEntry])

    public var errorDescription: String? {
        switch self {
        case .unsupportedService(let name):
            return "The server agent does not manage \(name) yet."
        case .backupFailed(let underlying, _):
            if case .rpc(_, let message) = underlying, !message.isEmpty { return message }
            return "\(underlying)"
        case .operationFailed(let underlying, _):
            if case .rpc(_, let message) = underlying, !message.isEmpty { return message }
            return "\(underlying)"
        }
    }
}

extension ContainerStatus {
    init(agent container: Gryonixnexusd_V1_Container) {
        let state = container.state.isEmpty ? "unknown" : container.state
        var text: String
        switch state {
        case "running": text = "Up"
        case "exited", "dead": text = "Exited"
        default: text = state.prefix(1).uppercased() + state.dropFirst()
        }
        if !container.health.isEmpty { text += " (\(container.health))" }
        self.init(name: container.name, status: text)
    }
}
