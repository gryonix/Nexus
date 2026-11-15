import Foundation
import ServerControl
import XCTest
@testable import ServerControlSSH

@available(macOS 15.0, *)
final class TerminalRouteTests: XCTestCase {
    private let login = TerminalLogin(username: "root", secret: .password("x"))

    func testARouteThatDidNotAnswerLetsTheNextOneTry() {
        XCTAssertTrue(TerminalSession.mayTryAnotherRoute(after: ServerControlError.connectionFailed("refused")))
        XCTAssertTrue(TerminalSession.mayTryAnotherRoute(after: ServerControlError.timeout(command: "dial")))
    }

    func testAWrongKeyOrSettingStopsAtTheFirstRoute() {
        XCTAssertFalse(TerminalSession.mayTryAnotherRoute(after: ServerControlError.hostKeyMismatch(host: "h")))
        XCTAssertFalse(TerminalSession.mayTryAnotherRoute(after: ServerControlError.notConfigured("no key")))
        XCTAssertFalse(TerminalSession.mayTryAnotherRoute(after: CancellationError()))
    }

    func testTheSummaryNamesThePathOutermostFirst() {
        let hop = TerminalEndpoint.Hop(host: "203.0.113.4", port: 22, pinnedHostKey: nil, login: login)
        let relayed = TerminalEndpoint(host: "10.8.0.2", port: 22, pinnedHostKey: nil, parent: hop, kind: .relay)
        XCTAssertEqual(relayed.summary, "203.0.113.4:22 → 10.8.0.2:22")
        XCTAssertEqual(TerminalEndpoint(host: "192.168.1.5", port: 2222, pinnedHostKey: nil).summary,
                       "192.168.1.5:2222")
    }

    func testAChainNamesEveryMachineFromTheOutermost() {
        let relay = TerminalEndpoint.Hop(host: "203.0.113.4", port: 22, pinnedHostKey: nil, login: login)
        let home = TerminalEndpoint.Hop(host: "10.8.0.2", port: 22, pinnedHostKey: nil, login: login)
        let chained = TerminalEndpoint(host: "192.168.1.5", port: 22, pinnedHostKey: nil,
                                       parent: home, outer: [relay], kind: .relay)
        XCTAssertEqual(chained.hops.map(\.host), ["203.0.113.4", "10.8.0.2"])
        XCTAssertEqual(chained.summary, "203.0.113.4:22 → 10.8.0.2:22 → 192.168.1.5:22")
    }

    func testEveryFailedRouteIsNamedWithItsReason() {
        let lan = TerminalEndpoint(host: "192.168.1.5", port: 22, pinnedHostKey: nil, kind: .localNetwork)
        let tunnel = TerminalEndpoint(host: "10.8.0.2", port: 22, pinnedHostKey: nil, kind: .tunnelAddress)
        let failed = TerminalRoutesFailed(attempts: [(lan, "timed out"), (tunnel, "no route")])
        XCTAssertEqual(failed.description, "192.168.1.5:22: timed out\n10.8.0.2:22: no route")
    }

    func testTheKeepaliveRunsInsideTheTunnelsIdleLimit() {
        XCTAssertLessThan(TerminalSession.keepaliveInterval, .seconds(30))
    }

    func testTheSharedLinkKeepaliveRunsInsideTheTunnelsIdleLimit() {
        XCTAssertLessThan(CitadelCommandRunner.keepaliveInterval, .seconds(30))
    }
}
