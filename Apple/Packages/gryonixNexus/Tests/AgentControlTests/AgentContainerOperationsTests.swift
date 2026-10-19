import AgentClient
import Foundation
import SwiftProtobuf
import XCTest
@testable import AgentControl

private struct ContainersMockTransport: AgentTransport {
    var onUnary: @Sendable (String, Data) async throws -> Data = { _, _ in Data() }

    func unary(path: String, request: Data) async throws -> Data {
        try await onUnary(path, request)
    }

    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

@available(macOS 15.0, *)
final class AgentContainerOperationsTests: XCTestCase {
    private func inventory(_ build: (inout Gryonixnexusd_V1_ContainerInventory) -> Void) throws -> Data {
        var wire = Gryonixnexusd_V1_ContainerInventory()
        build(&wire)
        let bytes: Data = try wire.serializedBytes()
        return bytes
    }

    private func ops(_ payload: @escaping @Sendable (String, Data) async throws -> Data)
    -> AgentContainerOperations {
        AgentContainerOperations(client: AgentClient(transport:
            ContainersMockTransport(onUnary: payload)))
    }

    private func group(key: String, name: String) -> Gryonixnexusd_V1_ContainerGroup {
        var group = Gryonixnexusd_V1_ContainerGroup()
        group.key = key
        group.displayName = name
        group.derivedName = name
        group.kind = .composeProject
        group.status = .running
        return group
    }

    // MARK: - The listing

    func testAnUnreachableEngineIsNotAnEmptyMachine() async throws {
        let payload = try inventory { $0.unavailableReason = "docker: command not found" }
        let result = try await ops { path, _ in
            XCTAssertEqual(path, "/gryonixnexusd.v1.Containers/ListContainers")
            return payload
        }.inventory()

        XCTAssertEqual(result.unavailableReason, "docker: command not found",
                       "the reason has to survive, or the screen can only draw an empty list")
        XCTAssertTrue(result.groups.isEmpty)
    }

    func testAHealthyEmptyHostReportsNoReasonAtAll() async throws {
        let payload = try inventory { _ in }
        let result = try await ops { _, _ in payload }.inventory()
        XCTAssertNil(result.unavailableReason,
                     "an empty string is the wire's way of saying nothing is wrong")
        XCTAssertTrue(result.groups.isEmpty)
    }

    func testAStrangersStackAndOneOfOursAreToldApart() async throws {
        let payload = try inventory {
            var ours = group(key: "mailcowdockerized", name: "mailcow")
            ours.serviceID = "mailcow"
            var theirs = group(key: "someone-else", name: "someone-else")
            theirs.kind = .standalone
            theirs.status = .partial
            $0.groups = [ours, theirs]
        }
        let result = try await ops { _, _ in payload }.inventory()

        XCTAssertEqual(result.groups.first?.serviceID, "mailcow")
        XCTAssertTrue(result.groups.first?.isComposeProject == true)
        XCTAssertNil(result.groups.last?.serviceID,
                     "an empty service id means a stranger, not a service called \"\"")
        XCTAssertFalse(result.groups.last?.isComposeProject == true)
        XCTAssertEqual(result.groups.last?.status, .partial,
                       "partial is the state that matters most on a stack")
    }

    func testEveryStatusCrossesOverIncludingOnesWeHaveNotSeen() async throws {
        let cases: [(Gryonixnexusd_V1_ServiceStatus, ContainerGroupStatus)] = [
            (.running, .running), (.stopped, .stopped),
            (.partial, .partial), (.error, .error), (.unspecified, .unknown),
        ]
        for (wire, expected) in cases {
            let payload = try inventory {
                var one = group(key: "k", name: "n")
                one.status = wire
                $0.groups = [one]
            }
            let result = try await ops { _, _ in payload }.inventory()
            XCTAssertEqual(result.groups.first?.status, expected, "\(wire)")
        }
    }

    // MARK: - Renaming

