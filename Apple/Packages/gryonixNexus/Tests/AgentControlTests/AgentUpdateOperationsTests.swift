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

private func updateEvent(_ phase: Gryonixnexusd_V1_ServiceOperationPhase,
                         text: String = "",
                         outcome: Gryonixnexusd_V1_UpdateOutcome = .unspecified,
                         reason: String = "") -> Data {
    var event = Gryonixnexusd_V1_UpdateEvent()
    event.phase = phase
    event.text = text
    event.outcome = outcome
    event.reason = reason
    return (try? event.serializedBytes()) ?? Data()
}

final class AgentUpdateOperationsTests: XCTestCase {
    // MARK: - Routing

    func testUpdatesFollowTheSameRouteAsControlActions() {
        XCTAssertEqual(ServiceUpdateRouting.route(usesAgent: true, agentTransportAvailable: true), .agent)
        XCTAssertEqual(ServiceUpdateRouting.route(usesAgent: true, agentTransportAvailable: false), .ssh)
        XCTAssertEqual(ServiceUpdateRouting.route(usesAgent: false, agentTransportAvailable: true), .ssh)
    }

    // MARK: - Check

    func testCheckMapsAvailabilityAndKeepsUnrecognisedIds() async throws {
        var current = Gryonixnexusd_V1_ServiceUpdateStatus()
        current.serviceID = "nextcloud"
        current.availability = .current

        var available = Gryonixnexusd_V1_ServiceUpdateStatus()
        available.serviceID = "vaultwarden"
        available.availability = .available
        available.movedImages = ["vaultwarden/server:1.34.0"]

        var unknown = Gryonixnexusd_V1_ServiceUpdateStatus()
        unknown.serviceID = "immich"
        unknown.availability = .unknown
        unknown.reason = "registry_unreachable"

        var future = Gryonixnexusd_V1_ServiceUpdateStatus()
        future.serviceID = "some-future-service"
        future.availability = .current

        var vpn = Gryonixnexusd_V1_ServiceUpdateStatus()
        vpn.serviceID = "vpn"
        vpn.availability = .current

        var result = Gryonixnexusd_V1_UpdateCheckResult()
        result.services = [current, available, unknown, future, vpn]
        let payload: Data = try result.serializedBytes()

        let updates = AgentUpdateOperations(client: AgentClient(transport: MockTransport(
            onUnary: { path, _ in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Update/CheckUpdates")
                return payload
            })))

        let reports = try await updates.check()
        XCTAssertEqual(reports.count, 5)
        XCTAssertEqual(reports[0].service, .nextcloud)
        XCTAssertEqual(reports[0].status, .current)
        XCTAssertEqual(reports[1].service, .vaultwarden)
        XCTAssertEqual(reports[1].status, .available(images: ["vaultwarden/server:1.34.0"]))
        XCTAssertEqual(reports[2].service, .immich)
        XCTAssertEqual(reports[2].status, .unknown)
        XCTAssertEqual(reports[3].service, ServiceID(rawValue: "some-future-service"))
        XCTAssertEqual(reports[4].service, .vpnPanel)
    }

    // MARK: - Run

    func testASuccessfulRunReturnsTheUpdatedOutcomeWithNoTrailerAtAll() async throws {
        let frames = [
            updateEvent(.started),
            updateEvent(.progress, text: "pulling nextcloud"),
            updateEvent(.completed, outcome: .updated)
        ]
        var progress: [String] = []
        let updates = AgentUpdateOperations(client: AgentClient(transport: MockTransport(
            onStream: { path, request in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Update/RunUpdate")
                let sent = try? Gryonixnexusd_V1_RunUpdateRequest(serializedBytes: request)
                XCTAssertEqual(sent?.serviceID, "nextcloud")
                return AsyncThrowingStream { continuation in
                    for frame in frames { continuation.yield(frame) }
                    continuation.finish()
                }
            })))

        let record = try await updates.run(.nextcloud) { progress.append($0) }
        XCTAssertEqual(record.service, .nextcloud)
        XCTAssertEqual(record.outcome, .updated)
        XCTAssertEqual(progress, ["pulling nextcloud\n"])
    }

