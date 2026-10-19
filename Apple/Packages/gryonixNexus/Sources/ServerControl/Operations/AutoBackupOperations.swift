import Foundation
import ServiceCatalog

/// The unattended backup schedule as it exists on the server
public struct AutoBackupSettings: Sendable, Hashable {
    public var schedule: CommandCatalog.Backups.Schedule
    /// How many backups of each service to keep
    public var retention: Int
    /// Services the timer backs up, by ServiceID raw value
    public var services: Set<String>

    public init(schedule: CommandCatalog.Backups.Schedule = .off, retention: Int = 7,
                services: Set<String> = []) {
        self.schedule = schedule
        self.retention = retention
        self.services = services
    }

    public var isOn: Bool { schedule != .off }
}

public protocol AutoBackupManaging: Sendable {
    /// The stored schedule, or "off" when unset or unreadable
    func load() async throws -> AutoBackupSettings

    /// Writes a new schedule
    func save(_ settings: AutoBackupSettings, passphrase: String?) async throws

    func loadDestination() async throws -> BackupDestinationState

    func saveDestination(_ settings: BackupDestinationSettings, secret: String?) async throws

    func testDestination() async throws -> BackupDestinationTestResult

    /// USB drive settings and state from the services machine
    func loadDrives() async throws -> BackupDrivesState

    func saveDrives(_ settings: BackupDriveSettings) async throws
}

/// Which implementation a deployment's BACKUP SCHEDULE goes through
public enum AutoBackupRouting {
    public static func route(usesAgent: Bool, agentTransportAvailable: Bool) -> ServiceControlRoute {
        ServiceControlRouting.route(usesAgent: usesAgent,
                                    agentTransportAvailable: agentTransportAvailable)
    }
}

public struct AutoBackupOperations: AutoBackupManaging {
    private let runner: any SSHCommandRunner
    private let deployment: Deployment

    public init(runner: any SSHCommandRunner, deployment: Deployment) {
        self.runner = runner
        self.deployment = deployment
    }

    private var hosts: [SSHHostID] { deployment.workerHosts }

    public func load() async throws -> AutoBackupSettings {
        var found: [AutoBackupSettings] = []
        for host in hosts {
            let result = try await runner.run(CommandCatalog.Backups.readSchedule, on: host,
                                              timeout: deployment.timeouts.duration(for: .quick))
            found.append(Self.parse(result.stdout))
        }
        return Self.merged(found)
    }

    /// One answer out of one per machine
    static func merged(_ settings: [AutoBackupSettings]) -> AutoBackupSettings {
        AutoBackupSettings(
            schedule: settings.first(where: { $0.schedule != .off })?.schedule ?? .off,
            retention: settings.map(\.retention).max() ?? AutoBackupSettings().retention,
            services: settings.reduce(into: Set<String>()) { $0.formUnion($1.services) })
    }

    /// Writes the schedule
    public func save(_ settings: AutoBackupSettings, passphrase: String? = nil) async throws {
        for host in hosts { try await save(settings, passphrase: passphrase, on: host) }
    }

    /// One machine's copy
    private func save(_ settings: AutoBackupSettings, passphrase: String?,
                      on host: SSHHostID) async throws {
        if let passphrase, !passphrase.isEmpty {
            let result = try await runner.run(CommandCatalog.Backups.setPassphrase, feeding: passphrase,
                                              on: host, timeout: deployment.timeouts.duration(for: .quick))
            guard result.succeeded else {
                throw ServerControlError.commandFailure(command: "set backup passphrase",
                                                        exitCode: result.exitCode, stderr: "")
            }
        }
        let command = CommandCatalog.Backups.setSchedule(settings.schedule,
                                                         retention: settings.retention,
                                                         services: settings.services.sorted())
        let result = try await runner.run(command, on: host,
                                          timeout: deployment.timeouts.duration(for: .quick))
        guard result.succeeded else {
            throw ServerControlError.commandFailure(command: command, exitCode: result.exitCode,
                                                    stderr: result.stderr)
        }
        guard result.stdout.contains(CommandCatalog.Backups.controlDoneMarker) else {
            throw ServerControlError.commandFailure(command: command, exitCode: nil,
                                                    stderr: OutputTail.tail(result.stdout))
        }
    }

    // MARK: - Destination

    public func loadDestination() async throws -> BackupDestinationState {
        guard let host = hosts.first else { return BackupDestinationState() }
        let result = try await runner.run(CommandCatalog.Backups.showDestination, on: host,
                                          timeout: deployment.timeouts.duration(for: .quick))
        guard result.succeeded else { return BackupDestinationState() }
        return BackupDestinationParsing.parse(result.stdout)
    }

