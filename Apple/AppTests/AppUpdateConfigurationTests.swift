import XCTest

@testable import gryonixNexus

final class AppUpdateConfigurationTests: XCTestCase {
    /// `Apple/` as it sits on disk
    private var appleDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AppTests
            .deletingLastPathComponent()   // Apple
    }

    private func infoPlist() throws -> [String: Any] {
        let url = appleDirectory.appendingPathComponent("App/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any], "App/Info.plist is not a dictionary")
    }

    private func isKeySparkleWouldAccept(_ key: String) -> Bool {
        guard let decoded = Data(base64Encoded: key) else { return false }
        return decoded.count == 32
    }

    func testAPlaceholderSigningKeyIsTheOneAppUpdatesRefusesToStartOn() throws {
        let key = try XCTUnwrap(infoPlist()["SUPublicEDKey"] as? String,
                                "SUPublicEDKey is written by project.yml; without it the Check-for-Updates row has nothing to check")
        guard !isKeySparkleWouldAccept(key) else { return }  // a real key: nothing to pin

        let source = try String(contentsOf: appleDirectory
            .appendingPathComponent("App/Features/Settings/AppUpdates.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("\"\(key)\""),
                      """
                      Info.plist ships \(key), which Sparkle would reject, and AppUpdates does not \
                      name that string — so it would consider this build configured and start an \
                      updater that fails with an alert. Keep `placeholderPublicKey` and project.yml's \
                      SUPublicEDKey the same string.
                      """)
    }

    func testTheAppcastIsFetchedOverHTTPS() throws {
        let feed = try XCTUnwrap(infoPlist()["SUFeedURL"] as? String,
                                 "SUFeedURL is written by project.yml")
        let url = try XCTUnwrap(URL(string: feed), "SUFeedURL is not a URL: \(feed)")
        XCTAssertEqual(url.scheme, "https", "the appcast has to be served over HTTPS")
    }
}
