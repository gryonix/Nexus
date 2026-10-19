import AgentClient
import Foundation
import ServerControl
import SwiftProtobuf
import XCTest
@testable import AgentControl

private struct DeviceMockTransport: AgentTransport {
    var onUnary: @Sendable (String, Data) async throws -> Data = { _, _ in Data() }

    func unary(path: String, request: Data) async throws -> Data {
        try await onUnary(path, request)
    }

    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private func deviceList(_ rows: [(id: String, publicKey: String, label: String, pairedAt: Int64)]) throws -> Data {
    var list = Gryonixnexusd_V1_DeviceList()
    list.devices = rows.map { row in
        var device = Gryonixnexusd_V1_Device()
        device.id = row.id
        device.publicKey = row.publicKey
        device.label = row.label
        device.pairedAt = row.pairedAt
        return device
    }
    return try list.serializedBytes()
}

private func revokeResponse(_ revoked: Bool) throws -> Data {
    var response = Gryonixnexusd_V1_RevokeResponse()
    response.revoked = revoked
    return try response.serializedBytes()
}

final class AgentDeviceOperationsTests: XCTestCase {
    // MARK: - ListDevices

    func testDevicesComeBackWithLabelAndPairedAt() async throws {
        let payload = try deviceList([
            (id: "abc123", publicKey: "ssh-ed25519 AAAA...", label: "Morgan's iPhone", pairedAt: 1_700_000_000_000),
        ])
        let ops = AgentDeviceOperations(client: AgentClient(transport: DeviceMockTransport(
            onUnary: { path, _ in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Pairing/ListDevices")
                return payload
            })))

        let devices = try await ops.listDevices()
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].id, "abc123")
        XCTAssertEqual(devices[0].label, "Morgan's iPhone")
        XCTAssertEqual(devices[0].publicKey, "ssh-ed25519 AAAA...")
        XCTAssertEqual(devices[0].pairedAt, 1_700_000_000_000)
    }

    func testNoDevicesYetIsAnEmptyListNotAFailure() async throws {
        let payload = try deviceList([])
        let ops = AgentDeviceOperations(client: AgentClient(transport: DeviceMockTransport(
            onUnary: { _, _ in payload })))
        let devices = try await ops.listDevices()
        XCTAssertTrue(devices.isEmpty)
    }

    func testMultipleDevicesAllComeBackInOrder() async throws {
        let payload = try deviceList([
            (id: "a", publicKey: "key-a", label: "Mac", pairedAt: 1),
            (id: "b", publicKey: "key-b", label: "iPad", pairedAt: 2),
        ])
        let ops = AgentDeviceOperations(client: AgentClient(transport: DeviceMockTransport(
            onUnary: { _, _ in payload })))
        let devices = try await ops.listDevices()
        XCTAssertEqual(devices.map(\.id), ["a", "b"])
    }

    // MARK: - Revoke

    func testRevokeSendsTheDeviceIDAndReportsSuccess() async throws {
        let ops = AgentDeviceOperations(client: AgentClient(transport: DeviceMockTransport(
            onUnary: { path, request in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Pairing/Revoke")
                let decoded = try Gryonixnexusd_V1_RevokeRequest(serializedBytes: request)
                XCTAssertEqual(decoded.deviceID, "abc123")
                return try revokeResponse(true)
            })))
        let revoked = try await ops.revoke(deviceID: "abc123")
        XCTAssertTrue(revoked)
    }

    func testRevokingAnAlreadyGoneDeviceReportsFalseRatherThanThrowing() async throws {
        let ops = AgentDeviceOperations(client: AgentClient(transport: DeviceMockTransport(
            onUnary: { _, _ in try revokeResponse(false) })))
        let revoked = try await ops.revoke(deviceID: "unknown")
        XCTAssertFalse(revoked)
    }

    // MARK: - The gate

    private actor Peak {
        private(set) var current = 0
        private(set) var highest = 0
        func enter() { current += 1; highest = max(highest, current) }
        func leave() { current -= 1 }
    }

    func testConcurrentCallsAreSerializedByAProvidedGate() async throws {
        let gate = AgentChannelGate(limit: 1)
        let peak = Peak()
        let payload = try deviceList([])
        let ops = AgentDeviceOperations(
            client: AgentClient(transport: DeviceMockTransport(onUnary: { _, _ in
                await peak.enter()
                try? await Task.sleep(nanoseconds: 2_000_000)
                await peak.leave()
                return payload
            })),
            gate: gate)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask { _ = try? await ops.listDevices() }
            }
        }
        let highest = await peak.highest
        XCTAssertEqual(highest, 1, "more than one call ran at once under a limit-1 gate")
    }

    func testWithNoGateCallsGenuinelyOverlap() async throws {
        let peak = Peak()
        let payload = try deviceList([])
        let ops = AgentDeviceOperations(
            client: AgentClient(transport: DeviceMockTransport(onUnary: { _, _ in
                await peak.enter()
                try? await Task.sleep(nanoseconds: 2_000_000)
                await peak.leave()
                return payload
            })))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask { _ = try? await ops.listDevices() }
            }
        }
        let highest = await peak.highest
        XCTAssertGreaterThan(highest, 1, "calls did not overlap even without a gate — harness is not sensitive")
    }

    // MARK: - Refusals

    func testTheServersOwnWordsSurviveAsTheErrorMessage() async throws {
        let ops = AgentDeviceOperations(client: AgentClient(transport: DeviceMockTransport(
            onUnary: { _, _ in
                throw AgentError.rpc(code: "not_found", message: "no such device")
            })))
        do {
            _ = try await ops.revoke(deviceID: "ghost")
            XCTFail("the failure should have been rethrown")
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(text.contains("no such device"), text)
        }
    }
}
