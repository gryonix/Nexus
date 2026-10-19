import Foundation
import ServiceCatalog

public struct AutoUpdateSettings: Sendable, Hashable {
    public var schedule: CommandCatalog.Backups.Schedule
    /// Services the timer updates, by `ServiceID` raw value
    public var services: Set<String>

    public init(schedule: CommandCatalog.Backups.Schedule = .off,
                services: Set<String> = []) {
        self.schedule = schedule
        self.services = services
    }

    public var isOn: Bool { schedule != .off }
}

public struct ServiceUpdateReport: Sendable, Hashable {
    public let service: ServiceID
    public let status: ServiceUpdateStatus

    public init(service: ServiceID, status: ServiceUpdateStatus) {
        self.service = service
        self.status = status
    }
}

public struct ServiceUpdateRunRecord: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        case updated
        case rolledBack(reason: String)
        case failed(reason: String)
    }
    public let service: ServiceID
    public let outcome: Outcome

    public init(service: ServiceID, outcome: Outcome) {
        self.service = service
        self.outcome = outcome
    }
}

public struct ServiceUpdateRunLog: Sendable, Hashable {
    public let lastRun: Date?
    public let records: [ServiceUpdateRunRecord]

    public init(lastRun: Date?, records: [ServiceUpdateRunRecord]) {
        self.lastRun = lastRun
        self.records = records
    }

    public var isEmpty: Bool { lastRun == nil && records.isEmpty }
}

/// Reads update status and drives the update wrapper
public struct ServiceUpdateOperations: ServiceUpdateManaging, Sendable {
    private let runner: any SSHCommandRunner
    private let deployment: Deployment

    public init(runner: any SSHCommandRunner, deployment: Deployment) {
        self.runner = runner
        self.deployment = deployment
    }

    private var hosts: [SSHHostID] { deployment.workerHosts }

    /// Asks what has moved
    public func check() async throws -> [ServiceUpdateReport] {
        var outputs: [String] = []
        for host in hosts {
            let result = try await runner.run(CommandCatalog.Updates.check(nil), on: host,
                                              timeout: deployment.timeouts.duration(for: .long))
            outputs.append(result.stdout)
        }
        return Self.parseCheck(outputs.joined(separator: "\n"))
    }

    @discardableResult
    public func run(_ service: ServiceID,
                    onChunk: @escaping @Sendable (String) -> Void = { _ in }) async throws -> ServiceUpdateRunRecord {
        let command = CommandCatalog.Updates.run(service.rawValue)
        let accumulated = OutputBox()
        try await DetachedJobs.run(command, kind: .update, subject: service.rawValue,
                                   on: deployment.host(running: service), runner: runner,
                                   quickTimeout: deployment.timeouts.duration(for: .quick),
                                   runTimeout: deployment.timeouts.duration(for: .long)) { text in
            accumulated.append(text)
            onChunk(text)
        }
        let output = ANSIStripper.strip(accumulated.text)
        guard let record = Self.parseStatus(output).records.first else {
            throw ServerControlError.commandFailure(command: command, exitCode: nil,
                                                    stderr: OutputTail.tail(output))
        }
        return record
    }

    /// Parses the wrapper's markers
    public static func parseCheck(_ output: String) -> [ServiceUpdateReport] {
        var available: [ServiceID: [String]] = [:]
        var settled: [ServiceID: ServiceUpdateStatus] = [:]
        var order: [ServiceID] = []

        func note(_ id: ServiceID) {
            if !order.contains(id) { order.append(id) }
        }

        for rawLine in output.split(separator: "\n") {
            let fields = rawLine.split(separator: " ", omittingEmptySubsequences: true)
                .map(String.init)
            guard fields.count >= 2 else { continue }
            let id = ServiceID(rawValue: fields[1])
            switch fields[0] {
            case CommandCatalog.Updates.availableMarker:
                guard fields.count >= 3 else { continue }
                note(id)
                available[id, default: []].append(fields[2])
            case CommandCatalog.Updates.currentMarker:
                note(id)
                settled[id] = .current
            case CommandCatalog.Updates.unknownMarker:
                note(id)
                settled[id] = .unknown
            default:
                continue
            }
        }

        return order.map { id in
            if let images = available[id] {
                return ServiceUpdateReport(service: id, status: .available(images: images))
            }
            return ServiceUpdateReport(service: id, status: settled[id] ?? .unknown)
        }
    }

