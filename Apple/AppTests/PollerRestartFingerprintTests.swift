import ServerControl
import XCTest

@testable import gryonixNexus

final class PollerRestartFingerprintTests: XCTestCase {
    private func single() -> Deployment {
        Deployment(name: "A", topology: .singleHost, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"))
    }

    private func adding(_ host: String, to deployment: Deployment) -> Deployment {
        var copy = deployment
        let node = DeploymentNode(id: UUID(),
                                  endpoint: HostEndpoint(host: host, user: "root"),
                                  capabilities: [.worker],
                                  routedThrough: deployment.nodes.first?.id)
        copy.storedNodes = deployment.nodes + [node]
        return copy
    }

    private func fingerprint(_ deployment: Deployment) -> ServerMetricsStore.ConnectionFingerprint {
        ServerMetricsStore.ConnectionFingerprint(deployment)
    }

    func testACosmeticEditIsNotWorthAHandshake() {
        var renamed = single()
        renamed.name = "Something else"
        renamed.tags = ["prod"]
        renamed.iconSymbol = "sparkles"
        renamed.tintName = "teal"

        XCTAssertEqual(fingerprint(single()), fingerprint(renamed))
    }

    func testRenamingAMachineIsNotWorthOneEither() {
        let grown = adding("192.168.1.50", to: single())
        var renamed = grown
        renamed.storedNodes?[1].name = "Kitchen box"

        XCTAssertEqual(fingerprint(grown), fingerprint(renamed))
    }

    func testAddingTheFirstMachineRestartsThePoller() {
        XCTAssertNotEqual(fingerprint(single()), fingerprint(adding("192.168.1.50", to: single())))
    }

    func testAddingASECONDMachineRestartsItToo() {
        let one = adding("192.168.1.50", to: single())
        let two = adding("192.168.1.51", to: one)

        XCTAssertTrue(one.hasHomeHost, "precondition: the flag the fingerprint used is already set")
        XCTAssertTrue(two.hasHomeHost)
        XCTAssertNotEqual(fingerprint(one), fingerprint(two),
                          "a machine nothing restarts for is a machine nothing polls")
    }

    /// Moving a machine's address is a different machine to dial
    func testMovingAMachineRestartsThePoller() {
        let grown = adding("192.168.1.50", to: single())
        var moved = grown
        moved.storedNodes?[1].endpoint.host = "192.168.1.77"

        XCTAssertNotEqual(fingerprint(grown), fingerprint(moved))
    }

    func testRemovingAMachineRestartsThePoller() {
        let grown = adding("192.168.1.50", to: single())
        var shrunk = grown
        shrunk.storedNodes = [grown.nodes[0]]

        XCTAssertNotEqual(fingerprint(grown), fingerprint(shrunk))
    }
}
