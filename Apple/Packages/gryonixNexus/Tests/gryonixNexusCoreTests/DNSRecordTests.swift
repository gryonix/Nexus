import XCTest
@testable import gryonixNexusCore

final class DNSRecordTests: XCTestCase {
    func testShortTXTStaysOneString() {
        XCTAssertEqual(bindTXTRData("v=spf1 mx -all"), "\"v=spf1 mx -all\"")
    }

    func testLongTXTIsSplitIntoQuotedStrings() {
        let key = "v=DKIM1;k=rsa;p=" + String(repeating: "A", count: 392)
        let rendered = bindTXTRData(key)
        let parts = rendered.split(separator: " ").map(String.init)
            .filter { $0.hasPrefix("\"") || $0.hasSuffix("\"") }
        XCTAssertGreaterThan(parts.count, 1, "a 400-character key must be split")
        for part in rendered.split(separator: "\" \"") {
            let bare = part.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            XCTAssertLessThanOrEqual(bare.utf8.count, 255)
        }
        let rejoined = rendered
            .replacingOccurrences(of: "\" \"", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        XCTAssertEqual(rejoined, key)
    }

    func testExactlyAtTheLimitStaysOneString() {
        let value = String(repeating: "x", count: 255)
        XCTAssertEqual(bindTXTRData(value), "\"\(value)\"")
        XCTAssertEqual(bindTXTRData(value + "x").components(separatedBy: "\" \"").count, 2)
    }

    func testQuotingIsEscaped() {
        XCTAssertEqual(bindTXTRData("a\"b"), "\"a\\\"b\"")
        XCTAssertEqual(bindTXTRData("a\\b"), "\"a\\\\b\"")
    }

    func testAnExistingSPFIsJoinedNotReplaced() {
        let ours = DNSRecord(name: "example.com", type: .txt, value: "v=spf1 mx -all")
        let merged = ours.merged(withExisting: "\"v=spf1 include:_spf.google.com ~all\"")
        XCTAssertEqual(merged.value, "v=spf1 include:_spf.google.com mx ~all")
        XCTAssertEqual(ours.merged(withExisting: "v=DMARC1; p=none").value, "v=spf1 mx -all")
    }

    func testASetKeepsTheOwnersOtherTextAndTakesNoSecondSPF() {
        let ours = DNSRecord(name: "example.com", type: .txt, value: "v=spf1 mx -all")
        let existing = ["\"google-site-verification=abc\"", "\"v=spf1 include:mailgun.org -all\""]
        let updated = ours.updatedSet(existing: existing) { bindTXTRData($0.value) }
        XCTAssertEqual(updated, ["\"google-site-verification=abc\"", "\"v=spf1 include:mailgun.org mx -all\""])
        let dmarc = DNSRecord(name: "_dmarc.example.com", type: .txt, value: "v=DMARC1; p=quarantine")
        XCTAssertNil(dmarc.updatedSet(existing: ["\"v=DMARC1; p=reject\""]) { bindTXTRData($0.value) })
    }

    func testAnAddressIsAddedToItsSetOnlyWhenAbsent() {
        let record = DNSRecord(name: "mail.example.com", type: .a, value: "203.0.113.9")
        XCTAssertEqual(record.updatedSet(existing: ["198.51.100.1"]) { $0.value }, ["198.51.100.1", "203.0.113.9"])
        XCTAssertNil(record.updatedSet(existing: ["203.0.113.9", "198.51.100.1"]) { $0.value })
    }
}
