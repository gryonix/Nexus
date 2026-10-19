import AgentClient
import Foundation

public struct ContainerGroup: Sendable, Identifiable, Hashable {
    public let key: String
    public var id: String { key }
    public let isComposeProject: Bool
    public let displayName: String
    public let derivedName: String
    public let isRenamed: Bool
    public let serviceID: String?
    public let status: ContainerGroupStatus
    public let containers: [ContainerSummary]
    public let configFiles: [String]

    public init(key: String, isComposeProject: Bool, displayName: String,
                derivedName: String, isRenamed: Bool, serviceID: String?,
                status: ContainerGroupStatus, containers: [ContainerSummary],
                configFiles: [String]) {
        self.key = key
        self.isComposeProject = isComposeProject
        self.displayName = displayName
        self.derivedName = derivedName
        self.isRenamed = isRenamed
        self.serviceID = serviceID
        self.status = status
        self.containers = containers
        self.configFiles = configFiles
    }
}

/// How much of a group is up
public enum ContainerGroupStatus: Sendable, Hashable {
    case running
    case stopped
    case partial
    case error
    case unknown
}

/// One container inside a group
public struct ContainerSummary: Sendable, Identifiable, Hashable {
    public let name: String
    public var id: String { name }
    public let image: String
    /// "running", "exited", … — the engine's own word, not a parsed one
    public let state: String
    public let health: String
    public let ports: String

    public init(name: String, image: String, state: String, health: String, ports: String) {
        self.name = name
        self.image = image
        self.state = state
        self.health = health
        self.ports = ports
    }
}

public struct ContainerInventory: Sendable {
    public let groups: [ContainerGroup]
    /// Non-nil when the host has no reachable container engine
    public let unavailableReason: String?

    public init(groups: [ContainerGroup], unavailableReason: String?) {
        self.groups = groups
        self.unavailableReason = unavailableReason
    }
}

/// Everything about one container the list does not carry
public struct ContainerDetail: Sendable {
    public let container: ContainerSummary
    public let createdAt: String
    public let restartPolicy: String
    /// Empty for a standalone container
    public let composeProject: String
    public let composeService: String
    public let command: String
    public let environment: [ContainerEnvironmentVariable]
    public let mounts: [ContainerMount]

    public init(container: ContainerSummary, createdAt: String, restartPolicy: String,
                composeProject: String, composeService: String, command: String,
                environment: [ContainerEnvironmentVariable], mounts: [ContainerMount]) {
        self.container = container
        self.createdAt = createdAt
        self.restartPolicy = restartPolicy
        self.composeProject = composeProject
        self.composeService = composeService
        self.command = command
        self.environment = environment
        self.mounts = mounts
    }
}

public struct ContainerMount: Sendable, Identifiable, Hashable {
    /// The host path
    public let source: String
    public let destination: String
    public let isReadOnly: Bool
    /// "bind" | "volume", as the engine reports it
    public let kind: String
    /// A named volume's name, empty for a bind mount
    public let volumeName: String
    public var displaySource: String { volumeName.isEmpty ? source : volumeName }
    public var id: String { "\(source)→\(destination)" }

    public init(source: String, destination: String, isReadOnly: Bool, kind: String,
                volumeName: String = "") {
        self.source = source
        self.destination = destination
        self.isReadOnly = isReadOnly
        self.kind = kind
        self.volumeName = volumeName
    }
}

/// One environment variable of a container
public struct ContainerEnvironmentVariable: Sendable, Identifiable, Hashable {
    public let key: String
    public let value: String
    public let isSensitive: Bool
    public var id: String { key }

    public init(key: String, value: String, isSensitive: Bool) {
        self.key = key
        self.value = value
        self.isSensitive = isSensitive
    }
}

/// What a backup of one group would archive
public struct ContainerBackupPlan: Sendable, Hashable {
    public let key: String
    public let paths: [String]
    public let volumes: [String]
    public let databases: [ContainerDatabaseDump]
    /// Stop the stack while archiving
    public let stopWhileArchiving: Bool
    public let isDetected: Bool
    /// What the detection concluded, in the server's words
    public let notes: [String]

