import XCTest
@testable import ServerControl

final class TerminalAccessoryKeysTests: XCTestCase {
    func testCatalogIDsAreUniqueAndDefaultsResolve() {
        let ids = TerminalAccessoryCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(TerminalAccessoryLayout().keys.count, TerminalAccessoryLayout.defaultIDs.count)
    }

    func testFunctionKeySequences() {
        XCTAssertEqual(TerminalAccessoryCatalog.key("f1")?.action, .bytes([0x1B, 0x4F, 0x50]))
        XCTAssertEqual(TerminalAccessoryCatalog.key("f5")?.action, .bytes(Array("\u{1B}[15~".utf8)))
        XCTAssertEqual(TerminalAccessoryCatalog.key("ctrl-C")?.action, .bytes([3]))
    }

    func testAddRemoveMoveReset() {
        var layout = TerminalAccessoryLayout(ids: ["esc", "tab"])
        layout.add("f1")
        layout.add("f1")
        layout.add("nonsense")
        XCTAssertEqual(layout.ids, ["esc", "tab", "f1"])
        layout.move(from: 2, to: 0)
        XCTAssertEqual(layout.ids, ["f1", "esc", "tab"])
        layout.remove(at: 1)
        XCTAssertEqual(layout.ids, ["f1", "tab"])
        layout.reset()
        XCTAssertEqual(layout.ids, TerminalAccessoryLayout.defaultIDs)
    }

    func testStoreRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "accessory-\(UUID())"))
        let store = TerminalAccessoryStore(defaults: defaults)
        XCTAssertEqual(store.load(), TerminalAccessoryLayout())
        let layout = TerminalAccessoryLayout(ids: ["tab", "sym-|"])
        store.save(layout)
        XCTAssertEqual(store.load(), layout)
    }
}
