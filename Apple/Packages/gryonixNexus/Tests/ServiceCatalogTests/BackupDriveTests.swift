import Foundation
@testable import ServiceCatalog
import XCTest

final class BackupDriveTests: XCTestCase {
    private let uuid = "3f2a7c1e-5b8d-4e6f-9a0b-1c2d3e4f5a6b"

    private var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Android/catalog/src/test/resources/storage")
    }

    private func fixture(_ name: String) throws -> String {
        try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
    }

    func testScriptsMatchTheAgent() throws {
        let identity = DiskIdentity(path: "/dev/sdf", serial: "4C530001", sizeBytes: 61_530_439_680)
        XCTAssertEqual(BackupDriveScripts.format(disk: "/dev/sdf", name: "usb1", identity: identity),
                       try fixture("drive-format.sh"))
        XCTAssertEqual(BackupDriveScripts.attach(uuid: uuid, name: "usb1"), try fixture("drive-attach.sh"))
        XCTAssertEqual(BackupDriveScripts.check(uuid: uuid, name: "usb1"), try fixture("drive-check.sh"))
        XCTAssertEqual(BackupDriveScripts.eject(uuid: uuid, name: "usb1"), try fixture("drive-eject.sh"))
        XCTAssertEqual(BackupDriveScripts.forget(uuid: uuid, name: "usb1"), try fixture("drive-forget.sh"))
    }

    func testRemovableDrivesAreFoundAndTheSystemDiskIsNot() throws {
        let hardware = try XCTUnwrap(ServerHardware.parse(try fixture("probe-usb-drives.txt")))
        let drives = BackupDrives.drives(in: hardware, chosen: ["dead-beef": "usb9"])
        XCTAssertFalse(drives.contains { $0.disk?.path == "/dev/sda" }, "the system disk")
        XCTAssertFalse(drives.contains { $0.disk?.path == "/dev/sde" }, "mounted somewhere else")
        let blank = try XCTUnwrap(drives.first { $0.disk?.path == "/dev/sdb" })
        XCTAssertEqual(blank.state, .blank)
        XCTAssertNil(blank.uuid)
        let ready = try XCTUnwrap(drives.first { $0.uuid == uuid })
        XCTAssertEqual(ready.state, .ready)
        XCTAssertEqual(ready.name, "usb1")
        let unmounted = try XCTUnwrap(drives.first { $0.name == "usb2" })
        XCTAssertEqual(unmounted.state, .unmounted)
        let missing = try XCTUnwrap(drives.first { $0.uuid == "dead-beef" })
        XCTAssertEqual(missing.state, .missing)
        XCTAssertEqual(missing.name, "usb9")
    }

    func testNamesAreChecked() {
        XCTAssertTrue(BackupDrives.isValidName("usb1"))
        XCTAssertTrue(BackupDrives.isValidName("backup-2"))
        XCTAssertFalse(BackupDrives.isValidName("USB"))
        XCTAssertFalse(BackupDrives.isValidName("-x"))
        XCTAssertFalse(BackupDrives.isValidName("twelve-chars"))
        XCTAssertFalse(BackupDrives.isValidName("флешка"))
        XCTAssertEqual(BackupDrives.suggestedName(taken: ["usb1", "usb2"]), "usb3")
    }

    func testACheckIsReadFromItsMarkers() {
        let check = BackupDriveCheck.parse("""
        GRYONIXNEXUS_DRIVE_SMART none
        GRYONIXNEXUS_DRIVE_FSCK clean
        GRYONIXNEXUS_DRIVE_SPEED 31457280 104857600
        GRYONIXNEXUS_DRIVE_CHECK_DONE
        """)
        XCTAssertEqual(check.smart, .none)
        XCTAssertEqual(check.filesystem, .clean)
        XCTAssertEqual(check.writeBytesPerSecond, 31_457_280)
        XCTAssertEqual(check.readBytesPerSecond, 104_857_600)
    }

    func testTheNewDrivesUUIDIsReadAfterFormatting() {
        let output = "noise\nGRYONIXNEXUS_DRIVE_UUID \(uuid)\nGRYONIXNEXUS_DRIVE_FORMAT_DONE\n"
        XCTAssertEqual(BackupDriveScripts.formattedUUID(output), uuid)
        XCTAssertTrue(BackupDriveScripts.isDriveCopy("/srv/gryonix-backup/usb1/nextcloud/a.tar.gz"))
        XCTAssertFalse(BackupDriveScripts.isDriveCopy("/opt/backups/nextcloud/a.tar.gz"))
        XCTAssertFalse(BackupDriveScripts.isDriveCopy("/srv/gryonix-backup/../etc/shadow"))
    }
}
