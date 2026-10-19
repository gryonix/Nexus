import XCTest

@testable import gryonixNexus

final class SettingsScreenOrderTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path),
                   encoding: .utf8)
    }

    func testSettingsHasNoDemoSwitch() throws {
        let text = try source("App/Features/Settings/AppSettingsView.swift")
        XCTAssertFalse(text.contains("Text(\"Demo fleet\")"),
                       "the demo switch lives in the License screen only")
    }

    func testTheDemoSwitchLivesInTheLicenseScreen() throws {
        let text = try source("App/Features/Licensing/LicenseView.swift")
        XCTAssertTrue(text.contains("Text(\"Demo fleet\")"), "the demo switch is gone from License")
    }
}
