@testable import ServerControl
import ServiceCatalog
import XCTest

final class BackupPartsParsingTests: XCTestCase {
    func testShowPartsIsRead() {
        let choice = BackupPartsParsing.parse("""
        BACKUP_PARTS='files databases'
        UPDATE_PARTS=''
        GRYONIXNEXUS_BACKUP_CTL_DONE
        """)
        XCTAssertEqual(choice.regular, [.files, .databases])
        XCTAssertEqual(choice.beforeUpdate, [])
    }

    func testMissingLinesKeepTheWrapperDefaults() {
        let choice = BackupPartsParsing.parse("GRYONIXNEXUS_BACKUP_CTL_DONE")
        XCTAssertEqual(choice.regular, Set(BackupPart.allCases))
        XCTAssertEqual(choice.beforeUpdate, [.settings, .databases])
    }

    func testWordsFollowTheWrappersOrder() {
        XCTAssertEqual(BackupPartsParsing.words([.databases, .files]), ["files", "databases"])
        XCTAssertEqual(CommandCatalog.Backups.setParts(scope: "update", parts: ["settings"]),
                       "sudo /opt/gryonixnexus-backup-ctl.sh set-parts 'update' 'settings'")
    }

    func testAServiceKeepsItsOwnLinesAndBorrowsTheRest() {
        let state = BackupPartsParsing.state("""
        BACKUP_PARTS='databases'
        UPDATE_PARTS='settings databases'
        UPDATE_PARTS_minecraft_java='files'
        BACKUP_PARTS_Bad='files'
        """)
        XCTAssertEqual(Array(state.services.keys), ["minecraft-java"])
        XCTAssertEqual(state.choice(for: "minecraft-java").beforeUpdate, [.files])
        XCTAssertEqual(state.choice(for: "minecraft-java").regular, [.databases])
        XCTAssertEqual(state.choice(for: "immich"), state.choice)
        XCTAssertEqual(CommandCatalog.Backups.setParts(scope: "backup", service: "immich", parts: ["files"]),
                       "sudo /opt/gryonixnexus-backup-ctl.sh set-parts 'backup' '--service' 'immich' 'files'")
    }

    func testTheSharedSwitchFollowsEveryServiceAndSetsThemAll() {
        let listed = ["immich", "nextcloud"]
        var state = BackupPartsState()
        XCTAssertTrue(state.sharedIsOn(.files, .regular, among: listed))
        state = state.applying(state.settingService("immich", .files, .regular, on: false))
        XCTAssertFalse(state.sharedIsOn(.files, .regular, among: listed), "one service off turns the shared off")
        XCTAssertTrue(state.choice(for: "nextcloud").regular.contains(.files))
        let change = state.settingShared(.files, .regular, on: true, among: listed)
        XCTAssertEqual(Set(change.services.keys), Set(listed))
        state = state.applying(change)
        XCTAssertTrue(state.sharedIsOn(.files, .regular, among: listed))
        XCTAssertEqual(state.choice(for: "immich").beforeUpdate, [.settings, .databases], "the other scope stays")
    }
}
