import AgentClient
import Foundation
import ServerControl
import ServiceCatalog

public struct AgentBackupOperations: ServiceBackupManaging {
    private let client: AgentClient
    private let gate: AgentChannelGate?
    private let language: AppLanguage

    public init(client: AgentClient, gate: AgentChannelGate? = nil, language: AppLanguage = .en) {
        self.client = client
        self.gate = gate
        self.language = language
    }

    public func listBackups(of service: any ManagedService) async throws -> [BackupEntry] {
        let id = try agentID(service)
        let list = try await mapping { try await client.listBackups(serviceID: id) }
        return list.archives.prefix(BackupListParser.defaultLimit).map(BackupEntry.init(agent:))
    }

    /// Every service's backups in one call, by agent service id
    public func listAll() async throws -> [String: [BackupEntry]] {
        let all = try await mapping { try await client.listAllBackups() }
        return Dictionary(all.lists.map { ($0.serviceID, $0.archives.map(BackupEntry.init(agent:))) },
                          uniquingKeysWith: { first, _ in first })
    }

    public func estimate(of service: any ManagedService) async throws -> BackupEstimate? {
        let id = try agentID(service)
        let estimate = try await mapping { try await client.estimateBackup(serviceID: id) }
        return BackupEstimate(dataBytes: UInt64(max(0, estimate.dataBytes)),
                              freeBytes: UInt64(max(0, estimate.freeBytes)))
    }

    @discardableResult
    public func backup(_ service: any ManagedService, encrypt: Bool?, passphrase: String?,
                       onChunk: @escaping @Sendable (String) -> Void) async throws -> BackupOutcome {
        let id = try agentID(service)
        let encryption: Gryonixnexusd_V1_BackupEncryption = switch encrypt {
        case .none: .unspecified
        case .some(true): .enabled
        case .some(false): .disabled
        }
        let client = self.client
        var log = ""
        var archive: Gryonixnexusd_V1_BackupArchive?
        var backups: [BackupEntry] = []
        var completed = false
        do {
            for try await event in client.runBackup(serviceID: id, encryption: encryption,
                                                    passphrase: passphrase ?? "") {
                switch event.phase {
                case .progress:
                    let line = event.text.hasSuffix("\n") ? event.text : event.text + "\n"
                    log += line
                    onChunk(line)
                case .completed:
                    completed = true
                    if event.hasArchive { archive = event.archive }
                    if event.hasBackups {
                        backups = event.backups.archives.map(BackupEntry.init(agent:))
                    }
                case .started, .unspecified, .UNRECOGNIZED:
                    break
                }
            }
        } catch {
            guard completed else { throw error }
            throw AgentControlError.backupFailed(underlying: Self.asAgentError(error),
                                                 backups: backups)
        }
        return BackupOutcome(sizeBytes: archive.map { UInt64(max(0, $0.sizeBytes)) },
                             path: archive?.path,
                             log: OutputTail.tail(log))
    }

    public func deleteBackup(_ service: any ManagedService, path: String) async throws {
        let id = try agentID(service)
        _ = try await mapping { try await client.deleteBackup(serviceID: id, path: path) }
    }

    // MARK: - Helpers

    private func agentID(_ service: any ManagedService) throws -> String {
        guard let id = AgentServiceMapping.agentID(for: service.id) else {
            throw AgentControlError.unsupportedService(service.displayName)
        }
        return id
    }

    private func mapping<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        do {
            guard let gate else { return try await body() }
            return try await gate.withSlot(body)
        } catch let error as AgentError {
            guard case .rpc(_, let message) = error, !message.isEmpty else { throw error }
            throw ServerControlError.commandFailed(command: "backup", exitCode: nil, stderr: message)
        }
    }

    private static func asAgentError(_ error: Error) -> AgentError {
        error as? AgentError ?? .transport("\(error)")
    }
}

extension BackupEntry {
    init(agent archive: Gryonixnexusd_V1_BackupArchive) {
        self.init(name: archive.path,
                  sizeText: Self.sizeText(archive.sizeBytes, directory: archive.directory),
                  dateText: Self.dateText(archive.modifiedAt),
                  isDirectory: archive.directory,
                  drive: archive.drive.isEmpty ? nil : archive.drive,
                  sizeBytes: archive.directory ? nil : archive.sizeBytes,
                  modifiedAt: archive.modifiedAt > 0
                      ? Date(timeIntervalSince1970: Double(archive.modifiedAt) / 1000) : nil)
    }

    private static func sizeText(_ bytes: Int64, directory: Bool) -> String {
        guard !directory else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func dateText(_ millis: Int64) -> String {
        guard millis > 0 else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
    }
}
