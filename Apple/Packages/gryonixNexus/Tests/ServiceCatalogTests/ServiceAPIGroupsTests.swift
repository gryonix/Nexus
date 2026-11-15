import XCTest
@testable import ServiceCatalog

final class ServiceAPIGroupsTests: XCTestCase {
    func testTheAlwaysOpenAPIsAreTheSitesOwnLists() {
        XCTAssertEqual(ServiceAPIGroups.groups(for: .vaultwarden).first?.paths, VaultwardenService.bitwardenAPIPaths)
        XCTAssertEqual(ServiceAPIGroups.groups(for: .mailcow).first?.paths, MailcowService.syncPaths)
        XCTAssertEqual(ServiceAPIGroups.groups(for: .n8n).first?.paths, N8NService.webhookPaths)
    }

    func testAServiceWithoutAppsHasNoGroups() {
        XCTAssertTrue(ServiceAPIGroups.groups(for: .headscale).isEmpty)
    }

    func testAGroupIsOpenOnlyWhenEveryPathIs() {
        let paths = VaultwardenService.bitwardenAPIPaths
        XCTAssertEqual(ServiceAPIGroups.openGroups(of: .vaultwarden, openPaths: paths), ["bitwarden-apps"])
        XCTAssertEqual(ServiceAPIGroups.openGroups(of: .vaultwarden, openPaths: Array(paths.dropLast())), [])
    }

    func testClosingAGroupKeepsPathsItDoesNotKnow() {
        let sent = ServiceAPIGroups.paths(of: .immich, openGroups: [], keeping: ["/custom/*", "/api/*"])
        XCTAssertEqual(sent, ["/custom/*"])
        let opened = ServiceAPIGroups.paths(of: .immich, openGroups: ["immich-app"], keeping: sent)
        XCTAssertEqual(opened, ["/custom/*", "/api/*", "/.well-known/immich"])
    }

    func testNoGroupWouldOpenThePage() {
        for id in ServiceRegistry.all.map(\.id) {
            for group in ServiceAPIGroups.groups(for: id) {
                XCTAssertFalse(group.paths.contains("/") || group.paths.contains("/*"), id.rawValue)
            }
        }
    }
}