    func testRenamingSendsTheKeyAndTrimsTheNameAndBelievesTheServer() async throws {
        let payload = try inventory {
            var renamed = group(key: "k", name: "Owner's name")
            renamed.derivedName = "k"
            renamed.renamed = true
            $0.groups = [renamed]
        }
        let result = try await ops { path, request in
            XCTAssertEqual(path, "/gryonixnexusd.v1.Containers/SetContainerGroupName")
            let sent = try Gryonixnexusd_V1_SetContainerGroupNameRequest(serializedBytes: request)
            XCTAssertEqual(sent.key, "k")
            XCTAssertEqual(sent.displayName, "Owner's name",
                           "a pasted name arrives with whitespace; the server should not store it")
            return payload
        }.rename(key: "k", to: "  Owner's name \n")

        XCTAssertEqual(result.groups.first?.displayName, "Owner's name")
        XCTAssertEqual(result.groups.first?.derivedName, "k",
                       "the derived name always travels, so \"back to detected\" needs no second call")
        XCTAssertTrue(result.groups.first?.isRenamed == true)
    }

    func testClearingANameIsTheSameCallWithAnEmptyString() async throws {
        let payload = try inventory { $0.groups = [group(key: "k", name: "k")] }
        _ = try await ops { path, request in
            XCTAssertEqual(path, "/gryonixnexusd.v1.Containers/SetContainerGroupName")
            let sent = try Gryonixnexusd_V1_SetContainerGroupNameRequest(serializedBytes: request)
            XCTAssertTrue(sent.displayName.isEmpty)
            return payload
        }.rename(key: "k", to: "   ")
    }

    // MARK: - Inspect

    func testAReadOnlyMountIsNotReportedAsWritable() async throws {
        var detail = Gryonixnexusd_V1_ContainerDetail()
        var readOnly = Gryonixnexusd_V1_ContainerMount()
        readOnly.source = "/srv/media"
        readOnly.destination = "/media"
        readOnly.mode = "ro"
        readOnly.kind = "bind"
        var writable = Gryonixnexusd_V1_ContainerMount()
        writable.source = "app_data"
        writable.destination = "/data"
        writable.mode = "rw"
        writable.kind = "volume"
        detail.mounts = [readOnly, writable]
        let payload: Data = try detail.serializedBytes()

        let read = try await ops { path, _ in
            XCTAssertEqual(path, "/gryonixnexusd.v1.Containers/InspectContainer")
            return payload
        }.inspect(container: "c")

        XCTAssertTrue(read.mounts.first?.isReadOnly == true, "\"ro\" is the only read-only word here")
        XCTAssertFalse(read.mounts.last?.isReadOnly == true)
        XCTAssertEqual(read.mounts.first?.kind, "bind",
                       "bind vs volume decides whether the source path means anything to a reader")
    }

    func testTheSensitiveVerdictSurvivesTheCrossing() async throws {
        var detail = Gryonixnexusd_V1_ContainerDetail()
        var secret = Gryonixnexusd_V1_ContainerEnvVar()
        secret.key = "DB_PASSWORD"
        secret.value = "hunter2"
        secret.sensitive = true
        var plain = Gryonixnexusd_V1_ContainerEnvVar()
        plain.key = "TZ"
        plain.value = "Europe/Berlin"
        detail.env = [secret, plain]
        let payload: Data = try detail.serializedBytes()

        let read = try await ops { _, _ in payload }.inspect(container: "c")

        XCTAssertTrue(read.environment.first?.isSensitive == true,
                      "a credential that loses its flag is a credential drawn in the open")
        XCTAssertFalse(read.environment.last?.isSensitive == true)
        XCTAssertEqual(read.environment.first?.key, "DB_PASSWORD")
    }

    // MARK: - The backup plan

    func testClearingACorrectionAndArchivingNothingAreDifferentRequests() async throws {
        var answer = Gryonixnexusd_V1_ContainerBackupPlan()
        answer.key = "k"
        let payload: Data = try answer.serializedBytes()

        var sawPlan: [Bool] = []
        let operations = ops { _, request in
            let sent = try Gryonixnexusd_V1_SetContainerBackupPlanRequest(serializedBytes: request)
            sawPlan.append(sent.hasPlan)
            return payload
        }

        _ = try await operations.setBackupPlan(key: "k", plan: nil)
        _ = try await operations.setBackupPlan(
            key: "k",
            plan: ContainerBackupPlan(key: "k", paths: [], volumes: [], databases: [],
                                      stopWhileArchiving: false, isDetected: false, notes: []))

        XCTAssertEqual(sawPlan, [false, true],
                       "nil must clear the correction; an empty plan must be sent as a plan")
    }

