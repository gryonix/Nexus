import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

final class NftablesSSHThrottleTests: XCTestCase {
    private let appKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMyDQB6mYEJGEwmaG7pwxsGYtqL9jGpLazp91J9hxAxk gryonixnexus-app"

    private func singleHostInput() throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"), distribution: .debian)]
        )
    }

    private func scenarioBInput() throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .vpsRelayWithHomeBackend,
            servers: [
                ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"),
                           vpnAddress: .ipv4("10.8.0.1"), distribution: .debian),
                ServerNode(role: .homeBackend, vpnAddress: .ipv4("10.8.0.2"), distribution: .debian)
            ],
            dashboardAccess: DashboardAccessInput(sshUser: "admin", appPublicKey: appKey)
        )
    }

    private func assertThrottled(_ script: String, port: Int = 22, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(script.contains("tcp dport \(port) meter gryonixnexus_ssh_throttle4"),
                      "missing the IPv4 meter:\n\(script)", file: file, line: line)
        XCTAssertTrue(script.contains("tcp dport \(port) meter gryonixnexus_ssh_throttle6"),
                      "missing the IPv6 meter:\n\(script)", file: file, line: line)
        XCTAssertTrue(script.contains("ip saddr timeout 60s limit rate 10/minute burst 5 packets"),
                      file: file, line: line)
        XCTAssertTrue(script.contains("ip6 saddr timeout 60s limit rate 10/minute burst 5 packets"),
                      file: file, line: line)
        XCTAssertTrue(script.contains("tcp dport \(port) drop comment \"SSH: per-source rate exceeded\""),
                      file: file, line: line)
        XCTAssertFalse(script.contains("tcp dport \(port) accept comment \"SSH\""),
                       "a flat SSH accept survived next to the throttle:\n\(script)", file: file, line: line)
    }

    func testSingleHostScenarioAThrottlesSSH() throws {
        let bundle = try MailRecipe().generate(from: try singleHostInput())
        let script = try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-mail-server.sh" }).contents
        assertThrottled(script)
    }

    func testScenarioBThrottlesSSHOnBothHalves() throws {
        let bundle = try MailRecipe().generate(from: try scenarioBInput())
        let vps = try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-vps.sh" }).contents
        let home = try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-home-server.sh" }).contents
        assertThrottled(vps)
        assertThrottled(home)
    }

    func testACustomSSHPortThreadsThroughEveryThrottleLine() throws {
        struct MovedSSHPolicy: SecurityPolicy {
            let minimumTLSVersion: TLSVersion = .v1_2
            let dkimKeyBits = 2048
            let allowOpenRelay = false
            let ssh = SSHHardening(port: 2222)
        }
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"), distribution: .debian)],
            security: MovedSSHPolicy()
        )
        let bundle = try MailRecipe().generate(from: input)
        let script = try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-mail-server.sh" }).contents
        assertThrottled(script, port: 2222)
        XCTAssertFalse(script.contains("dport 22 "), "port 22 must not appear at all once ssh moved off it:\n\(script)")
    }
}
