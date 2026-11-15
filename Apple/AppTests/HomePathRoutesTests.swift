import ServerControl
import ServerControlSSH
import XCTest

@testable import gryonixNexus

@available(macOS 15.0, *)
final class HomePathRoutesTests: XCTestCase {
    private let routes = [
        TerminalEndpoint(host: "192.168.1.5", port: 22, pinnedHostKey: nil, kind: .localNetwork),
        TerminalEndpoint(host: "10.8.0.2", port: 22, pinnedHostKey: nil, kind: .relay),
        TerminalEndpoint(host: "10.8.0.2", port: 22, pinnedHostKey: nil, kind: .tunnelAddress),
    ]

    func testAutomaticKeepsEveryRoute() {
        let kept = TerminalEndpointBuilder.allowed(routes, by: .automatic, routed: true)
        XCTAssertEqual(kept.map(\.kind), [.localNetwork, .relay, .tunnelAddress])
    }

    func testThroughTheVPSDropsTheLocalNetwork() {
        let kept = TerminalEndpointBuilder.allowed(routes, by: .throughVPS, routed: true)
        XCTAssertEqual(kept.map(\.kind), [.relay, .tunnelAddress])
    }

    func testOverTheLocalNetworkKeepsOnlyIt() {
        let kept = TerminalEndpointBuilder.allowed(routes, by: .localNetwork, routed: true)
        XCTAssertEqual(kept.map(\.kind), [.localNetwork])
    }

    func testAMachineNotBehindTheVPSIgnoresTheChoice() {
        let kept = TerminalEndpointBuilder.allowed(routes, by: .localNetwork, routed: false)
        XCTAssertEqual(kept.count, 3)
    }

    func testTheRowReportsTheChoiceOrTheRouteThatWorkedLast() {
        let defaults = UserDefaults(suiteName: "HomePathRoutesTests")!
        defaults.removePersistentDomain(forName: "HomePathRoutesTests")
        let server = UUID(), node = UUID()
        XCTAssertEqual(TerminalEndpointBuilder.pathInUse(choice: .automatic, deploymentID: server,
                                                         nodeID: node, defaults: defaults), .throughVPS)
        defaults.set("localNetwork", forKey: "terminal.route.\(server.uuidString).\(node.uuidString)")
        XCTAssertEqual(TerminalEndpointBuilder.pathInUse(choice: .automatic, deploymentID: server,
                                                         nodeID: node, defaults: defaults), .localNetwork)
        XCTAssertEqual(TerminalEndpointBuilder.pathInUse(choice: .throughVPS, deploymentID: server,
                                                         nodeID: node, defaults: defaults), .throughVPS)
    }
}
