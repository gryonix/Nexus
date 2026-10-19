import XCTest
@testable import ServiceCatalog

final class ServiceDataPlacementTests: XCTestCase {
    private let mount = "/srv/gryonixnexus-storage"

    func testAServiceMovesUnderTheArrayWithItsOwnFolderName() {
        var settings = ServiceSettings()
        settings.placeData(of: .nextcloud, under: mount)
        XCTAssertEqual(settings.nextcloudPath, "/srv/gryonixnexus-storage/nextcloud")
        settings.placeData(of: .vaultwarden, under: mount + "/")
        XCTAssertEqual(settings.vaultwardenDataPath, "/srv/gryonixnexus-storage/vaultwarden/data")
    }

    func testMediaFollowsJellyfin() {
        var settings = ServiceSettings()
        settings.placeData(of: .jellyfin, under: mount)
        XCTAssertEqual(settings.jellyfinPath, "/srv/gryonixnexus-storage/jellyfin")
        XCTAssertEqual(settings.jellyfinMediaPath, "/srv/gryonixnexus-storage/media")
    }

    func testPlacingTwiceChangesNothing() {
        var settings = ServiceSettings()
        settings.placeData(of: .immich, under: mount)
        let once = settings
        settings.placeData(of: .immich, under: mount)
        XCTAssertEqual(settings, once)
    }

    func testOtherServicesStayWhereTheyAre() {
        var settings = ServiceSettings()
        settings.placeData(of: .nextcloud, under: mount)
        XCTAssertEqual(settings.immichPath, ServiceSettings().immichPath)
        XCTAssertFalse(ServiceSettings.keepsData(.adguardHome))
    }
}