    func testCorrectingAPlanKeepsItsDatabasesExactly() async throws {
        var wire = Gryonixnexusd_V1_ContainerBackupPlan()
        wire.key = "k"
        wire.paths = ["/srv/app", "/srv/cache"]
        var dump = Gryonixnexusd_V1_ContainerDatabaseDump()
        dump.container = "app-db-1"
        dump.engine = .postgres
        dump.database = "app"
        dump.user = "app"
        dump.passwordEnv = "POSTGRES_PASSWORD"
        wire.databases = [dump]
        wire.detected = true
        wire.notes = ["postgres image detected"]
        let read: Data = try wire.serializedBytes()

        let operations = ops { path, _ in
            XCTAssertEqual(path, "/gryonixnexusd.v1.Containers/GetContainerBackupPlan")
            return read
        }
        let plan = try await operations.backupPlan(key: "k")
        XCTAssertEqual(plan.databases.first?.passwordEnvName, "POSTGRES_PASSWORD",
                       "the NAME travels; the value never does")
        XCTAssertTrue(plan.isDetected)
        XCTAssertEqual(plan.notes, ["postgres image detected"])

        let corrected = ContainerBackupPlan(
            key: plan.key, paths: ["/srv/app"], volumes: plan.volumes,
            databases: plan.databases, stopWhileArchiving: plan.stopWhileArchiving,
            isDetected: false, notes: [])
        var sent: Gryonixnexusd_V1_ContainerBackupPlan?
        _ = try await ops { _, request in
            sent = try Gryonixnexusd_V1_SetContainerBackupPlanRequest(serializedBytes: request).plan
            return read
        }.setBackupPlan(key: "k", plan: corrected)

        XCTAssertEqual(sent?.paths, ["/srv/app"])
        XCTAssertEqual(sent?.databases.count, 1)
        XCTAssertEqual(sent?.databases.first?.engine, .postgres,
                       "the engine round-trips as the enum, not through its display name")
        XCTAssertEqual(sent?.databases.first?.passwordEnv, "POSTGRES_PASSWORD")
    }

    func testACorrectionDoesNotSendBackTheServersOwnVerdict() async throws {
        var answer = Gryonixnexusd_V1_ContainerBackupPlan()
        answer.key = "k"
        let payload: Data = try answer.serializedBytes()
        var sent: Gryonixnexusd_V1_ContainerBackupPlan?
        _ = try await ops { _, request in
            sent = try Gryonixnexusd_V1_SetContainerBackupPlanRequest(serializedBytes: request).plan
            return payload
        }.setBackupPlan(key: "k",
                        plan: ContainerBackupPlan(key: "k", paths: ["/a"], volumes: [],
                                                  databases: [], stopWhileArchiving: false,
                                                  isDetected: true,
                                                  notes: ["invented by the client"]))
        XCTAssertTrue(sent?.notes.isEmpty ?? false,
                      "notes are the agent's words about its own detection")
        XCTAssertFalse(sent?.detected ?? true)
    }

    // MARK: - Ports

    func testThePublishedPortsSurviveAsTheEngineWroteThem() async throws {
        let payload = try inventory {
            var one = group(key: "k", name: "n")
            var container = Gryonixnexusd_V1_Container()
            container.name = "web-1"
            container.ports = "0.0.0.0:8080->80/tcp, [::]:8080->80/tcp"
            one.containers = [container]
            $0.groups = [one]
        }
        let result = try await ops { _, _ in payload }.inventory()
        XCTAssertEqual(result.groups.first?.containers.first?.ports,
                       "0.0.0.0:8080->80/tcp, [::]:8080->80/tcp",
                       "kept verbatim: a parser that dropped a form docker prints is worse than the line")
    }

    // MARK: - Actions

    func testTheThreeVerbsMapOntoTheAgentsOwnEnumRatherThanASecondOne() {
        XCTAssertEqual(ContainerAction.start.wire, .start)
        XCTAssertEqual(ContainerAction.stop.wire, .stop)
        XCTAssertEqual(ContainerAction.restart.wire, .restart)
    }
}

@available(macOS 15.0, *)
final class ContainerDestructiveVerbTests: XCTestCase {
    private func ops(_ payload: @escaping @Sendable (String, Data) async throws -> Data)
    -> AgentContainerOperations {
        AgentContainerOperations(client: AgentClient(transport: ContainersMockTransport(onUnary: payload)))
    }

