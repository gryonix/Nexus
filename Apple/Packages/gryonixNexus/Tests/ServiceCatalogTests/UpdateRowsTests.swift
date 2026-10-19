import XCTest
@testable import ServiceCatalog

final class UpdateRowsTests: XCTestCase {
    private func id(_ s: String) -> ServiceID { ServiceID(rawValue: s) }

    func testAReportedServiceTheDeploymentDoesNotListGetsARow() {
        let rows = UpdateRows.statusRows(
            updatable: [id("nextcloud")],
            deploymentServices: [id("nextcloud")],
            reported: [id("nextcloud"), id("adguard-home")]
        )
        XCTAssertEqual(rows, [id("nextcloud"), id("adguard-home")],
                       "the reported-but-unlisted service is appended after the deployment's own")
    }

    func testTheExtraRowIsNotSilentlyDropped() {
        let rows = UpdateRows.statusRows(
            updatable: [id("nextcloud")],
            deploymentServices: [id("nextcloud")],
            reported: [id("vaultwarden")]
        )
        XCTAssertTrue(rows.contains(id("vaultwarden")))
    }

    func testAReportForAnUpdatableServiceIsNotDuplicated() {
        let rows = UpdateRows.statusRows(
            updatable: [id("nextcloud"), id("immich")],
            deploymentServices: [id("nextcloud"), id("immich"), id("caddy")],
            reported: [id("nextcloud"), id("immich")]
        )
        XCTAssertEqual(rows, [id("nextcloud"), id("immich")])
    }

    func testAListedButNonUpdatableServiceStaysOutEvenWhenReported() {
        let rows = UpdateRows.statusRows(
            updatable: [id("nextcloud")],
            deploymentServices: [id("nextcloud"), id("headscale")],
            reported: [id("nextcloud"), id("headscale")]
        )
        XCTAssertEqual(rows, [id("nextcloud")])
    }

    func testAppendedReportsAreInAStableOrder() {
        let rows = UpdateRows.statusRows(
            updatable: [],
            deploymentServices: [],
            reported: [id("zoneminder"), id("adguard-home"), id("matomo")]
        )
        XCTAssertEqual(rows, [id("adguard-home"), id("matomo"), id("zoneminder")])
    }
}
