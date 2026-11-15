import XCTest
@testable import ServerControl

final class KnownHostsTests: XCTestCase {
    func testFingerprintIsSha256OfTheKeyBlobWithoutPadding() {
        let key = KnownHosts.describe("ssh-ed25519 aGVsbG8=")
        XCTAssertEqual(key?.keyType, "ssh-ed25519")
        XCTAssertEqual(key?.fingerprint, "SHA256:LPJNul+wow4m6DsqxbninhsWHlwfp0JecwQzYpOLmCQ")
    }

    func testGarbageIsNotAKey() {
        XCTAssertNil(KnownHosts.describe("unreadable"))
        XCTAssertNil(KnownHosts.describe("ssh-rsa !!!"))
    }

    func testOnlyMachinesWithAPinAreListed() {
        let deployment = Deployment(name: "orion", topology: .singleHost, domain: "example.net",
                                    entry: HostEndpoint(host: "203.0.113.5", port: 2222, user: "root"))
        let node = deployment.nodes[0]
        let listed = KnownHosts.entries(for: deployment) { $0 == node.sshHost ? "ssh-ed25519 aGVsbG8=" : nil }
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0].endpoint, "203.0.113.5:2222")
        XCTAssertEqual(listed[0].serverName, "orion")
        XCTAssertTrue(KnownHosts.entries(for: deployment) { _ in nil }.isEmpty)
    }

    func testBastionRowsComeFromTheirEndpoints() {
        let deployment = Deployment(name: "orion", topology: .singleHost, domain: "example.net",
                                    entry: HostEndpoint(host: "203.0.113.5", user: "root"))
        let rows = KnownHosts.bastionEntries(for: deployment, endpoints: ["198.51.100.7:22", "198.51.100.8:22"]) {
            $0.hasSuffix("7:22") ? "ssh-rsa aGVsbG8=" : nil
        }
        XCTAssertEqual(rows.map(\.endpoint), ["198.51.100.7:22"])
    }
}
