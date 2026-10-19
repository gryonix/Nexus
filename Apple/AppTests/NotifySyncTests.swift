import AgentClient
import XCTest

@testable import gryonixNexus

@MainActor
final class NotifySyncTests: XCTestCase {
    private let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMjhZbMLa1yPZt87ATUHLO4OUNZoQu6+22Re+KW7HKUl phone"

    private func server(custom: Bool, checks: Gryonixnexusd_V1_NotifyChecks) -> Gryonixnexusd_V1_NotifySettings {
        var settings = Gryonixnexusd_V1_NotifySettings()
        settings.channel = .relay
        settings.language = "ru"
        settings.checks = checks
        settings.customChecks = custom
        settings.quietKeys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMjhZbMLa1yPZt87ATUHLO4OUNZoQu6+22Re+KW7HKUl"]
        return settings
    }

    func testAServerFollowingTheDefaultsGetsThem() {
        var wanted = NotifyPreferences()
        wanted.sshLogins = false
        let request = DashboardViewModel.notifySyncRequest(current: server(custom: false, checks: NotifyPreferences().checks),
                                                           wanted: wanted, language: "ru", appKey: key)
        XCTAssertEqual(request?.checks.sshLogins, false)
        XCTAssertEqual(request?.customChecks, false)
    }

    func testAServerWithItsOwnChoiceKeepsIt() {
        var own = NotifyPreferences().checks
        own.backups = false
        var wanted = NotifyPreferences()
        wanted.sshLogins = false
        let current = server(custom: true, checks: own)
        XCTAssertNil(DashboardViewModel.notifySyncRequest(current: current, wanted: wanted, language: "ru", appKey: key))
    }

    func testAnUnknownAppKeyIsSent() {
        let current = server(custom: true, checks: NotifyPreferences().checks)
        let request = DashboardViewModel.notifySyncRequest(current: current, wanted: NotifyPreferences(),
                                                           language: "ru", appKey: "ssh-ed25519 AAAAother mac")
        XCTAssertEqual(request?.appPublicKey, "ssh-ed25519 AAAAother mac")
        XCTAssertEqual(request?.customChecks, true)
    }

    func testASilentSecondMachineTakesTheMainOnesChannel() {
        var primary = server(custom: false, checks: NotifyPreferences().checks)
        primary.relayURL = "https://push.example.com"
        let request = DashboardViewModel.notifyMirrorRequest(primary: primary, current: Gryonixnexusd_V1_NotifySettings(),
                                                             appKey: key)
        XCTAssertEqual(request?.channel, .relay)
        XCTAssertEqual(request?.relayURL, "https://push.example.com")
        XCTAssertEqual(request?.checks, primary.checks)
        XCTAssertEqual(request?.language, "ru")
    }

    func testAMatchingSecondMachineIsLeftAlone() {
        var primary = server(custom: false, checks: NotifyPreferences().checks)
        primary.relayURL = "https://push.example.com"
        XCTAssertNil(DashboardViewModel.notifyMirrorRequest(primary: primary, current: primary, appKey: key))
    }

    // MARK: - The app-wide channel

    func testAFollowingServerGetsTheAppsChannel() {
        var current = server(custom: false, checks: NotifyPreferences().checks)
        current.relayURL = "https://push.gryonix.com"
        var choice = NotifyChannelDefault()
        choice.channel = .ntfy
        choice.ntfyTopic = "gnx-topic"
        let request = DashboardViewModel.notifySyncRequest(current: current, wanted: NotifyPreferences(),
                                                           language: "ru", appKey: key, channel: choice)
        XCTAssertEqual(request?.channel, .ntfy)
        XCTAssertEqual(request?.ntfyTopic, "gnx-topic")
        choice.channel = .relay
        choice.relayURL = "https://push.gryonix.com"
        XCTAssertNil(DashboardViewModel.notifySyncRequest(current: current, wanted: NotifyPreferences(),
                                                          language: "ru", appKey: key, channel: choice),
                     "already in step")
    }

    func testAServerKeepingItsChannelIsLeftAlone() {
        var current = server(custom: false, checks: NotifyPreferences().checks)
        current.channel = .ntfy
        current.ntfyTopic = "mine"
        XCTAssertNil(DashboardViewModel.notifySyncRequest(current: current, wanted: NotifyPreferences(),
                                                          language: "ru", appKey: key, channel: nil))
    }

    func testOnlyAServerWithItsOwnSetupKeepsItAtFirstSight() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "NotifySyncTests.own"))
        defaults.removePersistentDomain(forName: "NotifySyncTests.own")
        let choice = NotifyChannelDefault()
        var ours = server(custom: false, checks: NotifyPreferences().checks)
        ours.relayURL = "https://push.gryonix.com:8444"
        XCTAssertFalse(NotifyChannelDefault.keepsOwn(ours, deploymentID: UUID(), wanted: choice, defaults: defaults))
        var silent = ours
        silent.channel = .off
        XCTAssertFalse(NotifyChannelDefault.keepsOwn(silent, deploymentID: UUID(), wanted: choice, defaults: defaults))
        var own = ours
        own.channel = .ntfy
        let id = UUID()
        XCTAssertTrue(NotifyChannelDefault.keepsOwn(own, deploymentID: id, wanted: choice, defaults: defaults))
        XCTAssertTrue(NotifyChannelDefault.keepsOwn(ours, deploymentID: id, wanted: choice, defaults: defaults),
                      "decided once, then remembered")
    }
}
