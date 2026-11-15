import ServiceCatalog
import XCTest

final class SiteAddressTests: XCTestCase {
    func testOnlyNamesDNSAcceptsPass() {
        XCTAssertTrue(SiteAddress.isValid("music.example.com"))
        XCTAssertTrue(SiteAddress.isValid("hifi.local"))
        for bad in ["music", "music..example.com", "-a.example.com", "a b.example.com", "musik.ä.de", "a_b.example.com", ""] {
            XCTAssertFalse(SiteAddress.isValid(bad), bad)
        }
        XCTAssertEqual(SiteAddress.normalized("  Music.Example.COM \n"), "music.example.com")
    }
}
