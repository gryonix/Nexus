import ServiceCatalog
import XCTest
@testable import VPNTunnel

final class SimulatedTunnelEngineTests: XCTestCase {
    private func profile(protocolID: ServiceID = .wireguardVPN) -> TunnelProfile {
        TunnelProfile(serverID: UUID(), serverName: "Home", protocolID: protocolID,
                      deviceID: "device-1", deviceName: "iPhone",
                      endpoint: "vpn.example.com:51820", addresses: ["10.9.0.4/32"])
    }

    private func engine() -> SimulatedTunnelEngine {
        SimulatedTunnelEngine(timing: .immediate, bytesPerTick: 1_000)
    }

    /// Waits for the first state matching `predicate`, or fails
    private func wait(on engine: SimulatedTunnelEngine,
                      timeout: TimeInterval = 5,
                      for predicate: @escaping @Sendable (TunnelEngineState) -> Bool) async throws
        -> TunnelEngineState {
        let deadline = Date().addingTimeInterval(timeout)
        for await state in engine.events() {
            if predicate(state) { return state }
            if Date() > deadline { break }
        }
        XCTFail("no matching state before the deadline")
        throw CancellationError()
    }

    func testAFreshEngineIsOff() async {
        let engine = engine()
        let state = await engine.state()
        XCTAssertEqual(state.status, .off)
        XCTAssertNil(state.profileID)
    }

    func testASubscriberIsHandedTheCurrentStateImmediately() async throws {
        let engine = engine()
        var iterator = engine.events().makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first?.status, .off)
    }

    func testConnectingWalksThroughConnectingToConnected() async throws {
        let engine = engine()
        let profile = profile()
        var seen: [TunnelStatus] = []
        let watcher = Task {
            for await state in engine.events() {
                seen.append(state.status)
                if state.status.isActive { break }
            }
            return seen
        }
        try await engine.start(profile: profile, secret: "[Interface]\n[Peer]")
        let states = await watcher.value

        XCTAssertTrue(states.contains(.connecting), "the handshake must be visible, not skipped")
        XCTAssertTrue(states.last?.isActive == true)
        let state = await engine.state()
        XCTAssertEqual(state.profileID, profile.id)
        await engine.stop()
    }

    func testCountersMoveWhileConnected() async throws {
        let engine = engine()
        try await engine.start(profile: profile(), secret: "[Interface]\n[Peer]")
        let state = try await wait(on: engine) { $0.statistics.received > 0 }
        XCTAssertGreaterThan(state.statistics.received, 0)
        XCTAssertGreaterThan(state.statistics.sent, 0)
        XCTAssertNotNil(state.statistics.lastHandshake)
        await engine.stop()
    }

    func testStoppingEndsAtOffAndLeavesTheCountersAlone() async throws {
        let engine = engine()
        try await engine.start(profile: profile(), secret: "[Interface]\n[Peer]")
        _ = try await wait(on: engine) { $0.statistics.received > 0 }
        await engine.stop()

        let state = await engine.state()
        XCTAssertEqual(state.status, .off)
        XCTAssertGreaterThan(state.statistics.received, 0,
                             "the session's totals survive the disconnect that ends it")
    }

    func testAnArmedFailureSurfacesAsFailedRatherThanConnected() async throws {
        let engine = engine()
        await engine.armFailure("The server did not answer the handshake.")
        try await engine.start(profile: profile(), secret: "[Interface]\n[Peer]")

        let state = try await wait(on: engine) { $0.status.failureReason != nil }
        XCTAssertEqual(state.status.failureReason, "The server did not answer the handshake.")
        XCTAssertFalse(state.status.isActive)
    }

    func testAnArmedFailureIsConsumedByTheStartItFails() async throws {
        let engine = engine()
        await engine.armFailure("once")
        try await engine.start(profile: profile(), secret: "x")
        _ = try await wait(on: engine) { $0.status.failureReason != nil }

        try await engine.start(profile: profile(), secret: "x")
        let state = try await wait(on: engine) { $0.status.isActive }
        XCTAssertTrue(state.status.isActive)
        await engine.stop()
    }

    /// Refused before anything is published
    func testAProtocolWithNoDatapathIsRefusedUpFront() async {
        let engine = engine()
        let unknown = ServiceID(rawValue: "some-future-protocol")
        do {
            try await engine.start(profile: profile(protocolID: unknown), secret: "x")
            XCTFail("a protocol with no datapath must not be accepted by the tunnel engine")
        } catch {
            XCTAssertEqual(error as? TunnelEngineError, .protocolNotCarried(unknown))
        }
        let state = await engine.state()
        XCTAssertEqual(state.status, .off, "a refusal must not leave the engine mid-connect")
    }

    func testEveryCarriedProtocolStarts() async throws {
        for id in TunnelCapableProtocols.all where TunnelCapableProtocols.isIntegrated(id) {
            let engine = engine()
            try await engine.start(profile: profile(protocolID: id), secret: "x")
            let state = try await wait(on: engine) { $0.status.isActive }
            XCTAssertTrue(state.status.isActive, "\(id.displayName) did not come up")
            await engine.stop()
        }
    }

    func testAProtocolWithNoRuntimeInThisBuildIsRefusedToo() async {
        let named = TunnelCapableProtocols.all.filter {
            TunnelCapableProtocols.carries($0) && !TunnelCapableProtocols.isIntegrated($0)
        }
        XCTAssertEqual(named, [.openVPN],
                       "the set of named-but-unlinked datapaths changed — LICENSE decides with it")
        for id in named {
            let engine = engine()
            do {
                try await engine.start(profile: profile(protocolID: id), secret: "x")
                XCTFail("\(id.displayName) has no runtime in this build and must not start")
            } catch {
                XCTAssertEqual(error as? TunnelEngineError, .protocolNotCarried(id))
            }
            let state = await engine.state()
            XCTAssertEqual(state.status, .off, "a refusal must not leave the engine mid-connect")
        }
    }

    func testAnEmptyConfigurationIsRefusedRatherThanConnectedWithNothing() async {
        let engine = engine()
        do {
            try await engine.start(profile: profile(), secret: "   \n  ")
            XCTFail("an empty configuration must not start a tunnel")
        } catch {
            XCTAssertEqual(error as? TunnelEngineError, .configurationMissing)
        }
    }

    func testStartingASecondProfileReplacesTheFirst() async throws {
        let engine = engine()
        try await engine.start(profile: profile(), secret: "x")
        _ = try await wait(on: engine) { $0.status.isActive }

        let second = profile()
        try await engine.start(profile: second, secret: "x")
        let state = try await wait(on: engine) { $0.status.isActive && $0.profileID == second.id }
        XCTAssertEqual(state.profileID, second.id)
        await engine.stop()
    }

    func testTunnelKindMatchesTheBuild() {
        #if targetEnvironment(simulator)
        XCTAssertEqual(TunnelAvailability.kind, .simulated)
        XCTAssertFalse(TunnelAvailability.carriesTraffic)
        #else
        XCTAssertEqual(TunnelAvailability.kind, .system)
        XCTAssertTrue(TunnelAvailability.carriesTraffic)
        #endif
    }
}

extension TunnelAvailability.Kind: Equatable {}