    func testTheRemovalPreviewCarriesEachListSeparately() async throws {
        let captured = LockedBox<Gryonixnexusd_V1_PreviewContainerGroupRemovalRequest>()
        let operations = ops { path, data in
            XCTAssertEqual(path, "/gryonixnexusd.v1.Containers/PreviewContainerGroupRemoval")
            captured.value = try Gryonixnexusd_V1_PreviewContainerGroupRemovalRequest(serializedBytes: data)
            var wire = Gryonixnexusd_V1_ContainerRemovalPreview()
            wire.key = "mystack"
            wire.containers = ["mystack-app-1", "mystack-db-1"]
            wire.volumes = ["mystack_db"]
            wire.paths = ["/opt/mystack/data"]
            wire.backupPaths = ["/opt/backups/containers/mystack"]
            wire.notes = ["/etc is left alone: it is a system directory"]
            let bytes: Data = try wire.serializedBytes()
            return bytes
        }

        let preview = try await operations.removalPreview(key: "mystack", purgeData: true, purgeBackups: true)
        XCTAssertEqual(captured.value?.key, "mystack")
        XCTAssertEqual(captured.value?.purgeData, true)
        XCTAssertEqual(captured.value?.purgeBackups, true)

        XCTAssertEqual(preview.containers, ["mystack-app-1", "mystack-db-1"])
        XCTAssertEqual(preview.volumes, ["mystack_db"])
        XCTAssertEqual(preview.paths, ["/opt/mystack/data"])
        XCTAssertEqual(preview.backupPaths, ["/opt/backups/containers/mystack"])
        XCTAssertEqual(preview.notes.count, 1)
        XCTAssertFalse(preview.isEmpty)
    }

    func testAScheduleThatIsOffIsNotAScheduleAtAll() async throws {
        let operations = ops { _, _ in
            var wire = Gryonixnexusd_V1_ContainerBackupSchedule()
            wire.key = "mystack"
            wire.schedule = ""
            wire.enabled = false
            let bytes: Data = try wire.serializedBytes()
            return bytes
        }
        let schedule = try await operations.backupSchedule(key: "mystack")
        XCTAssertNil(schedule.cadence)
        XCTAssertFalse(schedule.isEnabled)
        XCTAssertNil(schedule.lastRun)
    }

    func testEachCadenceSurvivesTheCrossing() async throws {
        for cadence in ContainerBackupCadence.allCases {
            let operations = ops { _, _ in
                var wire = Gryonixnexusd_V1_ContainerBackupSchedule()
                wire.key = "mystack"
                wire.schedule = cadence.rawValue
                wire.enabled = true
                wire.lastOutcome = "ok /opt/backups/containers/mystack/x.tar.gz"
                wire.lastRun = "1750000000"
                let bytes: Data = try wire.serializedBytes()
                return bytes
            }
            let schedule = try await operations.backupSchedule(key: "mystack")
            XCTAssertEqual(schedule.cadence, cadence)
            XCTAssertTrue(schedule.isEnabled)
            XCTAssertEqual(schedule.lastRun, Date(timeIntervalSince1970: 1_750_000_000))
        }
    }

    func testAnUnknownCadenceReadsAsOffRatherThanAsSomethingElse() async throws {
        let operations = ops { _, _ in
            var wire = Gryonixnexusd_V1_ContainerBackupSchedule()
            wire.key = "mystack"
            wire.schedule = "fortnightly"
            wire.enabled = true
            let bytes: Data = try wire.serializedBytes()
            return bytes
        }
        let schedule = try await operations.backupSchedule(key: "mystack")
        XCTAssertNil(schedule.cadence)
    }

    func testSwitchingASchedueOffIsTheSameCallWithAnEmptyString() async throws {
        let captured = LockedBox<Gryonixnexusd_V1_SetContainerBackupScheduleRequest>()
        let operations = ops { path, data in
            XCTAssertEqual(path, "/gryonixnexusd.v1.Containers/SetContainerBackupSchedule")
            captured.value = try Gryonixnexusd_V1_SetContainerBackupScheduleRequest(serializedBytes: data)
            var wire = Gryonixnexusd_V1_ContainerBackupSchedule()
            wire.key = "mystack"
            let bytes: Data = try wire.serializedBytes()
            return bytes
        }
        _ = try await operations.setBackupSchedule(key: "mystack", every: nil)
        XCTAssertEqual(captured.value?.schedule, "")

        _ = try await operations.setBackupSchedule(key: "mystack", every: .weekly)
        XCTAssertEqual(captured.value?.schedule, "weekly")
    }

