@testable import ServerControl
import XCTest

final class BackupDrivesParsingTests: XCTestCase {
    func testShowDrivesIsRead() {
        let state = BackupDrivesParsing.parse("""
        DRIVE_MODE=drive
        DRIVE_ENCRYPT=0
        DRIVES=aa-11 bb-22
        DRIVE_PASS=1
        DRIVE=aa-11 1 61530439680 30000000000 /srv/gryonix-backup/usb1
        DRIVE=bb-22 0 0 0 /srv/gryonix-backup/usb2
        DRIVE_AT=1700000000
        DRIVE_OK=0
        DRIVE_ERROR='usb2: not connected;'
        GRYONIXNEXUS_BACKUP_CTL_DONE
        """)
        XCTAssertEqual(state.settings.mode, .drive)
        XCTAssertFalse(state.settings.encrypt)
        XCTAssertEqual(state.settings.uuids, ["aa-11", "bb-22"])
        XCTAssertTrue(state.hasPassphrase)
        XCTAssertEqual(state.statuses.count, 2)
        XCTAssertTrue(state.statuses[0].mounted)
        XCTAssertEqual(state.statuses[0].freeBytes, 30_000_000_000)
        XCTAssertEqual(state.statuses[1].name, "usb2")
        XCTAssertEqual(state.namesByUUID["bb-22"], "usb2")
        XCTAssertFalse(state.lastCopySucceeded)
        XCTAssertEqual(state.lastError, "usb2: not connected;")
        XCTAssertNotNil(state.lastCopy)
    }

    func testAFreshServerEncryptsByDefault() {
        let state = BackupDrivesParsing.parse("GRYONIXNEXUS_BACKUP_CTL_DONE\n")
        XCTAssertEqual(state.settings.mode, .both)
        XCTAssertTrue(state.settings.encrypt)
        XCTAssertTrue(state.settings.uuids.isEmpty)
    }

    func testSetDrivesQuotesEveryArgument() {
        XCTAssertEqual(CommandCatalog.Backups.setDrives(mode: "both", encrypt: true, uuids: ["aa-11"]),
                       "sudo /opt/gryonixnexus-backup-ctl.sh set-drives 'both' '1' 'aa-11'")
    }

    func testFormattingReplacesTheDrivesOldFilesystem() {
        let state = BackupDrivesState(
            settings: BackupDriveSettings(uuids: ["old-1", "other-2", "stale-3"]),
            statuses: [BackupDriveStatus(uuid: "old-1", mountPoint: "/srv/gryonix-backup/usb1"),
                       BackupDriveStatus(uuid: "other-2", mountPoint: "/srv/gryonix-backup/usb2"),
                       BackupDriveStatus(uuid: "stale-3", mountPoint: "/srv/gryonix-backup/usb3")])
        XCTAssertEqual(state.settings(formatted: "new-4", replacing: "old-1", name: "usb3").uuids,
                       ["other-2", "new-4"], "the old filesystem and the name's previous owner go")
        XCTAssertEqual(state.settings(formatted: "new-4", replacing: nil, name: "usb9").uuids,
                       ["old-1", "other-2", "stale-3", "new-4"])
    }

    func testADriveWithoutMountPointIsUnmapped() {
        let state = BackupDrivesState(statuses: [BackupDriveStatus(uuid: "aa", mountPoint: "/srv/gryonix-backup/usb1"),
                                                 BackupDriveStatus(uuid: "bb")])
        XCTAssertFalse(state.isUnmapped("aa"))
        XCTAssertTrue(state.isUnmapped("bb"))
        XCTAssertTrue(state.isUnmapped("cc"))
    }
}
