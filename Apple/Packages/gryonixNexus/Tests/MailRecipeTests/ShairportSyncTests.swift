import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

/// The AirPlay speaker, pinned over the generated artifacts
final class ShairportSyncTests: XCTestCase {
    private func script(atHome: Bool = true, settings: ServiceSettings? = nil) throws -> String {
        var chosen = settings ?? ServiceSettings()
        chosen.machineAtHome = atHome
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                                 distribution: .debian)],
            services: [.shairportSync],
            serviceSettings: chosen
        )
        let bundle = try MailRecipe().generate(from: input)
        return try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-mail-server.sh" },
                             "missing setup script").contents
    }

    private func compose(_ settings: ServiceSettings) -> String {
        let context = ServiceContext(domain: "example.com", sshUser: "admin", settings: settings)
        return ShairportSyncService().composeFile(context)?.composeContents ?? ""
    }

    func testTheModePicksTheImageTag() {
        XCTAssertTrue(compose(ServiceSettings()).contains("mikebrady/shairport-sync:latest"))
        XCTAssertTrue(compose(ServiceSettings(shairportMode: "airplay1"))
            .contains("mikebrady/shairport-sync:classic"))
    }

    func testTheSpeakerUsesTheHostNetworkAndTheSoundCard() {
        let text = compose(ServiceSettings(shairportName: "Living room", shairportOutput: "hw:1,0"))
        XCTAssertTrue(text.contains("network_mode: host"))
        XCTAssertTrue(text.contains("- /dev/snd"))
        XCTAssertTrue(text.contains(#"command: -a "Living room" -o alsa -- -d hw:1,0"#))
    }

    func testTheNameCannotBreakTheCommandLine() {
        let text = compose(ServiceSettings(shairportName: "A\"$(x)`b\\", shairportOutput: "hw:0;rm"))
        XCTAssertTrue(text.contains(#"-a "A(x)b""#), text)
        XCTAssertTrue(text.contains("-d hw:0rm"), text)
        XCTAssertTrue(compose(ServiceSettings(shairportName: "\"", shairportOutput: ";"))
            .contains(#"-a "gryonix" -o alsa -- -d default"#))
    }

    func testEveryAirPlayPortIsOpenAndNothingIsForwarded() {
        let context = ServiceContext(domain: "example.com", sshUser: "admin")
        let ports = ShairportSyncService().firewallPorts(context)
        XCTAssertEqual(ports.filter { $0.proto == .tcp }.map(\.port), [3689, 5000, 7000])
        XCTAssertEqual(ports.filter { $0.proto == .udp }.map(\.port),
                       [319, 320, 5353] + Array(6000...6009))
        XCTAssertEqual(ForwardedPorts.tcp(services: [ShairportSyncService()], context: context), [80])
        XCTAssertTrue(ForwardedPorts.udp(services: [ShairportSyncService()], context: context).isEmpty)
    }

    func testItNeedsAMachineAtHome() throws {
        XCTAssertThrowsError(try script(atHome: false)) { error in
            guard case ValidationError.inconsistentTopology(let message) = error else {
                return XCTFail("\(error)")
            }
            XCTAssertTrue(message.contains("AirPlay speaker"), message)
        }
        let text = try script()
        XCTAssertTrue(text.contains("docker compose -p shairport-sync up -d"))
    }

    func testItHasNoBackupNoWebPageAndOneImageToUpdate() {
        let context = ServiceContext(domain: "example.com", sshUser: "admin",
                                     settings: ServiceSettings(shairportMode: "airplay1"))
        let service = ShairportSyncService()
        XCTAssertNil(service.actions(context).backup)
        XCTAssertNil(service.webIngress(context))
        XCTAssertEqual(service.updateSpec(context).images, ["mikebrady/shairport-sync:classic"])
    }
}