    public init(key: String, paths: [String], volumes: [String],
                databases: [ContainerDatabaseDump], stopWhileArchiving: Bool,
                isDetected: Bool, notes: [String]) {
        self.key = key
        self.paths = paths
        self.volumes = volumes
        self.databases = databases
        self.stopWhileArchiving = stopWhileArchiving
        self.isDetected = isDetected
        self.notes = notes
    }
}

public struct ContainerDatabaseDump: Sendable, Hashable, Identifiable {
    public let container: String
    /// "postgres", "mysql", … as the agent classified the image
    public let engine: String
    public let database: String
    public let user: String
    public let passwordEnvName: String
    public var id: String { "\(container)/\(database)" }

    let wireEngine: Gryonixnexusd_V1_ContainerDatabaseEngine

    public init(container: String, engine: String, database: String, user: String,
                passwordEnvName: String) {
        self.init(container: container, engine: engine, database: database,
                  user: user, passwordEnvName: passwordEnvName, wireEngine: .unspecified)
    }

    init(container: String, engine: String, database: String, user: String,
         passwordEnvName: String, wireEngine: Gryonixnexusd_V1_ContainerDatabaseEngine) {
        self.container = container
        self.engine = engine
        self.database = database
        self.user = user
        self.passwordEnvName = passwordEnvName
        self.wireEngine = wireEngine
    }
}

@available(macOS 15.0, *)
public struct AgentContainerOperations: Sendable {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    public func inventory() async throws -> ContainerInventory {
        let client = self.client
        return Self.inventory(from: try await run { try await client.listContainers() })
    }

    @discardableResult
    public func rename(key: String, to displayName: String) async throws -> ContainerInventory {
        let client = self.client
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.inventory(from: try await run {
            try await client.setContainerGroupName(key: key, displayName: trimmed)
        })
    }

