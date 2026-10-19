import XCTest
import gryonixNexusCore
@testable import gryonixNexus

final class ConfigurationPublishingTests: XCTestCase {
    private let records = [
        DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.4"),
        DNSRecord(name: "example.com", type: .txt, value: "v=spf1 mx -all"),
    ]

    func testTheNameTheAppConnectsByIsPublished() {
        let entry = ConfigurationPublishing.entryRecord(host: "Example.com", zone: "example.com", records: records)
        XCTAssertEqual(entry?.name, "example.com")
        XCTAssertEqual(entry?.type, .a)
        XCTAssertEqual(entry?.value, "203.0.113.4")
    }

    func testAnAddressHostOrAnotherZoneAddsNothing() {
        XCTAssertNil(ConfigurationPublishing.entryRecord(host: "203.0.113.4", zone: "example.com", records: records))
        XCTAssertNil(ConfigurationPublishing.entryRecord(host: "other.org", zone: "example.com", records: records))
    }

    func testANameAlreadyListedIsNotRepeated() {
        XCTAssertNil(ConfigurationPublishing.entryRecord(host: "mail.example.com", zone: "example.com", records: records))
    }
}
