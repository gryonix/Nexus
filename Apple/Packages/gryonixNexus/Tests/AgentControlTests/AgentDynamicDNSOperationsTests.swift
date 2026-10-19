import AgentClient
import Foundation
import ServerControl
import SwiftProtobuf
import XCTest
@testable import AgentControl

private struct DNSMockTransport: AgentTransport {
    var onUnary: @Sendable (String, Data) async throws -> Data = { _, _ in Data() }

    func unary(path: String, request: Data) async throws -> Data {
        try await onUnary(path, request)
    }

    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private func state(enabled: Bool,
                   zone: String = "",
                   names: [String] = [],
                   hasToken: Bool = false,
                   recent: [String] = []) throws -> Data {
    var state = Gryonixnexusd_V1_DynamicDNSState()
    state.enabled = enabled
    state.zone = zone
    state.names = names
    state.hasToken_p = hasToken
    state.recent = recent
    return try state.serializedBytes()
}

final class AgentDynamicDNSOperationsTests: XCTestCase {
    func testStateComesBackWithTheRecentRunsTheHostRecorded() async throws {
        let payload = try state(enabled: true,
                                zone: "example.com",
                                names: ["home.example.com"],
                                hasToken: true,
                                recent: ["2026-08-15T17:18:57Z GRYONIXNEXUS_DDNS_UPDATED home.example.com 1.2.3.4 -> 5.6.7.8"])
        let ops = AgentDynamicDNSOperations(client: AgentClient(transport: DNSMockTransport(
            onUnary: { path, _ in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Dns/GetDynamicDNS")
                return payload
            })))

        let answer = try await ops.state()
        XCTAssertTrue(answer.enabled)
        XCTAssertEqual(answer.names, ["home.example.com"])
        XCTAssertTrue(answer.hasToken_p)
        XCTAssertEqual(answer.recent.count, 1)
    }

    /// The credential goes UP and is never read back down
    func testTheAnswerCarriesWhetherATokenIsHeldAndNeverTheTokenItself() async throws {
        let payload = try state(enabled: true, zone: "example.com",
                                names: ["home.example.com"], hasToken: true)
        let ops = AgentDynamicDNSOperations(client: AgentClient(transport: DNSMockTransport(
            onUnary: { _, _ in payload })))

        let answer = try await ops.state()
        XCTAssertTrue(answer.hasToken_p)
        let fields = try answer.jsonString()
        XCTAssertFalse(fields.lowercased().contains("\"token\""), "the state must not carry a token field: \(fields)")
    }

    func testAnEmptyTokenIsSentWhenTheHostAlreadyHoldsOne() async throws {
        let payload = try state(enabled: true, zone: "example.com",
                                names: ["a.example.com", "b.example.com"], hasToken: true)
        let sent = SentRequest()
        let ops = AgentDynamicDNSOperations(client: AgentClient(transport: DNSMockTransport(
            onUnary: { path, body in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Dns/SetDynamicDNS")
                await sent.record(try Gryonixnexusd_V1_SetDynamicDNSRequest(serializedBytes: body))
                return payload
            })))

        _ = try await ops.enable(zone: "example.com", names: ["a.example.com", "b.example.com"])
        let request = await sent.value
        XCTAssertEqual(request?.zone, "example.com")
        XCTAssertEqual(request?.names, ["a.example.com", "b.example.com"])
        XCTAssertEqual(request?.token, "", "an empty token means keep the stored one")
    }

    func testDisableSendsNoNames() async throws {
        let payload = try state(enabled: false)
        let sent = SentRequest()
        let ops = AgentDynamicDNSOperations(client: AgentClient(transport: DNSMockTransport(
            onUnary: { _, body in
                await sent.record(try Gryonixnexusd_V1_SetDynamicDNSRequest(serializedBytes: body))
                return payload
            })))

        let answer = try await ops.disable()
        XCTAssertFalse(answer.enabled)
        let request = await sent.value
        XCTAssertTrue(request?.names.isEmpty ?? false)
    }

    func testARefusalArrivesAsACommandFailureCarryingTheReason() async throws {
        let ops = AgentDynamicDNSOperations(client: AgentClient(transport: DNSMockTransport(
            onUnary: { _, _ in
                throw AgentError.rpc(code: "invalid_argument", message: "a b.example.com is not a hostname")
            })))

        do {
            _ = try await ops.enable(zone: "example.com", names: ["a b.example.com"], token: "t")
            XCTFail("a refused name must throw")
        } catch let error as ServerControlError {
            guard case .commandFailed(_, _, let stderr) = error else {
                return XCTFail("expected a command failure, got \(error)")
            }
            XCTAssertTrue(stderr.contains("is not a hostname"), stderr)
        }
    }

    func testConcurrentCallsAreSerializedByAProvidedGate() async throws {
        let payload = try state(enabled: false)
        let peak = DNSPeak()
        let ops = AgentDynamicDNSOperations(
            client: AgentClient(transport: DNSMockTransport(onUnary: { _, _ in
                await peak.enter()
                try? await Task.sleep(nanoseconds: 2_000_000)
                await peak.leave()
                return payload
            })),
            gate: AgentChannelGate(limit: 1))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 { group.addTask { _ = try? await ops.state() } }
        }
        let highest = await peak.highest
        XCTAssertEqual(highest, 1, "more than one call ran at once under a limit-1 gate")
    }

    func testWithNoGateCallsGenuinelyOverlap() async throws {
        let payload = try state(enabled: false)
        let peak = DNSPeak()
        let ops = AgentDynamicDNSOperations(
            client: AgentClient(transport: DNSMockTransport(onUnary: { _, _ in
                await peak.enter()
                try? await Task.sleep(nanoseconds: 2_000_000)
                await peak.leave()
                return payload
            })))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 { group.addTask { _ = try? await ops.state() } }
        }
        let highest = await peak.highest
        XCTAssertGreaterThan(highest, 1, "calls did not overlap even without a gate — harness is not sensitive")
    }
}

/// Highest number of calls in flight at once
private actor DNSPeak {
    private var current = 0
    private(set) var highest = 0
    func enter() {
        current += 1
        highest = max(highest, current)
    }
    func leave() { current -= 1 }
}

/// Captures the request the seam actually put on the wire
private actor SentRequest {
    private(set) var value: Gryonixnexusd_V1_SetDynamicDNSRequest?
    func record(_ request: Gryonixnexusd_V1_SetDynamicDNSRequest) { value = request }
}
