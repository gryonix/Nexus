import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

/// Pins the AirPlay screen and audio hub output
final class NativeAudioServicesTests: XCTestCase {
    private func script(_ services: Set<ServiceID>, settings: ServiceSettings = ServiceSettings()) throws -> String {
        var chosen = settings
        chosen.machineAtHome = true
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                                 distribution: .debian)],
            services: services,
            serviceSettings: chosen
        )
        let bundle = try MailRecipe().generate(from: input)
        return try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-mail-server.sh" },
                             "missing setup script").contents
    }

    private func context(_ settings: ServiceSettings = ServiceSettings()) -> ServiceContext {
        ServiceContext(domain: "example.com", sshUser: "admin", settings: settings)
    }

    func testTheScreenRunsAsAUnitWithFixedPortsAndHeadlessSinks() {
        let unit = UxPlayService.unitFile(context(ServiceSettings(uxplayName: "Living room")))
        XCTAssertTrue(unit.contains(#"ExecStart=/usr/bin/uxplay -n "Living room" -nh -p 7200 -vs kmssink -as alsasink"#), unit)
        XCTAssertTrue(unit.contains("User=uxplay"))
    }

    func testTheScreenNameCannotBreakTheUnit() {
        let unit = UxPlayService.unitFile(context(ServiceSettings(uxplayName: "A\"$(x)%h`b\\")))
        XCTAssertTrue(unit.contains(#"-n "A(x)hb""#), unit)
        XCTAssertTrue(UxPlayService.unitFile(context(ServiceSettings(uxplayName: "\"")))
            .contains(#"-n "gryonix TV""#))
    }

    func testTheScreenOpensItsOwnPortsOnTheHomeNetworkOnly() {
        let ports = UxPlayService().firewallPorts(context())
        XCTAssertEqual(ports.filter { $0.proto == .tcp }.map(\.port), [7200, 7201, 7202])
        XCTAssertEqual(ports.filter { $0.proto == .udp }.map(\.port), [7200, 7201, 7202])
        XCTAssertEqual(ForwardedPorts.tcp(services: [UxPlayService()], context: context()), [80])
        XCTAssertTrue(ForwardedPorts.udp(services: [UxPlayService()], context: context()).isEmpty)
    }

    func testTheScreenInstallsPackagesWithoutDocker() throws {
        XCTAssertFalse(ServiceRegistry.needsDocker([.uxplay, .odio]))
        let text = try script([.uxplay])
        XCTAssertTrue(text.contains("install -yq uxplay gstreamer1.0-plugins-good"))
        XCTAssertTrue(text.contains("systemctl restart gryonixnexus-uxplay.service"))
    }

    func testTheScreenAndAnAirPlay2SpeakerAreRefused() throws {
        XCTAssertThrowsError(try script([.uxplay, .shairportSync])) { error in
            guard case ValidationError.inconsistentTopology(let message) = error else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(message, L10nGeneration.errAirPlayScreenNeedsAirPlay1(.en))
            XCTAssertTrue(message.contains("cannot share one machine"), message)
        }
        let classic = try script([.uxplay, .shairportSync], settings: ServiceSettings(shairportMode: "airplay1"))
        XCTAssertTrue(classic.contains("gryonixnexus-uxplay.service"))
    }

    func testTheScreenManagesItsOwnUnit() {
        let actions = UxPlayService().actions(context())
        guard case .systemdUnits(let list, let journal) = actions.statusProbe else { return XCTFail() }
        XCTAssertEqual(list.command, "sudo systemctl show gryonixnexus-uxplay.service --property=Id --property=LoadState --property=ActiveState")
        XCTAssertTrue(journal.command.hasPrefix("sudo journalctl -u gryonixnexus-uxplay.service"))
        XCTAssertEqual(actions.restart?.command, "sudo systemctl restart gryonixnexus-uxplay.service")
        XCTAssertTrue(UxPlayService().sudoersLines(context()).contains(
            "admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop gryonixnexus-uxplay.service"))
    }

    func testTheHubChecksThePinnedInstallerBeforeRunningIt() throws {
        let text = try script([.odio])
        XCTAssertTrue(text.contains(OdioService.installerURL))
        XCTAssertTrue(text.contains("\(OdioService.installerSHA256)  "))
        XCTAssertTrue(text.contains("sha256sum -c -"))
        XCTAssertTrue(text.contains("ODIOS_VERSION=2026.10.0b3"))
        XCTAssertTrue(text.contains(#"bash -s < "$odio_tmp/install.sh""#))
        XCTAssertTrue(text.contains("apt-get install -yq python3-jinja2 python3-cryptography"))
        XCTAssertTrue(text.contains("INSTALL_BRANDING=N"))
    }

    func testTheHubLeavesAirPlayToTheSpeakerWhenBothAreSelected() throws {
        let both = OdioService().setupSteps(ServiceContext(
            domain: "example.com", sshUser: "admin", installedServices: [.odio, .shairportSync]))
        XCTAssertTrue(both[0].contains(#"if [ "1" = 1 ]"#))
        let alone = OdioService().setupSteps(context())
        XCTAssertTrue(alone[0].contains(#"if [ "0" = 1 ]"#))
        XCTAssertTrue(alone[0].contains("/opt/shairport-sync/docker-compose.yml"))
    }

    func testTheHubIsBehindTheGuardAndAPassword() throws {
        let ingress = try XCTUnwrap(OdioService().webIngress(context()))
        XCTAssertTrue(ingress.adminGuard)
        XCTAssertEqual(ingress.upstreamPort, 8018)
        XCTAssertEqual(ingress.hostname, "odio.local")
        let site = ServiceInfraSections.caddySite(
            owner: "odio", hostname: ingress.hostname, upstreamPort: ingress.upstreamPort,
            adminGuard: ingress.adminGuard, basicAuthSnippet: ingress.basicAuthSnippet)
        XCTAssertTrue(site.contains("import /etc/caddy/gryonixnexus-admin-guard\n    import /etc/caddy/gryonixnexus-odio-auth\n    reverse_proxy 127.0.0.1:8018"), site)
        let text = try script([.odio])
        XCTAssertTrue(text.contains("caddy hash-password --plaintext"))
        XCTAssertTrue(text.contains("printf 'bind: lo\\n'"))
        XCTAssertTrue(text.contains("import /etc/caddy/gryonixnexus-odio-auth"))
        XCTAssertTrue(text.contains("odio.local {\n    # gryonixnexus: odio\n    tls internal\n"), "the hub's site is home-only")
        XCTAssertFalse(text.contains("odio.example.com"))
    }

    func testTheHubReportsItsGeneratedPassword() {
        let report = OdioService().reportSteps(context()).joined(separator: "\n")
        XCTAssertTrue(report.contains("https://odio.local"))
        XCTAssertTrue(report.contains("ODIO_WEB_PASSWORD"))
    }

    func testTheHubLeavesItsPackagesAndSaysSo() {
        let spec = OdioService().uninstallSpec(context())
        XCTAssertEqual(spec.dataPaths, ["/opt/odio"])
        XCTAssertTrue(spec.preSteps.joined(separator: "\n").contains("left in place"))
        XCTAssertTrue(spec.preSteps.contains { $0.contains("gryonixnexus-odio-ctl disable") })
    }

    func testTheHubControlsTheUserUnitsThroughOneHelper() {
        let actions = OdioService().actions(context())
        XCTAssertEqual(actions.restart?.command, "sudo gryonixnexus-odio-ctl restart")
        guard case .systemdUnits(let list, _) = actions.statusProbe else { return XCTFail() }
        XCTAssertEqual(list.command, "sudo gryonixnexus-odio-ctl status")
        XCTAssertTrue(OdioService().sudoersLines(context()).contains(
            "admin ALL=(ALL) NOPASSWD: /usr/local/sbin/gryonixnexus-odio-ctl stop"))
        XCTAssertTrue(OdioService.controlScript().contains("runuser -u \"$user\""))
    }

    func testTheDlnaSpeakerInstallsBothUnitsAndMarksItself() throws {
        let text = try script([.upmpdcli])
        XCTAssertTrue(text.contains("install -yq mpd upmpdcli avahi-daemon"), text)
        XCTAssertTrue(text.contains("systemctl restart mpd.service upmpdcli.service"))
        XCTAssertTrue(text.contains("touch /var/lib/gryonixnexus/packaged/upmpdcli"))
        XCTAssertTrue(PackagedAudioService.upmpdcli.uninstallSpec(context()).preSteps
            .contains { $0.contains("remove -yq upmpdcli >") })
    }

    func testTheBluetoothSpeakerKeepsBluezAndSharesSudoersWithTheAgent() {
        let bluetooth = PackagedAudioService.bluealsa
        XCTAssertTrue(bluetooth.setupSteps(context())[0].contains("bt-agent --capability=NoInputNoOutput"))
        XCTAssertFalse(bluetooth.uninstallSpec(context()).preSteps.contains { $0.contains("remove -yq bluez ") })
        XCTAssertTrue(bluetooth.sudoersLines(context()).contains(
            "admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl show bluetooth.service bluealsa.service "
            + "bluealsa-aplay.service gryonixnexus-bt-agent.service --property=Id --property=LoadState --property=ActiveState"))
    }

    func testTheHubRefusesItsOwnPlayersBesideIt() throws {
        XCTAssertThrowsError(try script([.odio, .snapclient])) { error in
            guard case ValidationError.inconsistentTopology(let message) = error else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(message, L10nGeneration.errOverlapsAudioHub(.en, service: "Multi-room speaker (Snapcast)"))
        }
        XCTAssertNoThrow(try script([.odio, .snapserver]))
    }

    func testSpotifyConnectInstallsAPinnedPackageNamedAfterTheMachine() throws {
        let text = try script([.raspotify])
        XCTAssertTrue(text.contains("raspotify_0.48.4.librespot.v0.8.0-99b6088_$(dpkg --print-architecture).deb"), text)
        XCTAssertTrue(text.contains("armhf) spotify_sha=47cc9b1d"))
        XCTAssertTrue(text.contains(#"LIBRESPOT_NAME=\"$(hostname)\"/" /etc/raspotify/conf"#))
        XCTAssertTrue(text.contains("/etc/raspotify/conf\nsystemctl daemon-reload"))
    }

    func testTheMusicLibraryAnswersOnItsOwnPortAndRemovalKeepsSharedUnits() throws {
        let text = try script([.mympd])
        XCTAssertTrue(text.contains("odio-mympd/releases/download/v26.1.2/mympd_26.1.2-1_$(dpkg --print-architecture).deb"), text)
        XCTAssertTrue(text.contains(#"printf '[Service]\nEnvironment=MYMPD_HTTP_PORT=8019"#))
        XCTAssertEqual(PackagedAudioService.mympd.uninstallSpec(context()).preSteps.first,
                       "systemctl disable --now mympd.service >/dev/null 2>&1 || true")
        XCTAssertFalse(PackagedAudioService.bluealsa.uninstallSpec(context()).preSteps[0].contains(" bluetooth.service"))
    }

    func testHomeOnlyPortsSkipWebAndRepeats() {
        let ports = HomeOnlyPorts.of([PackagedAudioService.snapserver, PackagedAudioService.upmpdcli, PackagedAudioService.snapserver],
                                     context: context())
        XCTAssertEqual(ports.map { "\($0.proto.rawValue)/\($0.port)" },
                       ["tcp/1704", "tcp/1705", "tcp/1780", "udp/1900", "tcp/49152", "tcp/49153"])
    }
}
