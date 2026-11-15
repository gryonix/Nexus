import gryonixNexusCore
import TVLink
import XCTest

@testable import gryonixNexus

/// How long a paired phone's word unlocks an Apple TV
final class TVLicenceRuleTests: XCTestCase {
    private let said = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 3600

    private func phone(plan: String?, active: Bool = true, expires: Int? = nil) -> TVPairedPhone {
        TVPairedPhone(id: "p", name: "orion", pairedAt: said, lastSeen: said,
                      licence: TVLicenceVouch(active: active, plan: plan, expires: expires), licenceAt: said)
    }

    func testASubscriptionUnlocksForTenDays() {
        XCTAssertEqual(TVLicenceRule.unlock(phone(plan: "yearly"))?.until, said.addingTimeInterval(10 * day))
    }

    func testALifetimeLicenseUnlocksForTwentyDays() {
        XCTAssertEqual(TVLicenceRule.unlock(phone(plan: "lifetime"))?.until, said.addingTimeInterval(20 * day))
    }

    func testNeverPastThePhonesOwnEnd() {
        let end = Int(said.timeIntervalSince1970 + 3 * day)
        XCTAssertEqual(TVLicenceRule.unlock(phone(plan: "monthly", expires: end))?.until,
                       said.addingTimeInterval(3 * day))
    }

    func testAnInactivePhoneDoesNotUnlock() {
        XCTAssertNil(TVLicenceRule.unlock(phone(plan: "lifetime", active: false)))
    }

    func testABadTokenDoesNotUnlock() {
        var bad = phone(plan: "lifetime")
        bad.licence?.token = "not.a.token"
        bad.licence?.device = "p"
        XCTAssertNil(TVLicenceRule.unlock(bad))
    }

    func testTheWordRunsOut() {
        XCTAssertNil(TVLicenceRule.best([phone(plan: "yearly")], now: said.addingTimeInterval(11 * day)))
        XCTAssertNotNil(TVLicenceRule.best([phone(plan: "lifetime")], now: said.addingTimeInterval(11 * day)))
    }
}
