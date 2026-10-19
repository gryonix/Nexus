import AgentClient
import Foundation
import ServerControl
import ServiceCatalog

public struct AgentAutoBackupOperations: AutoBackupManaging {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    public func load() async throws -> AutoBackupSettings {
        let policy = try await mapping { try await client.getBackupSchedule() }
        return Self.settings(from: policy)
    }

    /// Writes a new schedule
    public func save(_ settings: AutoBackupSettings, passphrase: String? = nil) async throws {
        _ = try await mapping {
            try await client.setBackupSchedule(schedule: settings.schedule.wrapperArgument,
                                               retention: settings.retention,
                                               services: settings.services.sorted(),
                                               passphrase: passphrase ?? "")
        }
    }

    // MARK: - Destination

    public func loadDestination() async throws -> BackupDestinationState {
        let policy = try await mapping { try await client.getBackupSchedule() }
        return Self.destination(from: policy)
    }

    public func saveDestination(_ settings: BackupDestinationSettings, secret: String?) async throws {
        let destination: Gryonixnexusd_V1_BackupDestination = {
            var wire = Gryonixnexusd_V1_BackupDestination()
            wire.kind = Self.kind(settings.kind)
            wire.host = settings.host.trimmingCharacters(in: .whitespaces)
            wire.port = UInt32(max(settings.port, 0))
            wire.user = settings.user.trimmingCharacters(in: .whitespaces)
            wire.path = settings.path.trimmingCharacters(in: .whitespaces)
            wire.bucket = settings.bucket.trimmingCharacters(in: .whitespaces)
            wire.keep = UInt32(max(settings.keep, 0))
            return wire
        }()
        _ = try await mapping {
            try await client.setBackupDestination(destination, secret: secret ?? "")
        }
    }

    public func testDestination() async throws -> BackupDestinationTestResult {
        let answer = try await mapping { try await client.testBackupDestination() }
        return BackupDestinationTestResult(succeeded: answer.ok, detail: answer.detail)
    }

    // MARK: - USB drives

    public func loadDrives() async throws -> BackupDrivesState {
        let policy = try await mapping { try await client.getBackupSchedule() }
        return Self.drives(from: policy)
    }

    public func saveDrives(_ settings: BackupDriveSettings) async throws {
        var wire = Gryonixnexusd_V1_BackupDrives()
        wire.mode = switch settings.mode {
        case .both: .both
        case .local: .local
        case .drive: .drive
        }
        wire.encrypt = settings.encrypt
        wire.uuids = settings.uuids
        let request = wire
        _ = try await mapping { try await client.setBackupDrives(request) }
    }

    /// The policy's drive half; an older agent sends none
    static func drives(from policy: Gryonixnexusd_V1_BackupSchedulePolicy) -> BackupDrivesState {
        guard policy.hasDrives else { return BackupDrivesState(supported: false) }
        let wire = policy.drives
        let mode: BackupDriveSettings.Mode = switch wire.mode {
        case .local: .local
        case .drive: .drive
        default: .both
        }
        return BackupDrivesState(
            settings: BackupDriveSettings(mode: mode, encrypt: wire.encrypt, uuids: wire.uuids),
            statuses: wire.drives.map {
                BackupDriveStatus(uuid: $0.uuid, mounted: $0.mounted, sizeBytes: Int64($0.sizeBytes),
                                  freeBytes: Int64($0.freeBytes), mountPoint: $0.mountPoint)
            },
            lastCopy: wire.lastCopyAt > 0 ? Date(timeIntervalSince1970: TimeInterval(wire.lastCopyAt)) : nil,
            lastCopySucceeded: wire.lastCopyOk,
            lastError: wire.lastCopyError,
            hasPassphrase: wire.passphraseStored)
    }

    /// The policy's destination half, as the app's own type
    static func destination(from policy: Gryonixnexusd_V1_BackupSchedulePolicy)
        -> BackupDestinationState {
        var settings = BackupDestinationSettings()
        if policy.hasDestination {
            settings.kind = switch policy.destination.kind {
            case .ssh: .ssh
            case .s3: .s3
            default: .none
            }
            settings.host = policy.destination.host
            settings.port = policy.destination.port > 0 ? Int(policy.destination.port) : 22
            settings.user = policy.destination.user
            settings.path = policy.destination.path
            settings.bucket = policy.destination.bucket
            settings.keep = Int(policy.destination.keep)
        }
        return BackupDestinationState(
            settings: settings,
            publicKey: policy.destinationPublicKey,
            lastShipment: policy.lastShipmentAt > 0
                ? Date(timeIntervalSince1970: TimeInterval(policy.lastShipmentAt)) : nil,
            lastShipmentSucceeded: policy.lastShipmentOk,
            lastError: policy.lastShipmentError)
    }

    private static func kind(_ kind: BackupDestinationSettings.Kind)
        -> Gryonixnexusd_V1_BackupDestinationKind {
        switch kind {
        case .none: return .none
        case .ssh: return .ssh
        case .s3: return .s3
        }
    }

    private static func settings(from policy: Gryonixnexusd_V1_BackupSchedulePolicy) -> AutoBackupSettings {
        AutoBackupSettings(schedule: CommandCatalog.Backups.Schedule(wrapperArgument: policy.schedule),
                           retention: policy.retention > 0 ? Int(policy.retention) : 7,
                           services: Set(policy.services))
    }

    private func mapping<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        do {
            guard let gate else { return try await body() }
            return try await gate.withSlot(body)
        } catch let error as AgentError {
            guard case .rpc(_, let message) = error, !message.isEmpty else { throw error }
            throw ServerControlError.commandFailed(command: "backup schedule", exitCode: nil, stderr: message)
        }
    }
}
