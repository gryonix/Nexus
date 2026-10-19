import AgentClient
import Foundation
import ServerControl
import ServiceCatalog

/// One machine of a deployment, driven through its own agent
public struct AgentServiceMoveMachine: ServiceMoveMachine {
    private let client: AgentClient
    private let shell: (any ServiceMoveShell)?

    public init(client: AgentClient, shell: (any ServiceMoveShell)? = nil) {
        self.client = client
        self.shell = shell
    }

    // MARK: - Services

    public func hasService(_ service: ServiceID) async throws -> Bool {
        try await client.serviceStatus(serviceID: try agentID(service)).installed
    }

    public func estimatedBytes(of service: ServiceID) async throws -> Int64 {
        let estimate = try await AgentBackupOperations(client: client).estimate(of: try managed(service))
        return Int64(estimate?.dataBytes ?? 0)
    }

    public func install(_ service: ServiceID, context: AgentInstallContext,
                        log: @escaping ServiceMoveLog) async throws {
        try await AgentInstallOperations(client: client).install(service, context: context, onChunk: log)
    }

    public func backUp(_ service: ServiceID, log: @escaping ServiceMoveLog) async throws -> ServiceMoveArchive {
        let id = try agentID(service)
        let outcome = try await AgentBackupOperations(client: client)
            .backup(try managed(service), encrypt: false, passphrase: nil, onChunk: log)
        let listing = try await client.listBackups(serviceID: id).archives
        let found = outcome.path.flatMap { path in listing.first { $0.path == path } } ?? listing.first
        guard let archive = found, !archive.directory else { throw ServiceMoveProblem.noArchive }
        return ServiceMoveArchive(path: archive.path, name: archive.name, bytes: archive.sizeBytes)
    }

    public func start(_ service: ServiceID, log: @escaping ServiceMoveLog) async throws {
        try await AgentCommandRunner(client: client).power(.start, on: try managed(service), onProgress: log)
    }

    public func stop(_ service: ServiceID, log: @escaping ServiceMoveLog) async throws {
        try await AgentCommandRunner(client: client).power(.stop, on: try managed(service), onProgress: log)
    }

    public func restore(_ service: ServiceID, archivePath: String, log: @escaping ServiceMoveLog) async throws {
        try await AgentRestoreOperations(client: client)
            .restore(try managed(service), archivePath: archivePath, passphrase: nil, onChunk: log)
    }

    public func removeCopy(_ service: ServiceID, log: @escaping ServiceMoveLog) async throws {
        guard try await hasService(service) else { return }
        try await AgentServiceRemoval(client: client)
            .remove(try managed(service), purge: PurgeOptions(data: true, backups: false), onChunk: log)
    }

    public func deleteBackup(_ service: ServiceID, path: String) async throws {
        try await client.deleteBackup(serviceID: try agentID(service), path: path)
    }

    // MARK: - Transfer

    public func prepareSend(transferID: String) async throws -> String {
        try await client.prepareMoveSend(transferID: transferID)
    }

    public func prepareReceive(transferID: String, service: ServiceID, publicKey: String,
                               expectedBytes: Int64) async throws -> ServiceMoveGrant {
        guard let shell else { throw ServiceMoveProblem.noLoginAccess }
        let grant = try await client.prepareMoveReceive(
            transferID: transferID, serviceID: try agentID(service), controlUser: shell.loginUser,
            publicKey: publicKey, expectedBytes: expectedBytes)
        return ServiceMoveGrant(authorizedKeyLine: grant.authorizedKeyLine, hostKeys: grant.hostKeys,
                                freeBytes: grant.freeBytes)
    }

    public func authorize(_ grant: ServiceMoveGrant) async throws {
        try await shell?.appendAuthorizedKey(grant.authorizedKeyLine)
    }

    public func revoke(transferID: String) async throws {
        try await shell?.removeAuthorizedKeys(containing: Self.marker(transferID))
    }

    public func send(transferID: String, service: ServiceID, archivePath: String, to target: ServiceMoveEndpoint,
                     hostKeys: String, log: @escaping ServiceMoveLog) async throws -> ServiceMoveSent {
        var sent: ServiceMoveSent?
        for try await event in client.sendMoveData(
            transferID: transferID, serviceID: try agentID(service), archivePath: archivePath,
            host: target.host, port: target.port, user: target.user, hostKeys: hostKeys) {
            switch event.phase {
            case .progress: log(event.text.hasSuffix("\n") ? event.text : event.text + "\n")
            case .completed:
                sent = ServiceMoveSent(bytes: event.bytes, sha256: event.sha256, archiveName: event.archiveName)
            case .started, .unspecified, .UNRECOGNIZED: break
            }
        }
        guard let sent else { throw ServiceMoveProblem.noArchive }
        return sent
    }

    public func accept(transferID: String, service: ServiceID, sent: ServiceMoveSent,
                       log: @escaping ServiceMoveLog) async throws -> String {
        var path: String?
        for try await event in client.acceptMoveData(
            transferID: transferID, serviceID: try agentID(service), sha256: sent.sha256,
            bytes: sent.bytes, archiveName: sent.archiveName) {
            switch event.phase {
            case .progress: log(event.text.hasSuffix("\n") ? event.text : event.text + "\n")
            case .completed: path = event.archivePath
            case .started, .unspecified, .UNRECOGNIZED: break
            }
        }
        guard let path, !path.isEmpty else { throw ServiceMoveProblem.noArchive }
        return path
    }

    public func discard(transferID: String) async throws {
        try await client.discardMoveTransfer(transferID: transferID)
    }

    // MARK: - The front's site

    public func site(_ change: ServiceMoveSiteChange) async throws -> ServiceMoveSite {
        var request = Gryonixnexusd_V1_SetServiceUpstreamRequest()
        request.serviceID = try agentID(change.service)
        request.localPort = change.localPort
        request.localHTTPS = change.localHTTPS
        request.overwriteForwardedFor = change.overwriteForwardedFor
        request.remoteAddress = change.remoteAddress ?? ""
        request.dryRun = change.dryRun
        let state = try await client.setServiceUpstream(request)
        switch state.current {
        case "local": return .local
        case "remote": return .remote(state.remoteAddress)
        case "missing": return .missing
        default: return .unknown
        }
    }

    public func probe(_ service: ServiceID) async throws -> ServiceMoveProbe {
        let answer = try await client.probeServiceUpstream(serviceID: try agentID(service))
        return ServiceMoveProbe(answered: answer.answered, unavailable: answer.unavailable,
                                status: answer.status, detail: answer.detail)
    }

    // MARK: - Helpers

    public static func marker(_ transferID: String) -> String { "gryonixnexus-move-\(transferID)" }

    private func agentID(_ service: ServiceID) throws -> String {
        guard let id = AgentServiceMapping.agentID(for: service) else {
            throw AgentControlError.unsupportedService(service.rawValue)
        }
        return id
    }

    private func managed(_ service: ServiceID) throws -> any ManagedService {
        guard let found = ServiceRegistry.service(service) else {
            throw AgentControlError.unsupportedService(service.rawValue)
        }
        return found
    }
}
