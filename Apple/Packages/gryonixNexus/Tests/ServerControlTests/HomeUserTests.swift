import XCTest
@testable import ServerControl

final class HomeUserTests: XCTestCase {
    private func relay(homeUser: String?) -> Deployment {
        Deployment(name: "R", topology: .vpsRelayWithHomeBackend, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "server-user"),
                   homeWGAddress: "10.8.0.2", homeUser: homeUser)
    }

    func testHomeNodeUsesItsOwnUserAndRoundTrips() throws {
        let decoded = try JSONDecoder().decode(
            Deployment.self, from: JSONEncoder().encode(relay(homeUser: "root")))
        XCTAssertEqual(decoded.homeUser, "root")
        XCTAssertEqual(decoded.nodes[1].endpoint.user, "root")
        XCTAssertEqual(decoded.nodes[0].endpoint.user, "server-user")
        XCTAssertEqual(decoded.dashboardConfig.homeSSHUser, "root")
    }

    func testNilHomeUserIsOmittedAndFallsBackToEntryUser() throws {
        let deployment = relay(homeUser: nil)
        let json = try String(decoding: JSONEncoder().encode(deployment), as: UTF8.self)
        XCTAssertFalse(json.contains("homeUser"))
        XCTAssertEqual(deployment.nodes[1].endpoint.user, "server-user")
    }
}
