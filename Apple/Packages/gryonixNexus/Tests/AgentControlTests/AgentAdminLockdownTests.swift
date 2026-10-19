import AgentClient
import Foundation
import ServerControl
import SwiftProtobuf
import XCTest
@testable import AgentControl

private struct LockdownMockTransport: AgentTransport {
    var onUnary: @Sendable (String, Data) async throws -> Data = { _, _ in Data() }

    func unary(path: String, request: Data) async throws -> Data {
        try await onUnary(path, request)
    }

    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private func lockdownState(_ mode: Gryonixnexusd_V1_LockdownMode, hosts: [String] = []) throws -> Data {
    var state = Gryonixnexusd_V1_LockdownState()
    state.mode = mode
    state.hosts = hosts
    let bytes: Data = try state.serializedBytes()
    return bytes
}

final class AgentAdminLockdownTests: XCTestCase {
    // MARK: - Routing

    func testLockdownFollowsTheSameRouteAsControlActionsWithNoExtraCondition() {
        XCTAssertEqual(LockdownRouting.route(usesAgent: true, agentTransportAvailable: true), .agent)
        XCTAssertEqual(LockdownRouting.route(usesAgent: true, agentTransportAvailable: false), .ssh)
        XCTAssertEqual(LockdownRouting.route(usesAgent: false, agentTransportAvailable: true), .ssh)
        XCTAssertEqual(LockdownRouting.route(usesAgent: false, agentTransportAvailable: false), .ssh)
    }

    func testStatusMapsEachModeAndCallsTheRightPath() async throws {
        for (wire, expected) in [
            (Gryonixnexusd_V1_LockdownMode.off, AdminLockdownState.off),
            (Gryonixnexusd_V1_LockdownMode.all, AdminLockdownState.all),
        ] {
            let payload = try lockdownState(wire)
            let ops = AgentAdminLockdown(client: AgentClient(transport: LockdownMockTransport(
                onUnary: { path, _ in
                    XCTAssertEqual(path, "/gryonixnexusd.v1.Lockdown/GetLockdown")
                    return payload
                })))
            let result = try await ops.status()
            XCTAssertEqual(result, expected)
        }
    }

    func testStatusMapsOnlyModeToItsHostSet() async throws {
        let payload = try lockdownState(.only, hosts: ["a.example.com", "b.example.com"])
        let ops = AgentAdminLockdown(client: AgentClient(transport: LockdownMockTransport(
            onUnary: { _, _ in payload })))
        let result = try await ops.status()
        XCTAssertEqual(result, .only(["a.example.com", "b.example.com"]))
    }

    func testAnUnrecognisedModeFromANewerServerReadsAsOff() async throws {
        var raw = Gryonixnexusd_V1_LockdownState()
        raw.mode = Gryonixnexusd_V1_LockdownMode(rawValue: 99) ?? .unspecified
        let payload: Data = try raw.serializedBytes()
        let ops = AgentAdminLockdown(client: AgentClient(transport: LockdownMockTransport(
            onUnary: { _, _ in payload })))
        let result = try await ops.status()
        XCTAssertEqual(result, .off)
    }

    func testSetBoolSendsAllOrOffAndReadsTheWrappersAnswerBack() async throws {
        let sent = LockedBox<Gryonixnexusd_V1_SetLockdownRequest>()
        let ops = AgentAdminLockdown(client: AgentClient(transport: LockdownMockTransport(
            onUnary: { path, request in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Lockdown/SetLockdown")
                sent.value = try Gryonixnexusd_V1_SetLockdownRequest(serializedBytes: request)
                return try lockdownState(.all)
            })))
        let result = try await ops.set(true)
        XCTAssertEqual(sent.value?.mode, .all)
        XCTAssertEqual(result, .all)
    }

    func testSetFalseSendsOff() async throws {
        let sent = LockedBox<Gryonixnexusd_V1_SetLockdownRequest>()
        let ops = AgentAdminLockdown(client: AgentClient(transport: LockdownMockTransport(
            onUnary: { _, request in
                sent.value = try Gryonixnexusd_V1_SetLockdownRequest(serializedBytes: request)
                return try lockdownState(.off)
            })))
        _ = try await ops.set(false)
        XCTAssertEqual(sent.value?.mode, .off)
    }

    func testSetHostsSendsOnlyWithTheValidHosts() async throws {
        let sent = LockedBox<Gryonixnexusd_V1_SetLockdownRequest>()
        let ops = AgentAdminLockdown(client: AgentClient(transport: LockdownMockTransport(
            onUnary: { _, request in
                sent.value = try Gryonixnexusd_V1_SetLockdownRequest(serializedBytes: request)
                return try lockdownState(.only, hosts: ["a.example.com"])
            })))
        let result = try await ops.set(hosts: ["a.example.com"])
        XCTAssertEqual(sent.value?.mode, .only)
        XCTAssertEqual(sent.value?.hosts, ["a.example.com"])
        XCTAssertEqual(result, .only(["a.example.com"]))
    }

    func testAnInvalidHostRefusesTheWholeChangeInsteadOfGuardingLess() async throws {
        let sent = LockedBox<Gryonixnexusd_V1_SetLockdownRequest>()
        let ops = AgentAdminLockdown(client: AgentClient(transport: LockdownMockTransport(
            onUnary: { _, request in
                sent.value = try Gryonixnexusd_V1_SetLockdownRequest(serializedBytes: request)
                return try lockdownState(.only, hosts: ["a.example.com"])
            })))
        for hosts in [["a.example.com", "evil;rm -rf /"], ["evil;rm -rf /"]] {
            do {
                _ = try await ops.set(hosts: hosts)
                XCTFail("an unguardable name must be refused")
            } catch let error as ServerControlError {
                guard case .commandFailed(_, _, let text) = error else { return XCTFail("\(error)") }
                XCTAssertTrue(text.contains("evil;rm -rf /"))
            }
        }
        XCTAssertNil(sent.value, "nothing may reach the server, least of all an off")
    }

    func testAnEmptyListStillMeansOff() async throws {
        let sent = LockedBox<Gryonixnexusd_V1_SetLockdownRequest>()
        let ops = AgentAdminLockdown(client: AgentClient(transport: LockdownMockTransport(
            onUnary: { _, request in
                sent.value = try Gryonixnexusd_V1_SetLockdownRequest(serializedBytes: request)
                return try lockdownState(.off)
            })))
        let result = try await ops.set(hosts: [])
        XCTAssertEqual(sent.value?.mode, .off)
        XCTAssertEqual(result, .off)
    }

    // MARK: - Failure surfacing

    func testAnRPCFailureSurfacesAsCommandFailed() async throws {
        let ops = AgentAdminLockdown(client: AgentClient(transport: LockdownMockTransport(
            onUnary: { _, _ in
                throw AgentError.rpc(code: "failed_precondition",
                                     message: "this server has no lockdown wrapper")
            })))
        do {
            _ = try await ops.status()
            XCTFail("a refusal should have been rethrown")
        } catch let error as ServerControlError {
            guard case .commandFailed(_, _, let stderr) = error else {
                return XCTFail("expected commandFailed, got \(error)")
            }
            XCTAssertEqual(stderr, "this server has no lockdown wrapper")
        }
    }
}