    public func loadSchedule() async throws -> AutoUpdateSettings {
        var found: [AutoUpdateSettings] = []
        for host in hosts {
            let result = try await runner.run(CommandCatalog.Updates.readSchedule, on: host,
                                              timeout: deployment.timeouts.duration(for: .quick))
            found.append(Self.parseSchedule(result.stdout))
        }
        return Self.merged(found)
    }

    /// One answer out of one per machine
    static func merged(_ settings: [AutoUpdateSettings]) -> AutoUpdateSettings {
        AutoUpdateSettings(
            schedule: settings.first(where: { $0.schedule != .off })?.schedule ?? .off,
            services: settings.reduce(into: Set<String>()) { $0.formUnion($1.services) })
    }

    /// `KEY=value` lines, the same shape the backup schedule uses
    public static func parseSchedule(_ text: String) -> AutoUpdateSettings {
        var schedule = CommandCatalog.Backups.Schedule.off
        var services: Set<String> = []
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<separator])
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            switch key {
            case "SCHEDULE":
                schedule = CommandCatalog.Backups.Schedule(wrapperArgument: value)
            case "SERVICES":
                services = Set(value.split(separator: " ").map(String.init))
            default:
                continue
            }
        }
        return AutoUpdateSettings(schedule: schedule, services: services)
    }

    /// What the last scheduled run did
    public func loadStatus() async throws -> ServiceUpdateRunLog {
        var logs: [ServiceUpdateRunLog] = []
        for host in hosts {
            let result = try await runner.run(CommandCatalog.Updates.readStatus, on: host,
                                              timeout: deployment.timeouts.duration(for: .quick))
            logs.append(Self.parseStatus(result.stdout))
        }
        return ServiceUpdateRunLog(lastRun: logs.compactMap(\.lastRun).max(),
                                   records: logs.flatMap(\.records))
    }

    /// Parses the status file's marker lines only, in file order
    public static func parseStatus(_ text: String) -> ServiceUpdateRunLog {
        var lastRun: Date?
        var records: [ServiceUpdateRunRecord] = []

        for rawLine in text.split(separator: "\n") {
            let fields = rawLine.split(separator: " ", omittingEmptySubsequences: true)
                .map(String.init)
            guard let marker = fields.first else { continue }
            switch marker {
            case "last-run":
                guard fields.count >= 2 else { continue }
                lastRun = ISO8601DateFormatter().date(from: fields[1])
            case CommandCatalog.Updates.updatedMarker:
                guard fields.count >= 2 else { continue }
                records.append(ServiceUpdateRunRecord(service: ServiceID(rawValue: fields[1]),
                                                       outcome: .updated))
            case CommandCatalog.Updates.rolledBackMarker:
                guard fields.count >= 2 else { continue }
                let reason = fields.dropFirst(2).joined(separator: " ")
                records.append(ServiceUpdateRunRecord(service: ServiceID(rawValue: fields[1]),
                                                       outcome: .rolledBack(reason: reason)))
            case CommandCatalog.Updates.failedMarker:
                guard fields.count >= 2 else { continue }
                let reason = fields.dropFirst(2).joined(separator: " ")
                records.append(ServiceUpdateRunRecord(service: ServiceID(rawValue: fields[1]),
                                                       outcome: .failed(reason: reason)))
            default:
                continue
            }
        }

        return ServiceUpdateRunLog(lastRun: lastRun, records: records)
    }

    public func save(_ settings: AutoUpdateSettings) async throws {
        for host in hosts { try await save(settings, on: host) }
    }

    private func save(_ settings: AutoUpdateSettings, on host: SSHHostID) async throws {
        let command = CommandCatalog.Updates.setSchedule(settings.schedule,
                                                         services: settings.services.sorted())
        let result = try await runner.run(command, on: host,
                                          timeout: deployment.timeouts.duration(for: .quick))
        guard result.succeeded else {
            throw ServerControlError.commandFailure(command: command, exitCode: result.exitCode,
                                                    stderr: result.stderr)
        }
        guard result.stdout.contains(CommandCatalog.Updates.doneMarker) else {
            throw ServerControlError.commandFailure(command: command, exitCode: nil,
                                                    stderr: OutputTail.tail(result.stdout))
        }
    }
}
