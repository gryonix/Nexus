import AgentClient
import Foundation
import ServerControl
import ServiceCatalog
import SwiftProtobuf
import XCTest
@testable import AgentControl

private struct MockTransport: AgentTransport {
    var onUnary: @Sendable (String, Data) async throws -> Data = { _, _ in Data() }
    var onStream: @Sendable (String, Data) -> AsyncThrowingStream<Data, Error> = { _, _ in
        AsyncThrowingStream { $0.finish() }
    }

    func unary(path: String, request: Data) async throws -> Data {
        try await onUnary(path, request)
    }

    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        onStream(path, request)
    }
}

final class AgentAutoBackupOperationsTests: XCTestCase {
    // MARK: - Routing

    func testBackupScheduleFollowsTheSameRouteAsControlActions() {
        XCTAssertEqual(AutoBackupRouting.route(usesAgent: true, agentTransportAvailable: true), .agent)
        XCTAssertEqual(AutoBackupRouting.route(usesAgent: true, agentTransportAvailable: false), .ssh)
        XCTAssertEqual(AutoBackupRouting.route(usesAgent: false, agentTransportAvailable: true), .ssh)
    }

    // MARK: - Load

    func testLoadReadsTheScheduleRetentionAndServices() async throws {
        var policy = Gryonixnexusd_V1_BackupSchedulePolicy()
        policy.schedule = "every:1d@03:30"
        policy.retention = 14
        policy.services = ["nextcloud", "vaultwarden"]
        let payload: Data = try policy.serializedBytes()

        let backups = AgentAutoBackupOperations(client: AgentClient(transport: MockTransport(
            onUnary: { path, _ in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Backup/GetBackupSchedule")
                return payload
            })))

        let settings = try await backups.load()
        XCTAssertEqual(settings.schedule, .days(count: 1, hour: 3, minute: 30))
        XCTAssertEqual(settings.retention, 14)
        XCTAssertEqual(settings.services, ["nextcloud", "vaultwarden"])
    }

    func testLoadFallsBackToTheDefaultRetentionWhenTheServerNamesNone() async throws {
        var policy = Gryonixnexusd_V1_BackupSchedulePolicy()
        policy.schedule = "off"
        let payload: Data = try policy.serializedBytes()

        let backups = AgentAutoBackupOperations(client: AgentClient(transport: MockTransport(
            onUnary: { _, _ in payload })))

        let settings = try await backups.load()
        XCTAssertEqual(settings.retention, 7)
    }

    // MARK: - Save

    func testSaveSendsTheGrammarRetentionServicesAndPassphrase() async throws {
        let sent = LockedBox<Gryonixnexusd_V1_SetBackupScheduleRequest>()
        let backups = AgentAutoBackupOperations(client: AgentClient(transport: MockTransport(
            onUnary: { path, request in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Backup/SetBackupSchedule")
                sent.value = try Gryonixnexusd_V1_SetBackupScheduleRequest(serializedBytes: request)
                return try Gryonixnexusd_V1_BackupSchedulePolicy().serializedBytes()
            })))

        try await backups.save(AutoBackupSettings(schedule: .hours(count: 6, minute: 0),
                                                  retention: 30,
                                                  services: ["vaultwarden"]),
                               passphrase: "correct horse battery staple")
        XCTAssertEqual(sent.value?.schedule, "every:6h@00:00")
        XCTAssertEqual(sent.value?.retention, 30)
        XCTAssertEqual(sent.value?.services, ["vaultwarden"])
        XCTAssertEqual(sent.value?.passphrase, "correct horse battery staple")
    }

    func testSaveSendsAnEmptyPassphraseWhenNoneIsGiven() async throws {
        let sent = LockedBox<Gryonixnexusd_V1_SetBackupScheduleRequest>()
        let backups = AgentAutoBackupOperations(client: AgentClient(transport: MockTransport(
            onUnary: { _, request in
                sent.value = try Gryonixnexusd_V1_SetBackupScheduleRequest(serializedBytes: request)
                return try Gryonixnexusd_V1_BackupSchedulePolicy().serializedBytes()
            })))

        try await backups.save(AutoBackupSettings(schedule: .off), passphrase: nil)
        XCTAssertEqual(sent.value?.passphrase, "")
    }
}