    public func control(key: String, action: ContainerAction)
    -> AsyncThrowingStream<ContainerOperationEvent, Error> {
        let raw = client.controlContainerGroup(key: key, action: action.wire)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in raw {
                        continuation.yield(ContainerOperationEvent(event))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Follows one group's containers
    public func logs(key: String, tail: UInt32 = 0)
    -> AsyncThrowingStream<ContainerLogLine, Error> {
        let raw = client.containerGroupLogs(key: key, tail: tail)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in raw {
                        continuation.yield(ContainerLogLine(container: line.container,
                                                            text: line.text,
                                                            stream: line.stream))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Everything about one container the list does not carry
    public func inspect(container name: String) async throws -> ContainerDetail {
        let client = self.client
        let detail = try await run { try await client.inspectContainer(name: name) }
        return ContainerDetail(
            container: ContainerSummary(detail.container),
            createdAt: detail.createdAt,
            restartPolicy: detail.restartPolicy,
            composeProject: detail.composeProject,
            composeService: detail.composeService,
            command: detail.command,
            environment: detail.env.map {
                ContainerEnvironmentVariable(key: $0.key, value: $0.value,
                                             isSensitive: $0.sensitive)
            },
            mounts: detail.mounts.map {
                ContainerMount(source: $0.source, destination: $0.destination,
                               isReadOnly: $0.mode == "ro", kind: $0.kind,
                               volumeName: $0.name)
            })
    }

    public func backupPlan(key: String) async throws -> ContainerBackupPlan {
        let client = self.client
        return ContainerBackupPlan(try await run { try await client.containerBackupPlan(key: key) })
    }

    @discardableResult
    public func setBackupPlan(key: String, plan: ContainerBackupPlan?)
    async throws -> ContainerBackupPlan {
        let client = self.client
        let wire = plan.map { $0.wire(key: key) }
        return ContainerBackupPlan(try await run {
            try await client.setContainerBackupPlan(key: key, plan: wire)
        })
    }

    /// Runs the plan, streaming what it does
    public func runBackup(key: String) -> AsyncThrowingStream<ContainerBackupRunEvent, Error> {
        let raw = client.runContainerGroupBackup(key: key)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in raw {
                        continuation.yield(ContainerBackupRunEvent(event))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// What removing this group would delete, for these toggles
    public func removalPreview(key: String, purgeData: Bool, purgeBackups: Bool)
    async throws -> ContainerRemovalPreview {
        let client = self.client
        return ContainerRemovalPreview(try await run {
            try await client.previewContainerGroupRemoval(key: key,
                                                          purgeData: purgeData,
                                                          purgeBackups: purgeBackups)
        })
    }

    public func remove(key: String, purgeData: Bool, purgeBackups: Bool)
    -> AsyncThrowingStream<ContainerRemovalEvent, Error> {
        let raw = client.removeContainerGroup(key: key, purgeData: purgeData, purgeBackups: purgeBackups)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in raw {
                        continuation.yield(ContainerRemovalEvent(event))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public static func namesNothingToArchive(_ error: Error) -> Bool {
        guard case .rpc(_, let message) = error as? AgentError ?? .transport("") else { return false }
        return message.hasPrefix("nothing_to_archive:")
    }

    public func update(key: String, skipBackup: Bool = false)
    -> AsyncThrowingStream<ContainerUpdateEvent, Error> {
        let raw = client.updateContainerGroup(key: key, skipBackup: skipBackup)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in raw {
                        continuation.yield(ContainerUpdateEvent(event))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func backupSchedule(key: String) async throws -> ContainerBackupSchedule {
        let client = self.client
        return ContainerBackupSchedule(try await run { try await client.containerBackupSchedule(key: key) })
    }

    /// Sets it, or switches it off with `nil`
    @discardableResult
    public func setBackupSchedule(key: String, every schedule: ContainerBackupCadence?)
    async throws -> ContainerBackupSchedule {
        let client = self.client
        let wire = schedule?.wire ?? ""
        return ContainerBackupSchedule(try await run {
            try await client.setContainerBackupSchedule(key: key, schedule: wire)
        })
    }

    /// The archives one foreign group's backups have left, newest first
    public func backups(key: String) async throws -> ContainerBackupListing {
        let client = self.client
        let wire = try await run { try await client.containerGroupBackups(key: key) }
        return ContainerBackupListing(
            key: wire.key,
            directory: wire.directory,
            archives: wire.archives.map(ContainerArchive.init))
    }

    private func run<T: Sendable>(_ call: @escaping @Sendable () async throws -> T) async throws -> T {
        if let gate { return try await gate.withSlot(call) }
        return try await call()
    }

    private static func inventory(from wire: Gryonixnexusd_V1_ContainerInventory) -> ContainerInventory {
        ContainerInventory(
            groups: wire.groups.map(ContainerGroup.init),
            unavailableReason: wire.unavailableReason.isEmpty ? nil : wire.unavailableReason)
    }
}

/// The three verbs, in the app's vocabulary
public enum ContainerAction: Sendable, Hashable {
    case start
    case stop
    case restart

    var wire: Gryonixnexusd_V1_ServiceAction {
        switch self {
        case .start: return .start
        case .stop: return .stop
        case .restart: return .restart
        }
    }
}

public struct ContainerLogLine: Sendable, Hashable {
    public let container: String
    public let text: String
    /// "stdout" | "stderr"
    public let stream: String

    public init(container: String, text: String, stream: String) {
        self.container = container
        self.text = text
        self.stream = stream
    }
}

/// What a control run reports as it goes
public struct ContainerOperationEvent: Sendable {
    public enum Phase: Sendable, Hashable {
        case started, progress, completed, unknown

        init(_ wire: Gryonixnexusd_V1_ServiceOperationPhase) {
            switch wire {
            case .started: self = .started
            case .progress: self = .progress
            case .completed: self = .completed
            default: self = .unknown
            }
        }
    }

    public let phase: Phase
    public let key: String
    /// PROGRESS only
    public let text: String
    public let containers: [String]
    public let group: ContainerGroup?

    init(_ wire: Gryonixnexusd_V1_ContainerOperationEvent) {
        phase = Phase(wire.phase)
        key = wire.key
        text = wire.text
        containers = wire.containers
        group = wire.hasGroup ? ContainerGroup(wire.group) : nil
    }
}

private extension ContainerSummary {
    init(_ wire: Gryonixnexusd_V1_Container) {
        self.init(name: wire.name, image: wire.image, state: wire.state,
                  health: wire.health, ports: wire.ports)
    }
}

private extension ContainerGroup {
    init(_ wire: Gryonixnexusd_V1_ContainerGroup) {
        let status: ContainerGroupStatus
        switch wire.status {
        case .running: status = .running
        case .stopped: status = .stopped
        case .partial: status = .partial
        case .error: status = .error
        default: status = .unknown
        }
        self.init(key: wire.key,
                  isComposeProject: wire.kind == .composeProject,
                  displayName: wire.displayName,
                  derivedName: wire.derivedName,
                  isRenamed: wire.renamed,
                  serviceID: wire.serviceID.isEmpty ? nil : wire.serviceID,
                  status: status,
                  containers: wire.containers.map(ContainerSummary.init),
                  configFiles: wire.configFiles)
    }
}

private extension ContainerBackupPlan {
    init(_ wire: Gryonixnexusd_V1_ContainerBackupPlan) {
        self.init(key: wire.key,
                  paths: wire.paths,
                  volumes: wire.volumes,
                  databases: wire.databases.map {
                      ContainerDatabaseDump(container: $0.container,
                                            engine: Self.engineName($0.engine),
                                            database: $0.database,
                                            user: $0.user,
                                            passwordEnvName: $0.passwordEnv,
                                            wireEngine: $0.engine)
                  },
                  stopWhileArchiving: wire.stopWhileArchiving,
                  isDetected: wire.detected,
                  notes: wire.notes)
    }

    static func engineName(_ engine: Gryonixnexusd_V1_ContainerDatabaseEngine) -> String {
        String(describing: engine)
    }

    /// Back to the wire, for a correction
    func wire(key: String) -> Gryonixnexusd_V1_ContainerBackupPlan {
        var out = Gryonixnexusd_V1_ContainerBackupPlan()
        out.key = key
        out.paths = paths
        out.volumes = volumes
        out.databases = databases.map { database in
            var dump = Gryonixnexusd_V1_ContainerDatabaseDump()
            dump.container = database.container
            dump.engine = database.wireEngine
            dump.database = database.database
            dump.user = database.user
            dump.passwordEnv = database.passwordEnvName
            return dump
        }
        out.stopWhileArchiving = stopWhileArchiving
        return out
    }
}

// ─────────────────────── running, removing, updating ───────────────────────

public enum ContainerBackupCadence: String, Sendable, Hashable, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly

    public var id: String { rawValue }
    var wire: String { rawValue }

    init?(wire: String) {
        guard let value = ContainerBackupCadence(rawValue: wire) else { return nil }
        self = value
    }
}

public struct ContainerBackupSchedule: Sendable, Hashable {
    public let key: String
    /// Nil when the group is not scheduled
    public let cadence: ContainerBackupCadence?
    /// What the last scheduled run did, in the server's words
    public let lastOutcome: String
    public let lastRun: Date?

    public var isEnabled: Bool { cadence != nil }

    public init(key: String, cadence: ContainerBackupCadence?, lastOutcome: String, lastRun: Date?) {
        self.key = key
        self.cadence = cadence
        self.lastOutcome = lastOutcome
        self.lastRun = lastRun
    }

    init(_ wire: Gryonixnexusd_V1_ContainerBackupSchedule) {
        self.key = wire.key
        self.cadence = ContainerBackupCadence(wire: wire.schedule)
        self.lastOutcome = wire.lastOutcome
        self.lastRun = Double(wire.lastRun).map { Date(timeIntervalSince1970: $0) }
    }
}

/// One event from a backup run
public struct ContainerBackupRunEvent: Sendable {
    public let phase: ContainerOperationEvent.Phase
    public let key: String
    public let text: String
    public let stream: String
    public let plan: ContainerBackupPlan?
    public let archive: ContainerArchive?
    /// COMPLETED only
    public let group: ContainerGroup?

    init(_ wire: Gryonixnexusd_V1_ContainerBackupEvent) {
        self.phase = ContainerOperationEvent.Phase(wire.phase)
        self.key = wire.key
        self.text = wire.text
        self.stream = wire.stream
        self.plan = wire.hasPlan ? ContainerBackupPlan(wire.plan) : nil
        self.archive = wire.hasArchive ? ContainerArchive(wire.archive) : nil
        self.group = wire.hasGroup ? ContainerGroup(wire.group) : nil
    }
}

/// One archive on the server
public struct ContainerBackupListing: Sendable, Hashable {
    public let key: String
    public let directory: String
    public let archives: [ContainerArchive]

    public init(key: String, directory: String, archives: [ContainerArchive]) {
        self.key = key
        self.directory = directory
        self.archives = archives
    }
}

public struct ContainerArchive: Sendable, Hashable {
    public let name: String
    public let path: String
    public let sizeBytes: Int64
    public let modifiedAt: Date?

    public init(name: String, path: String, sizeBytes: Int64, modifiedAt: Date?) {
        self.name = name
        self.path = path
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
    }

    init(_ wire: Gryonixnexusd_V1_BackupArchive) {
        self.name = wire.name
        self.path = wire.path
        self.sizeBytes = wire.sizeBytes
        self.modifiedAt = wire.modifiedAt > 0
            ? Date(timeIntervalSince1970: Double(wire.modifiedAt) / 1000)
            : nil
    }
}

public struct ContainerRemovalPreview: Sendable, Hashable {
    /// Always removed
    public let containers: [String]
    /// Removed only with `purgeData`
    public let volumes: [String]
    public let paths: [String]
    /// Removed only with `purgeBackups`
    public let backupPaths: [String]
    public let notes: [String]

    public var isEmpty: Bool {
        containers.isEmpty && volumes.isEmpty && paths.isEmpty && backupPaths.isEmpty
    }

    public init(containers: [String], volumes: [String], paths: [String],
                backupPaths: [String], notes: [String]) {
        self.containers = containers
        self.volumes = volumes
        self.paths = paths
        self.backupPaths = backupPaths
        self.notes = notes
    }

    init(_ wire: Gryonixnexusd_V1_ContainerRemovalPreview) {
        self.init(containers: wire.containers, volumes: wire.volumes, paths: wire.paths,
                  backupPaths: wire.backupPaths, notes: wire.notes)
    }
}

public struct ContainerRemovalEvent: Sendable {
    public let phase: ContainerOperationEvent.Phase
    public let key: String
    public let text: String
    public let stream: String
    /// STARTED only
    public let removing: ContainerRemovalPreview?
    /// COMPLETED only
    public let group: ContainerGroup?

    init(_ wire: Gryonixnexusd_V1_ContainerRemovalEvent) {
        self.phase = ContainerOperationEvent.Phase(wire.phase)
        self.key = wire.key
        self.text = wire.text
        self.stream = wire.stream
        self.removing = wire.hasRemoving ? ContainerRemovalPreview(wire.removing) : nil
        self.group = wire.hasGroup ? ContainerGroup(wire.group) : nil
    }
}

public struct ContainerUpdateEvent: Sendable {
    public let phase: ContainerOperationEvent.Phase
    public let key: String
    public let text: String
    public let stream: String
    public let previousImages: [String: String]
    /// COMPLETED only
    public let didRollBack: Bool
    public let wasAlreadyCurrent: Bool
    public let group: ContainerGroup?

    init(_ wire: Gryonixnexusd_V1_ContainerUpdateEvent) {
        self.phase = ContainerOperationEvent.Phase(wire.phase)
        self.key = wire.key
        self.text = wire.text
        self.stream = wire.stream
        self.previousImages = wire.previousImages
        self.didRollBack = wire.rolledBack
        self.wasAlreadyCurrent = wire.alreadyCurrent
        self.group = wire.hasGroup ? ContainerGroup(wire.group) : nil
    }
}
