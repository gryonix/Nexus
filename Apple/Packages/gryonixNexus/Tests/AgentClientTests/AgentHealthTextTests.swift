import XCTest
@testable import AgentClient

final class AgentHealthTextTests: XCTestCase {
    func testBytesUseMemoryUnits() {
        XCTAssertTrue(AgentHealthText.bytes(24 * 1024 * 1024).contains("24"))
        XCTAssertTrue(AgentHealthText.bytes(24 * 1024 * 1024).contains("MB"))
    }

    func testHugeCountDoesNotTrap() {
        XCTAssertFalse(AgentHealthText.bytes(UInt64.max).isEmpty)
    }

    func testUnsetStartHasNoText() {
        XCTAssertNil(AgentHealthText.startedAt(0))
        XCTAssertNil(AgentHealthText.runningSince(0))
    }

    func testRunningSinceIsRelative() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let started = Int64((1_000_000 - 3 * 86_400) * 1000)
        let text = AgentHealthText.runningSince(started, now: now, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(text, "3 days ago")
    }
}
