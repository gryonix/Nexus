import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

final class CrowdSecSectionsTests: XCTestCase {
    private func input(services: Set<ServiceID> = [], crowdsecEnabled: Bool = true) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"), distribution: .debian)],
            services: services,
            serviceSettings: ServiceSettings(crowdsecEnabled: crowdsecEnabled)
        )
    }

    private func inputB(crowdsecEnabled: Bool = true) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .vpsRelayWithHomeBackend,
            servers: [
                ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"),
                           vpnAddress: .ipv4("10.8.0.1"), distribution: .debian),
                ServerNode(role: .homeBackend, vpnAddress: .ipv4("10.8.0.2"), distribution: .debian)
            ],
            services: [],
            serviceSettings: ServiceSettings(crowdsecEnabled: crowdsecEnabled)
        )
    }

    private func artifact(_ name: String, in bundle: GeneratedBundle) throws -> Artifact {
        try XCTUnwrap(bundle.artifacts.first { $0.fileName == name }, "missing artifact \(name)")
    }

    // MARK: - The toggle actually gates something on every host

    func testEveryHostInstallsCrowdSecWhenEnabled() throws {
        let bundleA = try MailRecipe().generate(from: try input())
        let scriptA = try artifact("setup-mail-server.sh", in: bundleA).contents
        XCTAssertTrue(scriptA.contains("install.crowdsec.net"),
                      "scenario A must install the CrowdSec engine when the toggle is on")
        XCTAssertTrue(scriptA.contains("crowdsec-firewall-bouncer-nftables"))

        let bundleB = try MailRecipe().generate(from: try inputB())
        for name in ["setup-vps.sh", "setup-home-server.sh"] {
            let script = try artifact(name, in: bundleB).contents
            XCTAssertTrue(script.contains("install.crowdsec.net"),
                          "\(name) must install the CrowdSec engine when the toggle is on")
        }
    }

    func testTheToggleOffSkipsTheInstallOnEveryHost() throws {
        let bundleA = try MailRecipe().generate(from: try input(crowdsecEnabled: false))
        let scriptA = try artifact("setup-mail-server.sh", in: bundleA).contents
        XCTAssertFalse(scriptA.contains("install.crowdsec.net"),
                       "scenario A must not install CrowdSec when the toggle is off")

        let bundleB = try MailRecipe().generate(from: try inputB(crowdsecEnabled: false))
        for name in ["setup-vps.sh", "setup-home-server.sh"] {
            let script = try artifact(name, in: bundleB).contents
            XCTAssertFalse(script.contains("install.crowdsec.net"),
                           "\(name) must not install CrowdSec when the toggle is off")
        }
    }

    // MARK: - The same facts crowdsec.rs itself exists to get right

    func testTheLocalAPINeverDefaultsToPort8080() throws {
        let script = try artifact("setup-mail-server.sh",
                                  in: try MailRecipe().generate(from: try input())).contents
        XCTAssertTrue(script.contains(CrowdSecSections.lapiListenAddr))
        XCTAssertFalse(script.contains("listen_uri: 127.0.0.1:8080"))
    }

    func testAcquisitionIsJournaldBased() throws {
        let script = try artifact("setup-mail-server.sh",
                                  in: try MailRecipe().generate(from: try input())).contents
        XCTAssertTrue(script.contains("source: journalctl"))
        XCTAssertFalse(script.contains("filename: /var/log/auth.log"))
    }

    func testTheEngineInstallsBeforeTheBouncer() throws {
        let script = try artifact("setup-mail-server.sh",
                                  in: try MailRecipe().generate(from: try input())).contents
        let engineRange = try XCTUnwrap(script.range(of: "install -y crowdsec\n"))
        let bouncerRange = try XCTUnwrap(script.range(of: "install -y crowdsec-firewall-bouncer-nftables"))
        XCTAssertTrue(engineRange.lowerBound < bouncerRange.lowerBound,
                      "the engine must be apt-installed before the bouncer")
    }

    func testAFailedInstallCannotAbortTheScript() throws {
        let script = try artifact("setup-mail-server.sh",
                                  in: try MailRecipe().generate(from: try input())).contents
        XCTAssertTrue(script.contains(") || echo"),
                      "the CrowdSec block must be wrapped so its own failure cannot trip the script's set -e")
    }
}
