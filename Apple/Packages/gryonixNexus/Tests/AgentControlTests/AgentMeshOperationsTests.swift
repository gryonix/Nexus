import AgentClient
import Foundation
import ServerControl
import SwiftProtobuf
import XCTest
@testable import AgentControl

/// The mesh seam — the one the screen calls
private struct MeshMockTransport: AgentTransport {
    var onUnary: @Sendable (String, Data) async throws -> Data = { _, _ in Data() }

    func unary(path: String, request: Data) async throws -> Data {
        try await onUnary(path, request)
    }

    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private func nodeList(_ rows: [(id: String, name: String, addresses: [String], user: String,
                                online: Bool, lastSeen: Int64)]) throws -> Data {
    var list = Gryonixnexusd_V1_MeshNodeList()
    list.nodes = rows.map { row in
        var node = Gryonixnexusd_V1_MeshNode()
        node.id = row.id
        node.name = row.name
        node.addresses = row.addresses
        node.user = row.user
        node.online = row.online
        node.lastSeen = row.lastSeen
        return node
    }
    return try list.serializedBytes()
}

private func nameList(_ rows: [(name: String, address: String)]) throws -> Data {
    var list = Gryonixnexusd_V1_MeshNameList()
    list.records = rows.map { row in
        var record = Gryonixnexusd_V1_MeshName()
        record.name = row.name
        record.address = row.address
        return record
    }
    return try list.serializedBytes()
}

@available(macOS 15.0, *)
final class AgentMeshOperationsTests: XCTestCase {
    // MARK: - Nodes

    func testANodeCarriesItsAddressUserAndOnlineState() async throws {
        let payload = try nodeList([
            (id: "1", name: "b5", addresses: ["100.64.0.1", "fd7a:115c:a1e0::1"],
             user: "gryonixnexus", online: true, lastSeen: 1_700_000_000),
        ])
        let ops = AgentMeshOperations(client: AgentClient(transport: MeshMockTransport(
            onUnary: { path, _ in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Mesh/ListMeshNodes")
                return payload
            })))

        let nodes = try await ops.nodes()
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].name, "b5")
        XCTAssertEqual(nodes[0].addresses.first, "100.64.0.1")
        XCTAssertEqual(nodes[0].user, "gryonixnexus")
        XCTAssertTrue(nodes[0].isOnline)
        XCTAssertNotNil(nodes[0].lastSeen)
    }

    func testAnUnknownLastSeenIsNilRatherThanNineteenSeventy() async throws {
        let payload = try nodeList([
            (id: "1", name: "b5", addresses: ["100.64.0.1"], user: "u", online: false, lastSeen: 0),
        ])
        let ops = AgentMeshOperations(client: AgentClient(transport: MeshMockTransport(
            onUnary: { _, _ in payload })))

        let nodes = try await ops.nodes()
        XCTAssertNil(nodes[0].lastSeen)
    }

    // MARK: - Publishing names

    func testPublishingSendsTheNamesAndReadsBackWhatTheServerWrote() async throws {
        let payload = try nameList([
            (name: "vault.example.com", address: "100.64.0.1"),
            (name: "cloud.example.com", address: "100.64.0.1"),
        ])
        let sent = Sent()
        let ops = AgentMeshOperations(client: AgentClient(transport: MeshMockTransport(
            onUnary: { path, request in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Mesh/PublishMeshNames")
                await sent.record(try Gryonixnexusd_V1_PublishMeshNamesRequest(serializedBytes: request))
                return payload
            })))

        let records = try await ops.publishNames(["vault.example.com", "cloud.example.com"])

        let request = await sent.request
        XCTAssertEqual(request?.names, ["vault.example.com", "cloud.example.com"])
        XCTAssertEqual(request?.nodeName, "")
        XCTAssertEqual(records.map(\.name), ["vault.example.com", "cloud.example.com"])
        XCTAssertEqual(Set(records.map(\.address)), ["100.64.0.1"])
    }

    func testPublishingNothingStillCallsTheServer() async throws {
        let payload = try nameList([])
        let calls = Counter()
        let ops = AgentMeshOperations(client: AgentClient(transport: MeshMockTransport(
            onUnary: { _, _ in
                await calls.bump()
                return payload
            })))

        let records = try await ops.publishNames([])
        XCTAssertTrue(records.isEmpty)
        let count = await calls.value
        XCTAssertEqual(count, 1, "an empty publish must still be sent — it is what clears the names")
    }

    // MARK: - The gate

    func testConcurrentCallsAreSerializedByAProvidedGate() async throws {
        let gate = AgentChannelGate(limit: 1)
        let peak = Peak()
        let payload = try nodeList([])
        let ops = AgentMeshOperations(
            client: AgentClient(transport: MeshMockTransport(onUnary: { _, _ in
                await peak.enter()
                try? await Task.sleep(nanoseconds: 2_000_000)
                await peak.leave()
                return payload
            })),
            gate: gate)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask { _ = try? await ops.nodes() }
            }
        }
        let highest = await peak.highest
        XCTAssertEqual(highest, 1, "more than one call ran at once under a limit-1 gate")
    }

    func testWithNoGateCallsGenuinelyOverlap() async throws {
        let peak = Peak()
        let payload = try nodeList([])
        let ops = AgentMeshOperations(
            client: AgentClient(transport: MeshMockTransport(onUnary: { _, _ in
                await peak.enter()
                try? await Task.sleep(nanoseconds: 2_000_000)
                await peak.leave()
                return payload
            })))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask { _ = try? await ops.nodes() }
            }
        }
        let highest = await peak.highest
        XCTAssertGreaterThan(highest, 1, "calls did not overlap even without a gate — harness is not sensitive")
    }

    func testPublishingGoesThroughTheGateAsWell() async throws {
        let gate = AgentChannelGate(limit: 1)
        let peak = Peak()
        let payload = try nameList([])
        let ops = AgentMeshOperations(
            client: AgentClient(transport: MeshMockTransport(onUnary: { _, _ in
                await peak.enter()
                try? await Task.sleep(nanoseconds: 2_000_000)
                await peak.leave()
                return payload
            })),
            gate: gate)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask { _ = try? await ops.publishNames(["a.example.com"]) }
            }
        }
        let highest = await peak.highest
        XCTAssertEqual(highest, 1, "publishing bypassed the gate")
    }

    // MARK: - Refusals

    func testTheServersOwnWordsSurviveAsTheErrorMessage() async throws {
        let ops = AgentMeshOperations(client: AgentClient(transport: MeshMockTransport(
            onUnary: { _, _ in
                throw AgentError.rpc(code: "failed_precondition",
                                     message: "this server does not run Headscale")
            })))
        do {
            _ = try await ops.publishNames(["vault.example.com"])
            XCTFail("the failure should have been rethrown")
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(text.contains("does not run Headscale"), text)
        }
    }

    // MARK: - Helpers

    private actor Peak {
        private(set) var current = 0
        private(set) var highest = 0
        func enter() { current += 1; highest = max(highest, current) }
        func leave() { current -= 1 }
    }

    private actor Counter {
        private(set) var value = 0
        func bump() { value += 1 }
    }

    private actor Sent {
        private(set) var request: Gryonixnexusd_V1_PublishMeshNamesRequest?
        func record(_ request: Gryonixnexusd_V1_PublishMeshNamesRequest) { self.request = request }
    }
}
