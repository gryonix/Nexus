import XCTest
import ServerControl
@testable import gryonixNexus

final class FileBrowserShortcutsTests: XCTestCase {
    func testShortcutsSurviveANewStore() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "files.shortcuts.test.\(UUID().uuidString)"))
        let id = UUID()
        var shortcuts = FileShortcuts()
        shortcuts.toggleBookmark("/srv/data")
        shortcuts.noteOpened("/srv/data/a.txt")
        FileShortcutsStore(deploymentID: id, defaults: defaults).save(shortcuts)
        let loaded = FileShortcutsStore(deploymentID: id, defaults: defaults).load()
        XCTAssertEqual(loaded, shortcuts)
        XCTAssertEqual(FileShortcutsStore(deploymentID: UUID(), defaults: defaults).load(), FileShortcuts())
    }
}
