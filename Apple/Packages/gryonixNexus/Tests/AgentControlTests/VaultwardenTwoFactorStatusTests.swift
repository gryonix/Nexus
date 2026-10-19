import XCTest
@testable import AgentControl
import AgentClient

final class VaultwardenTwoFactorStatusTests: XCTestCase {
    private func answer(readable: Bool, users: UInt32, without: UInt32) -> Gryonixnexusd_V1_VaultwardenTwoFactor {
        var message = Gryonixnexusd_V1_VaultwardenTwoFactor()
        message.readable = readable
        message.users = users
        message.usersWithoutTwoFactor = without
        return message
    }

    func testAnUnreadableDatabaseGivesNoStatus() {
        XCTAssertNil(VaultwardenTwoFactorStatus(answer(readable: false, users: 3, without: 3)))
    }

    func testOneAccountWithoutTwoFactorNeedsAttention() throws {
        let status = try XCTUnwrap(VaultwardenTwoFactorStatus(answer(readable: true, users: 4, without: 1)))
        XCTAssertEqual(status, VaultwardenTwoFactorStatus(users: 4, usersWithoutTwoFactor: 1))
        XCTAssertTrue(status.needsAttention)
    }

    func testEveryoneWithTwoFactorNeedsNoAttention() throws {
        let status = try XCTUnwrap(VaultwardenTwoFactorStatus(answer(readable: true, users: 2, without: 0)))
        XCTAssertFalse(status.needsAttention)
    }

    func testNoAccountsNeedsNoAttention() throws {
        let status = try XCTUnwrap(VaultwardenTwoFactorStatus(answer(readable: true, users: 0, without: 0)))
        XCTAssertFalse(status.needsAttention)
    }
}
