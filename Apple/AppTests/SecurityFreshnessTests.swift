import XCTest
@testable import gryonixNexus

@MainActor
final class SecurityFreshnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testNeverReadIsNotFresh() {
        XCTAssertFalse(DashboardViewModel.isFresh(triedAt: nil, known: true, maxAge: 300, now: now))
    }

    func testAGoodReadLastsTheWholeAge() {
        let tried = now.addingTimeInterval(-200)
        XCTAssertTrue(DashboardViewModel.isFresh(triedAt: tried, known: true, maxAge: 300, now: now))
        XCTAssertFalse(DashboardViewModel.isFresh(triedAt: tried, known: true, maxAge: 100, now: now))
    }

    func testAFailedReadWaitsBeforeTryingAgain() {
        XCTAssertTrue(DashboardViewModel.isFresh(triedAt: now.addingTimeInterval(-10), known: false,
                                                 maxAge: 300, now: now))
        XCTAssertFalse(DashboardViewModel.isFresh(triedAt: now.addingTimeInterval(-60), known: false,
                                                  maxAge: 300, now: now))
    }
}
