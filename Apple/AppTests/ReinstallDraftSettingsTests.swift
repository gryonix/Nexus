import ServiceCatalog
import ServerControl
import XCTest

@testable import gryonixNexus

final class ReinstallDraftSettingsTests: XCTestCase {
    private func deployment(services: Set<ServiceID>,
                            settings: ServiceSettings) -> Deployment {
        var deployment = Deployment(
            name: "middle",
            topology: .singleHost,
            domain: "example.test",
            entry: HostEndpoint(host: "203.0.113.40", user: "control"),
            services: services)
        deployment.serviceSettings = settings
        return deployment
    }

    func testALicenseThisServerWasInstalledUnderIsNotAskedAgain() {
        var settings = ServiceSettings()
        settings.minecraftJavaAcceptsEULA = true
        settings.minecraftBedrockAcceptsEULA = true
        let draft = ConfiguratorDraft(
            recovering: deployment(services: [.minecraftJava, .minecraftBedrock],
                                   settings: settings))
        XCTAssertEqual(draft.minecraftJavaAcceptsEULA, true)
        XCTAssertEqual(draft.minecraftBedrockAcceptsEULA, true)
    }

    func testAnAnswerTheOwnerChangedComesBackChanged() {
        var settings = ServiceSettings()
        settings.vaultwardenAllowSignups = false
        settings.piholeServesNetwork = true
        settings.minecraftJavaFlavour = "FABRIC"
        let draft = ConfiguratorDraft(
            recovering: deployment(services: [.vaultwarden, .pihole], settings: settings))
        XCTAssertEqual(draft.vaultwardenAllowSignups, false,
                       "open registration came back on for a server whose owner closed it")
        XCTAssertEqual(draft.piholeServesNetwork, true)
        XCTAssertEqual(draft.minecraftJavaFlavour, "FABRIC")
    }

    func testTheSetAutheliaGuardsIsCarried() {
        var settings = ServiceSettings()
        settings.autheliaProtectedServices = [.nextcloud]
        let draft = ConfiguratorDraft(
            recovering: deployment(services: [.authelia, .nextcloud], settings: settings))
        XCTAssertEqual(draft.autheliaProtectedServices, [.nextcloud])
    }

    func testWhatTheRecordNeverHeldComesBackAsTheDefault() {
        let plain = ServiceSettings()
        let draft = ConfiguratorDraft(
            recovering: deployment(services: [.nextcloud], settings: plain))
        XCTAssertEqual(draft.minecraftJavaAcceptsEULA, plain.minecraftJavaAcceptsEULA)
        XCTAssertEqual(draft.vaultwardenAllowSignups, plain.vaultwardenAllowSignups)
        XCTAssertEqual(draft.piholeServesNetwork, plain.piholeServesNetwork)
    }

    func testASwitchChangedAfterInstallSurvivesTheReinstall() {
        var saved = ConfiguratorDraft(topology: .singleHost)
        saved.vaultwardenAllowSignups = true
        saved.xrayRealitySNI = "www.apple.com"
        saved.crowdsecEnabled = true
        saved.distribution = "ubuntu"
        var settings = ServiceSettings()
        settings.vaultwardenAllowSignups = false
        settings.xrayRealitySNI = "www.cloudflare.com"
        settings.crowdsecEnabled = false
        let draft = ConfiguratorDraft(
            reinstalling: deployment(services: [.vaultwarden], settings: settings), saved: saved)
        XCTAssertEqual(draft.vaultwardenAllowSignups, false)
        XCTAssertEqual(draft.xrayRealitySNI, "www.cloudflare.com")
        XCTAssertEqual(draft.crowdsecEnabled, false)
        XCTAssertEqual(draft.entryDistribution, .ubuntu)
    }
}
