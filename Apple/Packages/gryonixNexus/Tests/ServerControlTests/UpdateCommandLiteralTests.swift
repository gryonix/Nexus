import XCTest
@testable import ServerControl

/// The client half of the update wrapper's contract
final class UpdateCommandLiteralTests: XCTestCase {
    func testTheWrapperPathAndMarkers() {
        XCTAssertEqual(CommandCatalog.Updates.controlScriptPath, "/opt/gryonixnexus-update-ctl.sh")
        XCTAssertEqual(CommandCatalog.Updates.doneMarker, "GRYONIXNEXUS_UPDATE_CTL_DONE")
        XCTAssertEqual(CommandCatalog.Updates.availableMarker, "GRYONIXNEXUS_UPDATE_AVAILABLE")
        XCTAssertEqual(CommandCatalog.Updates.currentMarker, "GRYONIXNEXUS_UPDATE_CURRENT")
        XCTAssertEqual(CommandCatalog.Updates.unknownMarker, "GRYONIXNEXUS_UPDATE_UNKNOWN")
        XCTAssertEqual(CommandCatalog.Updates.updatedMarker, "GRYONIXNEXUS_UPDATE_DONE")
        XCTAssertEqual(CommandCatalog.Updates.rolledBackMarker, "GRYONIXNEXUS_UPDATE_ROLLED_BACK")
        XCTAssertEqual(CommandCatalog.Updates.failedMarker, "GRYONIXNEXUS_UPDATE_FAILED")
    }

    /// The subcommands, spelled the way the wrapper's `case` reads them
    func testTheSubcommandsTheWrapperAnswersTo() {
        XCTAssertEqual(CommandCatalog.Updates.check(nil),
                       "sudo /opt/gryonixnexus-update-ctl.sh check --all")
        XCTAssertEqual(CommandCatalog.Updates.check("nextcloud"),
                       "sudo /opt/gryonixnexus-update-ctl.sh check nextcloud")
        XCTAssertEqual(CommandCatalog.Updates.run("nextcloud"),
                       "sudo /opt/gryonixnexus-update-ctl.sh run 'nextcloud'")
        XCTAssertEqual(CommandCatalog.Updates.readStatus,
                       "sudo /opt/gryonixnexus-update-ctl.sh status")
    }

    func testTheScheduleArgument() {
        XCTAssertEqual(
            CommandCatalog.Updates.setSchedule(.days(count: 1, hour: 4, minute: 0),
                                               services: ["nextcloud", "immich"]),
            "sudo /opt/gryonixnexus-update-ctl.sh set-schedule every:1d@04:00 nextcloud immich")
        XCTAssertEqual(CommandCatalog.Updates.setSchedule(.off, services: []),
                       "sudo /opt/gryonixnexus-update-ctl.sh set-schedule off")
        XCTAssertEqual(
            CommandCatalog.Updates.setSchedule(.hours(count: 6, minute: 30), services: ["forgejo"]),
            "sudo /opt/gryonixnexus-update-ctl.sh set-schedule every:6h@00:30 forgejo")
    }

    func testTheScheduleIsReadFromTheFileTheWrapperWrites() {
        XCTAssertEqual(CommandCatalog.Updates.readSchedule,
                       "cat /etc/gryonixnexus/autoupdate.conf 2>/dev/null || true")
        let parsed = ServiceUpdateOperations.parseSchedule("SCHEDULE=every:1d@04:00\nSERVICES='nextcloud immich'\n")
        XCTAssertEqual(parsed.schedule, .days(count: 1, hour: 4, minute: 0))
        XCTAssertEqual(parsed.services, ["nextcloud", "immich"])
    }
}