    func testARolledBackRunIsAResultNotAThrow() async throws {
        let updates = AgentUpdateOperations(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(updateEvent(.progress, text: "waiting for health"))
                    continuation.yield(updateEvent(.completed, outcome: .rolledBack,
                                                   reason: "a container is restarting"))
                    continuation.finish(throwing: AgentError.rpc(code: "internal",
                                                                 message: "a container is restarting"))
                }
            })))

        let record = try await updates.run(.nextcloud)
        XCTAssertEqual(record.outcome, .rolledBack(reason: "a container is restarting"))
    }

    func testAFailedRunIsAResultNotAThrow() async throws {
        let updates = AgentUpdateOperations(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(updateEvent(.completed, outcome: .failed,
                                                   reason: "the backup failed"))
                    continuation.finish(throwing: AgentError.rpc(code: "internal",
                                                                 message: "the backup failed"))
                }
            })))

        let record = try await updates.run(.vaultwarden)
        XCTAssertEqual(record.outcome, .failed(reason: "the backup failed"))
    }

    func testARefusalWithNoCompletedEventAtAllStillThrows() async throws {
        let updates = AgentUpdateOperations(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: AgentError.rpc(
                        code: "failed_precondition",
                        message: "mailcow ships its own updater, so this wrapper does not swap its images"))
                }
            })))

        do {
            _ = try await updates.run(.mailcow)
            XCTFail("a refusal before anything ran must throw")
        } catch let error as ServerControlError {
            guard case .commandFailed(_, _, let stderr) = error else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertEqual(stderr, "mailcow ships its own updater, so this wrapper does not swap its images")
        }
    }

    // MARK: - Schedule / status

    func testLoadScheduleAndLoadStatusBothReadTheOnePolicyCall() async throws {
        var record = Gryonixnexusd_V1_UpdateRunRecord()
        record.serviceID = "nextcloud"
        record.outcome = .updated

        var policy = Gryonixnexusd_V1_UpdatePolicy()
        policy.schedule = "every:1d@04:30"
        policy.services = ["nextcloud", "vaultwarden"]
        policy.lastRun = [record]
        policy.lastRunAt = 1_754_600_000_000
        let payload: Data = try policy.serializedBytes()

        let updates = AgentUpdateOperations(client: AgentClient(transport: MockTransport(
            onUnary: { path, _ in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Update/GetUpdatePolicy")
                return payload
            })))

        let settings = try await updates.loadSchedule()
        XCTAssertEqual(settings.schedule, .days(count: 1, hour: 4, minute: 30))
        XCTAssertEqual(settings.services, ["nextcloud", "vaultwarden"])

        let log = try await updates.loadStatus()
        XCTAssertEqual(log.records.first?.service, .nextcloud)
        XCTAssertEqual(log.records.first?.outcome, .updated)
        XCTAssertNotNil(log.lastRun)
    }

    func testSaveSendsTheGrammarAndTheCheckedServices() async throws {
        let sent = LockedBox<Gryonixnexusd_V1_SetUpdateScheduleRequest>()
        let updates = AgentUpdateOperations(client: AgentClient(transport: MockTransport(
            onUnary: { path, request in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Update/SetUpdateSchedule")
                sent.value = try Gryonixnexusd_V1_SetUpdateScheduleRequest(serializedBytes: request)
                return try Gryonixnexusd_V1_UpdatePolicy().serializedBytes()
            })))

        try await updates.save(AutoUpdateSettings(schedule: .hours(count: 6, minute: 0),
                                                   services: ["nextcloud"]))
        XCTAssertEqual(sent.value?.schedule, "every:6h@00:00")
        XCTAssertEqual(sent.value?.services, ["nextcloud"])
    }
}
