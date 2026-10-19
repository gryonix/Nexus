import AgentClient
import ServiceCatalog
import VPNTunnel
import XCTest
@testable import gryonixNexus

/// The server's pushed state must decode as the app's own
@MainActor
final class TunnelActivityPushTests: XCTestCase {
    func testTheServersStateDecodesAsTheActivitysState() throws {
        let since = Date(timeIntervalSinceReferenceDate: 812_000_000)
        let pushed = #"{"status":{"connected":{"since":812000000}},"statistics":{"received":2048,"sent":512}}"#
        let state = try JSONDecoder().decode(TunnelActivityAttributes.ContentState.self,
                                             from: Data(pushed.utf8))
        XCTAssertEqual(state.status, .connected(since: since))
        XCTAssertEqual(state.statistics, TunnelStatistics(received: 2048, sent: 512))
    }

    func testTheReconnectingStateDecodesToo() throws {
        let pushed = #"{"status":{"reasserting":{"since":812000000}},"statistics":{"received":0,"sent":0}}"#
        let state = try JSONDecoder().decode(TunnelActivityAttributes.ContentState.self,
                                             from: Data(pushed.utf8))
        XCTAssertEqual(state.status, .reasserting(since: Date(timeIntervalSinceReferenceDate: 812_000_000)))
    }

    func testTheRequestNamesTheTunnelAddressAndStart() {
        let profile = TunnelProfile(serverID: UUID(), serverName: "gvps", protocolID: .wireguardVPN,
                                    deviceID: "d1", deviceName: "iPhone", endpoint: "vpn.example.com:51820",
                                    addresses: ["10.9.0.4/32", "fd09::4/128"])
        let since = Date(timeIntervalSinceReferenceDate: 812_000_000)
        let request = TunnelActivityPush.request(token: "ab12", profile: profile, since: since)
        XCTAssertEqual(request.token, "ab12")
        XCTAssertEqual(request.protocol, "wireguard-vpn")
        XCTAssertEqual(request.address, "10.9.0.4/32")
        XCTAssertEqual(request.startedAt, 812_000_000)
        XCTAssertFalse(request.stop)
    }
}
