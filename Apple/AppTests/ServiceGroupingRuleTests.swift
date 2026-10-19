import ServiceCatalog
import XCTest

@testable import gryonixNexus

/// What the server screen folds by default
@MainActor
final class ServiceGroupingRuleTests: XCTestCase {
    private func settings() -> TabBarSettings {
        let defaults = UserDefaults(suiteName: "grouping-tests-\(UUID().uuidString)")!
        return TabBarSettings(defaults: defaults)
    }

    func testTheSitesListIsCollapsibleOutOfTheBoxAndStartsOpen() {
        let tabs = settings()
        XCTAssertTrue(tabs.sitesCollapsible)
        XCTAssertTrue(tabs.sitesExpanded)
    }

    func testGroupingTurnsItselfOnWhenAShelfHoldsTwo() {
        // Two file engines — the case the rule exists for.
        XCTAssertTrue(TabBarSettings.aShelfHoldsSeveral([.nextcloud, .seafile]))
        // Two photo engines, one shelf.
        XCTAssertTrue(TabBarSettings.aShelfHoldsSeveral([.immich, .photoprism]))
        // Three VPN protocols share the VPN shelf.
        XCTAssertTrue(TabBarSettings.aShelfHoldsSeveral([.wireguardVPN, .amneziaWG, .shadowsocks]))
    }

    func testGroupingStaysOffWhileEveryServiceIsAloneOnItsShelf() {
        XCTAssertFalse(TabBarSettings.aShelfHoldsSeveral([]))
        XCTAssertFalse(TabBarSettings.aShelfHoldsSeveral([.nextcloud]))
        XCTAssertFalse(TabBarSettings.aShelfHoldsSeveral([.nextcloud, .immich, .jellyfin]))
    }

    func testAServiceThatArrivedAlongsideAnotherStillCountsAsARow() {
        XCTAssertTrue(TabBarSettings.aShelfHoldsSeveral([.wireguardVPN, .vpnPanel]),
                      "the panel is drawn under VPN with the protocol, so that group holds two")
        XCTAssertTrue(TabBarSettings.aShelfHoldsSeveral([.headscale, .tailscaleNode]))
    }

    func testTheImplicitCategoryIsCountedWhereItIsDrawn() {
        XCTAssertFalse(TabBarSettings.aShelfHoldsSeveral([.vpnPanel, .nextcloud]),
                       "one VPN row and one files row is two groups of one")
    }

    func testAnExplicitChoiceOverrulesTheServersOwnAnswer() {
        let tabs = settings()
        XCTAssertNil(tabs.groupServicesByCategoryOverride)
        XCTAssertTrue(tabs.groupsServices(in: [.nextcloud, .seafile]))
        XCTAssertFalse(tabs.groupsServices(in: [.nextcloud]))

        tabs.groupServicesByCategoryOverride = false
        XCTAssertFalse(tabs.groupsServices(in: [.nextcloud, .seafile]),
                       "an owner who switched grouping off means every server")

        tabs.groupServicesByCategoryOverride = true
        XCTAssertTrue(tabs.groupsServices(in: [.nextcloud]),
                      "and one who switched it on means every server too")

        tabs.groupServicesByCategoryOverride = nil
        XCTAssertFalse(tabs.groupsServices(in: [.nextcloud]),
                       "clearing it has to give the server its say back")
    }

    func testAnExplicitOffIsRememberedAsOffAndNotAsUnset() {
        let defaults = UserDefaults(suiteName: "grouping-tests-\(UUID().uuidString)")!
        let first = TabBarSettings(defaults: defaults)
        first.groupServicesByCategoryOverride = false
        XCTAssertEqual(TabBarSettings(defaults: defaults).groupServicesByCategoryOverride, false)

        first.groupServicesByCategoryOverride = nil
        XCTAssertNil(TabBarSettings(defaults: defaults).groupServicesByCategoryOverride)
    }
}
