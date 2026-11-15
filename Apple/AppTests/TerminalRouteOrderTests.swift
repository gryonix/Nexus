import ServerControl
import ServerControlSSH
import XCTest

@testable import gryonixNexus

@available(macOS 15.0, *)
final class TerminalRouteOrderTests: XCTestCase {
    private var defaults: UserDefaults!
    private let key = "terminal.route.test"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "TerminalRouteOrderTests")
        defaults.removePersistentDomain(forName: "TerminalRouteOrderTests")
    }

    private func route(_ host: String, _ kind: TerminalEndpoint.Kind) -> TerminalEndpoint {
        TerminalEndpoint(host: host, port: 22, pinnedHostKey: nil, kind: kind)
    }

    func testWithNothingRememberedTheOrderStays() {
        let routes = [route("192.168.1.5", .localNetwork), route("10.8.0.2", .relay)]
        XCTAssertEqual(TerminalEndpointBuilder.ordered(routes, key: key, defaults: defaults).map(\.kind),
                       [.localNetwork, .relay])
    }

    func testTheRouteThatWorkedLastGoesFirst() {
        let routes = [route("192.168.1.5", .localNetwork), route("10.8.0.2", .relay),
                      route("10.8.0.2", .tunnelAddress)]
        TerminalEndpointBuilder.remember(routes[2], key: key, defaults: defaults)
        XCTAssertEqual(TerminalEndpointBuilder.ordered(routes, key: key, defaults: defaults).map(\.kind),
                       [.tunnelAddress, .localNetwork, .relay])
    }

    func testARememberedRouteThatIsGoneChangesNothing() {
        defaults.set("fallbackAddress", forKey: key)
        let routes = [route("203.0.113.4", .direct)]
        XCTAssertEqual(TerminalEndpointBuilder.ordered(routes, key: key, defaults: defaults).map(\.kind), [.direct])
    }

    func testPrivateAddressesAreTheOnesATunnelReaches() {
        for host in ["10.8.0.2", "192.168.1.5", "172.20.0.4", "100.64.1.2", "fd00::1", "nas.local"] {
            XCTAssertTrue(TerminalVPNOffer.isPrivate(host), host)
        }
        for host in ["203.0.113.4", "172.32.0.1", "example.com", "8.8.8.8", "fdroid.example"] {
            XCTAssertFalse(TerminalVPNOffer.isPrivate(host), host)
        }
    }

    // MARK: - Into a home network

    private func pair() -> Deployment {
        Deployment(name: "B", topology: .vpsRelayWithHomeBackend, domain: "example.test",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                   homeWGAddress: "10.8.0.2")
    }

    func testTheHomeMachineByItsTunnelAddressGoesThroughTheRelay() {
        let routes = TerminalEndpointBuilder.homeDetours(to: "10.8.0.2", port: 22, pinned: nil,
                                                         from: UUID(), fleet: [pair()])
        XCTAssertEqual(routes.map(\.kind), [.relay, .tunnelAddress])
        XCTAssertEqual(routes.first?.hops.map(\.host), ["203.0.113.10"])
        XCTAssertEqual(routes.first?.host, "10.8.0.2")
    }

    func testANeighbourOnTheHomeNetworkIsReachedThroughTheHomeMachine() {
        let routes = TerminalEndpointBuilder.homeDetours(to: "192.168.1.40", port: 22, pinned: nil,
                                                         from: UUID(), fleet: [pair()])
        XCTAssertEqual(routes.map(\.kind), [.relay])
        XCTAssertEqual(routes.first?.hops.map(\.host), ["203.0.113.10", "10.8.0.2"])
        XCTAssertEqual(routes.first?.host, "192.168.1.40")
    }

    func testANameOnTheHomeNetworkIsAskedOfTheHomeMachine() {
        let routes = TerminalEndpointBuilder.homeDetours(to: "orion.local", port: 22, pinned: nil,
                                                         from: UUID(), fleet: [pair()])
        XCTAssertEqual(routes.first?.hops.map(\.host), ["203.0.113.10", "10.8.0.2"])
        XCTAssertEqual(routes.first?.host, "orion.local")
    }

    func testThePublicInternetAndTheServersOwnMachinesGetNoDetour() {
        let fleet = [pair()]
        XCTAssertTrue(TerminalEndpointBuilder.homeDetours(to: "203.0.113.50", port: 22, pinned: nil,
                                                          from: UUID(), fleet: fleet).isEmpty)
        XCTAssertTrue(TerminalEndpointBuilder.homeDetours(to: "10.8.0.2", port: 22, pinned: nil,
                                                          from: fleet[0].id, fleet: fleet).isEmpty)
    }

    func testTheHomeMachineIsKnownByItsNameWithOrWithoutLocal() throws {
        let server = pair()
        let home = try XCTUnwrap(server.nodes.first { $0.routedThrough != nil })
        var named = home
        named.name = "Orion"
        XCTAssertTrue(TerminalEndpointBuilder.names(named, "orion.local", in: server))
        XCTAssertTrue(TerminalEndpointBuilder.names(named, "10.8.0.2", in: server))
        XCTAssertFalse(TerminalEndpointBuilder.names(named, "draco.local", in: server))
    }

    // MARK: - Through a chosen machine

    func testAChosenServerIsTheJumpHostForAnyAddress() {
        let server = pair()
        let routes = TerminalEndpointBuilder.chosenRoutes(to: "192.168.1.40", port: 22, pinned: nil,
                                                          via: TerminalVia(server: server.id), fleet: [server])
        XCTAssertEqual(routes.map(\.kind), [.relay])
        XCTAssertEqual(routes.first?.hops.map(\.host), ["203.0.113.10"])
        XCTAssertEqual(routes.first?.host, "192.168.1.40")
    }

    func testAChosenHomeMachineIsReachedThroughItsServer() throws {
        let server = pair()
        let home = try XCTUnwrap(server.nodes.first { $0.routedThrough != nil })
        let routes = TerminalEndpointBuilder.chosenRoutes(to: "192.168.1.40", port: 22, pinned: nil,
                                                          via: TerminalVia(server: server.id, node: home.id),
                                                          fleet: [server])
        XCTAssertEqual(routes.first?.hops.map(\.host), ["203.0.113.10", "10.8.0.2"])
    }

    func testAServerThatIsGoneGivesNoRoute() {
        XCTAssertTrue(TerminalEndpointBuilder.chosenRoutes(to: "192.168.1.40", port: 22, pinned: nil,
                                                           via: TerminalVia(server: UUID()), fleet: [pair()]).isEmpty)
    }

    func testEveryMachineWithAnAddressIsOffered() {
        let server = pair()
        let titles = TerminalViaSection.choices(in: [server]).map(\.title)
        XCTAssertEqual(titles.count, 2)
        XCTAssertEqual(titles.first, "B")
    }

    func testAFailedDirectTryAtAHomeAddressSaysHowToGoThroughAServer() {
        let only = route("192.168.1.40", .direct)
        let text = TerminalController.describe(ServerControlError.connectionFailed("Host is down"), routes: [only])
        XCTAssertTrue(text.contains("192.168.1.40:22"), text)
        XCTAssertTrue(text.contains("Host is down"), text)
        XCTAssertTrue(text.contains("Through a server"), text)
    }

    func testEveryTriedWayIsNamed() {
        let failed = TerminalRoutesFailed(attempts: [(route("192.168.1.40", .direct), "Host is down"),
                                                     (route("10.8.0.2", .relay), "timed out")])
        let lines = TerminalController.describe(failed, routes: []).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("timed out"))
    }
}
