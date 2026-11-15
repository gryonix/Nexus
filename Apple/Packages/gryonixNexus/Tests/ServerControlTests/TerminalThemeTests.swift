import XCTest
@testable import ServerControl

final class TerminalThemeTests: XCTestCase {
    func testEveryBuiltInThemeHasSixteenValidColours() {
        XCTAssertGreaterThanOrEqual(TerminalThemes.builtIn.count, 10)
        for theme in TerminalThemes.builtIn {
            XCTAssertEqual(theme.ansi.count, 16, theme.name)
            XCTAssertTrue(theme.isValid, theme.name)
        }
        XCTAssertEqual(Set(TerminalThemes.builtIn.map(\.id)).count, TerminalThemes.builtIn.count)
    }

    func testLightAndDarkClassification() {
        XCTAssertTrue(TerminalThemes.find("dracula")!.isDark)
        XCTAssertFalse(TerminalThemes.find("solarized-light")!.isDark)
    }

    private func colour(_ red: Double, _ green: Double, _ blue: Double) -> String {
        """
        <dict><key>Red Component</key><real>\(red)</real>
        <key>Green Component</key><real>\(green)</real>
        <key>Blue Component</key><real>\(blue)</real></dict>
        """
    }

    private func plist(skipping: String? = nil) -> Data {
        var body = ""
        for index in 0..<16 { body += "<key>Ansi \(index) Color</key>\(colour(Double(index) / 15, 0, 1))" }
        body += "<key>Background Color</key>\(colour(0, 0, 0))"
        body += "<key>Foreground Color</key>\(colour(1, 1, 1))"
        body += "<key>Cursor Color</key>\(colour(1, 0, 0))"
        if let skipping { body = body.replacingOccurrences(of: "<key>\(skipping)</key>", with: "<key>X</key>") }
        let text = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict>\(body)</dict></plist>"
        return Data(text.utf8)
    }

    func testItermColorsParse() throws {
        let theme = try ITermColorsImport.theme(from: plist(), name: "Test")
        XCTAssertEqual(theme.name, "Test")
        XCTAssertEqual(theme.ansi.count, 16)
        XCTAssertEqual(theme.ansi[15], "#FF00FF")
        XCTAssertEqual(theme.background, "#000000")
        XCTAssertEqual(theme.cursor, "#FF0000")
        XCTAssertEqual(theme.selection, theme.ansi[8])
        XCTAssertTrue(theme.isValid)
    }

    func testItermColorsMissingColourFails() {
        XCTAssertThrowsError(try ITermColorsImport.theme(from: plist(skipping: "Ansi 3 Color"), name: "x"))
        XCTAssertThrowsError(try ITermColorsImport.theme(from: Data("nope".utf8), name: "x"))
    }

    func testServerOverrideBeatsSystemMode() {
        var look = TerminalAppearance()
        look.serverThemes["prod"] = "production-red"
        XCTAssertEqual(look.theme(isDark: false, server: "prod").id, "production-red")
        XCTAssertEqual(look.theme(isDark: false, server: nil).id, TerminalThemes.defaultLightID)
        XCTAssertEqual(look.theme(isDark: true, server: nil).id, TerminalThemes.defaultDarkID)
    }

    func testAppearanceRoundTripAndDefaultsForMissingKeys() throws {
        var look = TerminalAppearance()
        look.fontSize = 17
        look.cursorShape = .bar
        look.save(try ITermColorsImport.theme(from: plist(), name: "Mine"))
        let data = try JSONEncoder().encode(look)
        XCTAssertEqual(try JSONDecoder().decode(TerminalAppearance.self, from: data), look)
        let sparse = try JSONDecoder().decode(TerminalAppearance.self, from: Data("{}".utf8))
        XCTAssertEqual(sparse, TerminalAppearance())
    }

    func testRemovingCustomThemeResetsReferences() throws {
        var look = TerminalAppearance()
        let custom = try ITermColorsImport.theme(from: plist(), name: "Mine")
        look.save(custom)
        look.darkThemeID = custom.id
        look.serverThemes["a"] = custom.id
        look.removeCustom(custom.id)
        XCTAssertEqual(look.darkThemeID, TerminalThemes.defaultDarkID)
        XCTAssertTrue(look.serverThemes.isEmpty)
    }

    func testZoomClamps() {
        var look = TerminalAppearance()
        look.zoom(by: 100)
        XCTAssertEqual(look.fontSize, 32)
        look.zoom(by: 0.001)
        XCTAssertEqual(look.fontSize, 8)
    }
}
