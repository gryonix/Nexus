import XCTest

@testable import gryonixNexus

final class MenuTickPlacementTests: XCTestCase {
    /// Every `.swift` file under `App/`, with its repo-relative path
    private func appSources() throws -> [(path: String, text: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AppTests
            .deletingLastPathComponent()   // Apple
            .appendingPathComponent("App")
        guard let walker = FileManager.default.enumerator(at: root,
                                                          includingPropertiesForKeys: nil) else {
            XCTFail("App/ could not be walked")
            return []
        }
        var found: [(String, String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            found.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        XCTAssertGreaterThan(found.count, 100, "the walk found almost nothing — it is pointed wrong")
        return found
    }

    func testNoMenuItemPutsItsTickInTheImageSlot() throws {
        for source in try appSources() where source.path != "MenuChoice.swift" {
            XCTAssertFalse(source.text.contains("systemImage: \"checkmark\")"),
                           "\(source.path) marks a choice with a leading checkmark image; a menu "
                           + "item that is one of a set uses `MenuChoice` (or a `Toggle`, for a "
                           + "several-of set), which gets the system's own trailing mark")
        }
    }

    func testTheHelperUsesTheMenusOwnSelectionState() throws {
        let source = try appSources().first { $0.path == "MenuChoice.swift" }
        guard let text = source?.text else { return XCTFail("MenuChoice.swift is gone") }
        XCTAssertTrue(text.contains("Toggle(isOn:"),
                      "MenuChoice stopped using the menu's own selection state, which is the only "
                      + "thing that draws the mark on the trailing edge")
    }

    @MainActor
    func testChoosingTheTickedItemChoosesItAgain() {
        var chosen = 0
        let choice = MenuChoice("Wide card", picked: true) { chosen += 1 }
        choice.selection.wrappedValue = false
        XCTAssertEqual(chosen, 1, "a tap on the ticked item did not re-choose it")
        XCTAssertTrue(choice.selection.wrappedValue,
                      "the item reported itself unticked — a one-of set with nothing in it")
    }
}
