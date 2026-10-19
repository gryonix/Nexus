import XCTest

@testable import ServiceCatalog

final class XrayRealitySiteTests: XCTestCase {
    func testASiteNameIsLowercasedAndTrimmed() {
        XCTAssertEqual(XrayRealityService.normalisedSite("  WWW.Apple.com "), "www.apple.com")
    }

    func testWhatIsNotAHostNameIsRefused() {
        for text in ["", "apple", "a b.com", "https://www.apple.com", "-a.com", "a..com", "www.apple.com/x"] {
            XCTAssertNil(XrayRealityService.normalisedSite(text), text)
        }
    }

    func testEverySuggestedSiteIsAHostName() {
        for site in XrayRealityService.suggestedSites {
            XCTAssertEqual(XrayRealityService.normalisedSite(site), site)
        }
    }
}