    public func saveDestination(_ settings: BackupDestinationSettings, secret: String?) async throws {
        for host in hosts { try await saveDestination(settings, secret: secret, on: host) }
    }

    private func saveDestination(_ settings: BackupDestinationSettings, secret: String?,
                                 on host: SSHHostID) async throws {
        let command = CommandCatalog.Backups.setDestination(
            kind: settings.kind.rawValue,
            host: settings.host.trimmingCharacters(in: .whitespaces),
            port: settings.port,
            user: settings.user.trimmingCharacters(in: .whitespaces),
            path: settings.path.trimmingCharacters(in: .whitespaces),
            bucket: settings.bucket.trimmingCharacters(in: .whitespaces),
            keep: settings.keep)
        let timeout = deployment.timeouts.duration(for: .quick)
        let result = if let secret, !secret.isEmpty {
            try await runner.run(command, feeding: secret, on: host, timeout: timeout)
        } else {
            try await runner.run(command, on: host, timeout: timeout)
        }
        guard result.succeeded else {
            if result.stderr.contains(Self.unsupportedAction) {
                throw ServerControlError.notConfigured(
                    "this server's backup wrapper is older than backup destinations — run Repair server on it, then set the destination again")
            }
            throw ServerControlError.commandFailure(command: "set backup destination",
                                                    exitCode: result.exitCode,
                                                    stderr: result.stderr)
        }
    }

    public func testDestination() async throws -> BackupDestinationTestResult {
        guard let host = hosts.first else {
            return BackupDestinationTestResult(succeeded: false, detail: "")
        }
        let result = try await runner.run(CommandCatalog.Backups.testDestination, on: host,
                                          timeout: deployment.timeouts.duration(for: .long))
        if result.stderr.contains(Self.unsupportedAction) {
            return BackupDestinationTestResult(
                succeeded: false,
                detail: "this server's backup wrapper is older than backup destinations — run Repair server on it first")
        }
        return Self.parseTest(result.stdout, fallback: result.stderr)
    }

    static let unsupportedAction = "unsupported action:"

    // MARK: - USB drives

    public func loadDrives() async throws -> BackupDrivesState {
        guard let host = hosts.first else { return BackupDrivesState(supported: false) }
        let result = try await runner.run(CommandCatalog.Backups.showDrives, on: host,
                                          timeout: deployment.timeouts.duration(for: .quick))
        guard result.succeeded else {
            if result.stderr.contains(Self.unsupportedAction) { return BackupDrivesState(supported: false) }
            throw ServerControlError.commandFailure(command: "show backup drives", exitCode: result.exitCode,
                                                    stderr: result.stderr)
        }
        return BackupDrivesParsing.parse(result.stdout)
    }

    public func saveDrives(_ settings: BackupDriveSettings) async throws {
        guard let host = hosts.first else { return }
        let command = CommandCatalog.Backups.setDrives(mode: settings.mode.rawValue, encrypt: settings.encrypt,
                                                       uuids: settings.uuids)
        let result = try await runner.run(command, on: host, timeout: deployment.timeouts.duration(for: .quick))
        guard result.succeeded else {
            if result.stderr.contains(Self.unsupportedAction) {
                throw ServerControlError.notConfigured(
                    "this server's backup wrapper is older than USB drives — run Repair server on it first")
            }
            throw ServerControlError.commandFailure(command: "set backup drives", exitCode: result.exitCode,
                                                    stderr: result.stderr)
        }
    }

    static func parseTest(_ output: String, fallback: String = "") -> BackupDestinationTestResult {
        guard let line = output.split(separator: "\n").last(where: {
            $0.hasPrefix(CommandCatalog.Backups.destinationTestMarker)
        }) else {
            return BackupDestinationTestResult(succeeded: false,
                                               detail: OutputTail.tail(fallback))
        }
        let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
        let ok = parts.count > 1 && parts[1] == "1"
        let detail = parts.count > 2 ? parts[2] : ""
        return BackupDestinationTestResult(succeeded: ok, detail: detail)
    }

    /// Parses the wrapper's shell-style config
    public static func parse(_ output: String) -> AutoBackupSettings {
        var settings = AutoBackupSettings()
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
            switch parts[0].trimmingCharacters(in: .whitespaces) {
            case "SCHEDULE":
                settings.schedule = CommandCatalog.Backups.Schedule(wrapperArgument: value)
            case "RETENTION":
                if let retention = Int(value), retention >= 1 { settings.retention = retention }
            case "SERVICES":
                settings.services = Set(value.split(separator: " ").map(String.init))
            default:
                continue
            }
        }
        return settings
    }
}
