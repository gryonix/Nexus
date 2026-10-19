import AgentClient
import Foundation
import ServerControl
import ServiceCatalog

public struct AgentRestoreOperations: ServiceRestoreManaging {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    /// Restores the service, streaming the wrapper's output
    @discardableResult
    public func restore(_ service: any ManagedService, archivePath: String, passphrase: String?,
                        onChunk: @escaping @Sendable (String) -> Void) async throws -> String {
        let id = try agentID(service)
        let client = self.client
        let archivePath = try await staged(archivePath, serviceID: id)
        var log = ""
        var status: [ContainerStatus]?
        do {
            for try await event in client.runRestore(serviceID: id, archivePath: archivePath,
                                                      passphrase: passphrase ?? "") {
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

    /// Stages a USB drive copy on the server's disk
    private func staged(_ path: String, serviceID: String) async throws -> String {
        guard BackupDriveScripts.isDriveCopy(path) else { return path }
        let client = self.client
        let staged = try await gated { try await client.fetchDriveBackup(serviceID: serviceID, path: path) }
        return staged.path
    }

    private func gated<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        guard let gate else { return try await body() }
        return try await gate.withSlot(body)
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
