import AgentClient
import Foundation
import ServerControl
import ServiceCatalog

public struct AgentServiceRemoval: ServiceRemovalManaging {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    /// Removes the service, streaming the wrapper's output
    @discardableResult
    public func remove(_ service: any ManagedService, purge: PurgeOptions,
                       onChunk: @escaping @Sendable (String) -> Void) async throws -> String {
        let id = try agentID(service)
        let client = self.client
        var log = ""
        var status: [ContainerStatus]?
        do {
            for try await event in client.removeService(serviceID: id, purgeData: purge.data,
                                                         purgeBackups: purge.backups) {
                switch event.phase {
                case .progress:
                    let line = event.text.hasSuffix("\n") ? event.text : event.text + "\n"
                    log += line
                    onChunk(line)
                case .completed:
                    status = event.status.installed
                        ? event.status.service.containers.map(ContainerStatus.init(agent:))
                        : []
                case .started, .unspecified, .UNRECOGNIZED:
                    break
                }
            }
        } catch {
            guard let status else { throw error }
            throw AgentControlError.operationFailed(underlying: Self.asAgentError(error), status: status)
        }
        return OutputTail.tail(log)
    }

    private func agentID(_ service: any ManagedService) throws -> String {
        guard let id = AgentServiceMapping.agentID(for: service.id) else {
            throw AgentControlError.unsupportedService(service.displayName)
        }
        return id
    }

    private static func asAgentError(_ error: Error) -> AgentError {
        error as? AgentError ?? .transport("\(error)")
    }
}
