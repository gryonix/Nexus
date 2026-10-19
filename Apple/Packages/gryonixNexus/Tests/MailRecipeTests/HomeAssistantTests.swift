import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

private final class HomeFixedKeyProvider: WireGuardKeyProvider, @unchecked Sendable {
    func makeKeyPair(for slot: WireGuardKeySlot) throws -> WireGuardKeyPair {
        WireGuardKeyPair(privateKey: "TEST-PRIVATE-KEY=", publicKey: "TEST-PUBLIC-KEY=")
    }
}

/// Home Assistant, pinned over the generated artifacts
final class HomeAssistantTests: XCTestCase {
    private func single(scope: DeploymentScope = .publicInternet, atHome: Bool = true,
                        stick: String = "",
                        services: Set<ServiceID> = [.homeAssistant]) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            scope: scope,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                                 distribution: .ubuntu)],
            services: services,
            serviceSettings: ServiceSettings(machineAtHome: atHome, homeAssistantUSBDevice: stick)
        )
    }

    private func split() throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .vpsRelayWithHomeBackend,
            servers: [
                ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"),
                           vpnAddress: .ipv4("10.8.0.1"), distribution: .ubuntu),
                ServerNode(role: .homeBackend, vpnAddress: .ipv4("10.8.0.2"), distribution: .debian)
            ],
            services: [.homeAssistant]
        )
    }

    private func generate(_ input: MailRecipeInput) throws -> GeneratedBundle {
        try MailRecipe(keyProvider: HomeFixedKeyProvider()).generate(from: input)
    }

    private func script(_ bundle: GeneratedBundle, _ role: ServerRole) throws -> String {
        let artifact = bundle.artifacts.first { $0.kind == .shellScript && $0.server == role }
        return try XCTUnwrap(artifact?.contents, "no script for \(role)")
    }

    func testARentedServerIsRefused() throws {
        XCTAssertThrowsError(try generate(single(atHome: false)))
        XCTAssertThrowsError(try generate(single(scope: .cloudflareTunnel, atHome: false)))
        XCTAssertThrowsError(try generate(single(scope: .meshOnly, atHome: false)))
    }

    func testEveryHomePlacementIsAccepted() throws {
        XCTAssertNoThrow(try generate(split()))
        XCTAssertNoThrow(try generate(single(scope: .localOnly, atHome: false)))
        XCTAssertNoThrow(try generate(single(scope: .dynamicDNS, atHome: false)))
        XCTAssertNoThrow(try generate(single(scope: .cloudflareTunnel, atHome: true)))
        XCTAssertNoThrow(try generate(single(scope: .meshOnly, atHome: true)))
        XCTAssertNoThrow(try generate(single(atHome: true)))
    }

    func testScenarioBInstallsItOnTheHomeHalfOnly() throws {
        let bundle = try generate(split())
        XCTAssertTrue(try script(bundle, .homeBackend).contains(HomeAssistantService.image))
        XCTAssertFalse(try script(bundle, .vpsRelay).contains(HomeAssistantService.image))
    }

    func testItRunsOnTheHostNetworkBehindLocalCaddyOnly() throws {
        let text = try script(generate(single()), .singleHost)
        XCTAssertTrue(text.contains("network_mode: host"))
        XCTAssertFalse(text.contains("server_host: 127.0.0.1"))
        XCTAssertTrue(text.contains(".storage/http <<'EOF_HA_HTTP'"))
        XCTAssertTrue(text.contains("\"trusted_proxies\": [\n        \"127.0.0.1/32\""))
        XCTAssertTrue(text.contains("\"pending\": null"))
        XCTAssertTrue(text.contains("reverse_proxy 127.0.0.1:\(HomeAssistantService.webUIPort)"))
    }

    func testBluetoothManagementGetsTheCapabilitiesItNeeds() throws {
        let text = try script(generate(single()), .singleHost)
        XCTAssertTrue(text.contains("/run/dbus:/run/dbus:ro"))
        XCTAssertTrue(text.contains("cap_add:"))
        XCTAssertTrue(text.contains("- NET_ADMIN"))
        XCTAssertTrue(text.contains("- NET_RAW"))
    }

    func testTheSettingsFileIsWrittenOnlyOnTheFirstInstall() throws {
        let text = try script(generate(single()), .singleHost)
        let path = ServiceSettings().homeAssistantPath
        XCTAssertTrue(text.contains("if [ ! -f \(path)/config/configuration.yaml ]; then"))
    }

    func testDiscoveryIsOpenOnlyWithTheHub() throws {
        let rule = "udp dport { 5353, 1900 } accept"
        XCTAssertTrue(try script(generate(single()), .singleHost).contains(rule))
        XCTAssertTrue(try script(generate(split()), .homeBackend).contains(rule))
        XCTAssertFalse(try script(generate(split()), .vpsRelay).contains(rule))
        XCTAssertFalse(try script(generate(single(services: [.jellyfin])), .singleHost).contains(rule))
    }

    func testAStickIsHandedThroughOnlyWhenOneIsNamed() throws {
        let without = try script(generate(single()), .singleHost)
        XCTAssertFalse(without.contains("devices:"))

        let stick = "/dev/serial/by-id/usb-Silicon_Labs_slae.sh_cc2652rb_stick-if00-port0"
        let with = try script(generate(single(stick: stick)), .singleHost)
        XCTAssertTrue(with.contains("    devices:"))
        XCTAssertTrue(with.contains("      - \(stick):\(stick)"))
    }

    func testAStickThatIsNotADevicePathIsRefused() throws {
        for value in ["ttyUSB0", "/etc/passwd", "/dev/../etc/shadow", "/dev/tty USB0"] {
            XCTAssertThrowsError(try generate(single(stick: value)), value) { error in
                guard case ValidationError.inconsistentTopology(let message) = error else {
                    return XCTFail("\(value): \(error)")
                }
                XCTAssertTrue(message.contains(value), message)
            }
        }
    }

    func testOnlyTheOwnerCanSayARentedStyleMachineIsHome() {
        XCTAssertTrue(HomePlacement.needsAnswer(topology: .singleHost, scope: .publicInternet))
        XCTAssertTrue(HomePlacement.needsAnswer(topology: .singleHost, scope: .cloudflareTunnel))
        XCTAssertTrue(HomePlacement.needsAnswer(topology: .singleHost, scope: .meshOnly))
        XCTAssertFalse(HomePlacement.needsAnswer(topology: .singleHost, scope: .localOnly))
        XCTAssertFalse(HomePlacement.needsAnswer(topology: .singleHost, scope: .dynamicDNS))
        XCTAssertFalse(HomePlacement.needsAnswer(topology: .vpsRelayWithHomeBackend, scope: .publicInternet))
    }
}
