import AgentControl
import ServiceCatalog

@available(macOS 15.0, *)
protocol VPNClientManaging: Sendable {
    func list(protocol id: ServiceID) async throws -> [VPNClientDevice]
    @discardableResult
    func add(protocol id: ServiceID, named name: String, dns: [String]) async throws -> [VPNClientDevice]
    @discardableResult
    func setDNS(protocol id: ServiceID, clientID: String, dns: [String]) async throws -> [VPNClientDevice]
    func defaultDNS() async throws -> VPNDNSDefaults
    @discardableResult
    func setDefaultDNS(_ dns: [String]) async throws -> VPNDNSDefaults
    func dnsPriority() async throws -> VPNDNSPriority
    @discardableResult
    func setDNSPriority(_ resolvers: [String]) async throws -> VPNDNSPriority
    @discardableResult
    func remove(protocol id: ServiceID, clientID: String) async throws -> [VPNClientDevice]
    func configuration(protocol id: ServiceID, clientID: String) async throws -> VPNClientConfiguration
}

/// What the containers section asks of a server
@available(macOS 15.0, *)
protocol ContainerManaging: Sendable {
    func inventory() async throws -> ContainerInventory
    @discardableResult
    func rename(key: String, to displayName: String) async throws -> ContainerInventory
    func control(key: String, action: ContainerAction) async throws
    func inspect(container name: String) async throws -> ContainerDetail
    func backupPlan(key: String) async throws -> ContainerBackupPlan
    @discardableResult
    func setBackupPlan(key: String, plan: ContainerBackupPlan?) async throws -> ContainerBackupPlan
    /// One group's log, as a stream
    func logs(key: String, tail: UInt32) -> AsyncThrowingStream<ContainerLogLine, Error>
    /// Runs the plan
    func runBackup(key: String, onLine: @escaping @Sendable (String) -> Void) async throws -> ContainerArchive?
    func removalPreview(key: String, purgeData: Bool, purgeBackups: Bool) async throws -> ContainerRemovalPreview
    func remove(key: String, purgeData: Bool, purgeBackups: Bool,
                onLine: @escaping @Sendable (String) -> Void) async throws
    func update(key: String, skipBackup: Bool,
                onLine: @escaping @Sendable (String) -> Void) async throws -> ContainerUpdateOutcome
    func backupSchedule(key: String) async throws -> ContainerBackupSchedule
    @discardableResult
    func setBackupSchedule(key: String, every cadence: ContainerBackupCadence?) async throws -> ContainerBackupSchedule
    /// The archives this group's runs have left
    func backups(key: String) async throws -> ContainerBackupListing
}

enum ContainerUpdateOutcome: Sendable, Hashable {
    case updated
    case alreadyCurrent
    case rolledBack(String)
}

@available(macOS 15.0, *)
extension AgentContainerOperations: ContainerManaging {
    /// Drains its own stream
    func control(key: String, action: ContainerAction) async throws {
        for try await _ in control(key: key, action: action) as AsyncThrowingStream<ContainerOperationEvent, Error> {}
    }

    func runBackup(key: String, onLine: @escaping @Sendable (String) -> Void) async throws -> ContainerArchive? {
        var archive: ContainerArchive?
        for try await event in runBackup(key: key) as AsyncThrowingStream<ContainerBackupRunEvent, Error> {
            if let written = event.archive { archive = written }
            if !event.text.isEmpty { onLine(event.text) }
        }
        return archive
    }

    func remove(key: String, purgeData: Bool, purgeBackups: Bool,
                onLine: @escaping @Sendable (String) -> Void) async throws {
        let stream: AsyncThrowingStream<ContainerRemovalEvent, Error> =
            remove(key: key, purgeData: purgeData, purgeBackups: purgeBackups)
        for try await event in stream where !event.text.isEmpty {
            onLine(event.text)
        }
    }

    func update(key: String, skipBackup: Bool,
                onLine: @escaping @Sendable (String) -> Void) async throws -> ContainerUpdateOutcome {
        var outcome = ContainerUpdateOutcome.updated
        var lastLine = ""
        let stream: AsyncThrowingStream<ContainerUpdateEvent, Error> = update(key: key, skipBackup: skipBackup)
        for try await event in stream {
            if !event.text.isEmpty {
                lastLine = event.text
                onLine(event.text)
            }
            if event.phase == .completed {
                if event.didRollBack {
                    outcome = .rolledBack(lastLine)
                } else if event.wasAlreadyCurrent {
                    outcome = .alreadyCurrent
                }
            }
        }
        return outcome
    }
}

@available(macOS 15.0, *)
extension AgentVPNClientOperations: VPNClientManaging {}

@available(macOS 15.0, *)
protocol MeshManaging: Sendable {
    func users() async throws -> [MeshUser]
    @discardableResult
    func createUser(named name: String) async throws -> [MeshUser]
    func mintAuthKey(userID: String, reusable: Bool, expirationHours: UInt32) async throws -> MeshAuthKey
    func nodes() async throws -> [MeshNode]
    @discardableResult
    func removeNode(id: String) async throws -> [MeshNode]
    @discardableResult
    func publishNames(_ names: [String], nodeName: String) async throws -> [MeshName]
}

@available(macOS 15.0, *)
extension AgentMeshOperations: MeshManaging {}

@available(macOS 15.0, *)
extension MeshManaging {
    @discardableResult
    func publishNames(_ names: [String]) async throws -> [MeshName] {
        try await publishNames(names, nodeName: "")
    }
}
