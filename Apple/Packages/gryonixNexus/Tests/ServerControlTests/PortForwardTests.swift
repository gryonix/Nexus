import XCTest
@testable import ServerControl

final class PortForwardTests: XCTestCase {
    private let server = UUID()

    func testValidForwardHasNoProblems() {
        let forward = PortForward(deploymentID: server, localPort: 8080, remoteHost: "localhost", remotePort: 80)
        XCTAssertEqual(forward.problems(among: []), [])
        XCTAssertEqual(forward.summary, "127.0.0.1:8080 → localhost:80")
    }

    func testRejectsBadPortsAndHost() {
        let forward = PortForward(deploymentID: server, localPort: 80, remoteHost: "a b", remotePort: 70000)
        XCTAssertEqual(Set(forward.problems(among: [])), [.localPort, .remoteHost, .remotePort])
    }

    func testDuplicateLocalPortIsFlagged() {
        let first = PortForward(deploymentID: server, localPort: 5432, remotePort: 5432)
        let second = PortForward(deploymentID: UUID(), localPort: 5432, remotePort: 3306)
        XCTAssertEqual(second.problems(among: [first]), [.duplicateLocalPort])
        XCTAssertEqual(first.problems(among: [first]), [])
    }

    func testListEditsAndCodableRoundTrip() throws {
        let one = PortForward(deploymentID: server, localPort: 9000, remotePort: 9000)
        var two = PortForward(deploymentID: UUID(), localPort: 9001, remotePort: 9001)
        var all = PortForwardList.upserting(two, into: PortForwardList.upserting(one, into: []))
        two.name = "db"
        all = PortForwardList.upserting(two, into: all)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(PortForwardList.forServer(server, in: all), [one])
        XCTAssertEqual(PortForwardList.removingServer(server, from: all), [two])
        let decoded = try JSONDecoder().decode([PortForward].self, from: JSONEncoder().encode(all))
        XCTAssertEqual(decoded, all)
        XCTAssertTrue(PortForwardState.running(connections: 0).isActive)
        XCTAssertFalse(PortForwardState.failed("x").isActive)
    }
}