    // MARK: - A foreign group's backups

    func testAForeignGroupsArchivesComeBackWithTheDirectoryTheAgentResolved() async throws {
        let operations = ops { path, _ in
            XCTAssertEqual(path, "/gryonixnexusd.v1.Containers/ListContainerGroupBackups")
            var wire = Gryonixnexusd_V1_ContainerBackupList()
            wire.key = "acme-stack"
            wire.directory = "/opt/backups/containers/acme-stack"
            var newer = Gryonixnexusd_V1_BackupArchive()
            newer.name = "newer.tar.gz"
            newer.path = "/opt/backups/containers/acme-stack/newer.tar.gz"
            newer.sizeBytes = 2048
            newer.modifiedAt = 1_700_000_000_000
            var older = Gryonixnexusd_V1_BackupArchive()
            older.name = "older.tar.gz"
            older.path = "/opt/backups/containers/acme-stack/older.tar.gz"
            wire.archives = [newer, older]
            let bytes: Data = try wire.serializedBytes()
            return bytes
        }
        let listing = try await operations.backups(key: "acme-stack")
        XCTAssertEqual(listing.directory, "/opt/backups/containers/acme-stack")
        XCTAssertEqual(listing.archives.map(\.name), ["newer.tar.gz", "older.tar.gz"])
        XCTAssertEqual(listing.archives.first?.sizeBytes, 2048)
        XCTAssertNotNil(listing.archives.first?.modifiedAt)
    }

    func testAGroupWithNoBackupsAnswersEmptyAndStillNamesTheDirectory() async throws {
        let operations = ops { _, _ in
            var wire = Gryonixnexusd_V1_ContainerBackupList()
            wire.key = "fresh"
            wire.directory = "/opt/backups/containers/fresh"
            let bytes: Data = try wire.serializedBytes()
            return bytes
        }
        let listing = try await operations.backups(key: "fresh")
        XCTAssertTrue(listing.archives.isEmpty)
        XCTAssertEqual(listing.directory, "/opt/backups/containers/fresh")
    }

    func testAnArchiveWithNoTimeHasNoDate() async throws {
        let operations = ops { _, _ in
            var wire = Gryonixnexusd_V1_ContainerBackupList()
            var archive = Gryonixnexusd_V1_BackupArchive()
            archive.name = "undated.tar.gz"
            wire.archives = [archive]
            let bytes: Data = try wire.serializedBytes()
            return bytes
        }
        let listing = try await operations.backups(key: "acme-stack")
        XCTAssertNil(listing.archives.first?.modifiedAt)
    }

    // MARK: - The one refusal that turns into an offer

    func testTheEmptyPlanRefusalIsRecognised() {
        let refusal = AgentError.rpc(
            code: "failed_precondition",
            message: "nothing_to_archive: this group stores nothing outside its images")
        XCTAssertTrue(AgentContainerOperations.namesNothingToArchive(refusal))
    }

    func testAStalePlanIsNotOfferedTheSkip() {
        let staleRun = AgentError.rpc(
            code: "internal",
            message: "this plan names nothing that exists on the host — nothing was archived")
        XCTAssertFalse(AgentContainerOperations.namesNothingToArchive(staleRun))
    }

    func testNothingElseIsMistakenForIt() {
        XCTAssertFalse(AgentContainerOperations.namesNothingToArchive(
            AgentError.rpc(code: "failed_precondition",
                           message: "this group has a database that would be dumped")))
        XCTAssertFalse(AgentContainerOperations.namesNothingToArchive(
            AgentError.transport("the agent bridge did not start: Connection refused")))
        XCTAssertFalse(AgentContainerOperations.namesNothingToArchive(
            AgentError.decode("nothing_to_archive: not an RPC refusal at all")))
        struct Other: Error {}
        XCTAssertFalse(AgentContainerOperations.namesNothingToArchive(Other()))
    }

    func testTheMarkerIsReadAtTheFrontRatherThanAnywhere() {
        XCTAssertFalse(AgentContainerOperations.namesNothingToArchive(
            AgentError.rpc(code: "internal",
                           message: "backing up failed: nothing_to_archive: appeared in a log line")))
    }
}
