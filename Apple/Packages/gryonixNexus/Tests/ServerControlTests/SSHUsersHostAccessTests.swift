import XCTest
@testable import ServerControl

/// The accounts correct the host-wide reading
final class SSHUsersHostAccessTests: XCTestCase {
    private func host(open: Bool, known: Bool = true) -> SSHPasswordAccess {
        SSHPasswordAccess(passwordLoginOpen: open, isKnown: known, appKeyPresent: true,
                          dropInPresent: true, sshdPresent: true, loginUser: "owner",
                          detail: "")
    }

    private func user(_ name: String, open: Bool, known: Bool = true) -> SSHUserAccess {
        SSHUserAccess(name: name, passwordLoginOpen: open, isKnown: known, hasKeys: true,
                      appKeyPresent: name == "owner", isLoginUser: name == "owner")
    }

    private func answer(_ users: [SSHUserAccess], host: SSHPasswordAccess) -> SSHUsers {
        SSHUsers(users: users, host: host, detail: "", isKnown: true)
    }

    func testEveryAccountClosedClosesTheHostRow() {
        let users = answer([user("owner", open: false), user("root", open: false)],
                           host: host(open: true))
        XCTAssertTrue(users.hostAccess.isClosed,
                      "the host-wide read cannot see a Match User block and the row believed it")
        XCTAssertFalse(users.hostAccess.isOutranked,
                       "a host closed account by account is not one cloud-init outranks")
    }

    func testOneOpenAccountLeavesTheHostRowOpen() {
        let users = answer([user("owner", open: false), user("root", open: true)],
                           host: host(open: true))
        XCTAssertTrue(users.hostAccess.isOpen, "root still takes passwords")
    }

    func testAnAccountNobodyCouldAskLeavesTheHostRowOpen() {
        let users = answer([user("owner", open: false), user("root", open: false, known: false)],
                           host: host(open: true))
        XCTAssertTrue(users.hostAccess.isOpen, "an unread account was taken for a closed one")
    }

    func testAHostNobodyCouldAskIsNotCorrected() {
        let users = answer([user("owner", open: false)], host: host(open: false, known: false))
        XCTAssertFalse(users.hostAccess.isKnown, "an unread host was answered for")
    }

    func testAnEmptyAccountListChangesNothing() {
        let users = answer([], host: host(open: true))
        XCTAssertTrue(users.hostAccess.isOpen, "no accounts is not every account")
    }
}
