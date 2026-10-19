import AgentClient
import XCTest

@testable import AgentControl

final class VaultMergeTests: XCTestCase {
    private func entry(_ id: String, _ password: String, at: Int64,
                       by: String = "phone-a", deleted: Bool = false) -> Gryonixnexusd_V1_VaultEntry {
        var e = Gryonixnexusd_V1_VaultEntry()
        e.id = id
        e.host = "single"
        e.title = "Vaultwarden"
        e.password = password
        e.updatedAt = at
        e.updatedBy = by
        e.deleted = deleted
        return e
    }

    func testTheNewerEditWinsWhicheverSideItIsOn() {
        let mine = entry("a", "mine", at: 200)
        let theirs = entry("a", "theirs", at: 100)
        XCTAssertEqual(VaultMerge.merged(local: [mine], remote: [theirs]).first?.password, "mine")
        XCTAssertEqual(VaultMerge.merged(local: [entry("a", "mine", at: 100)],
                                         remote: [entry("a", "theirs", at: 200)]).first?.password,
                       "theirs")
    }

    func testEntriesOnlyOneSideHasAreKept() {
        let merged = VaultMerge.merged(local: [entry("a", "x", at: 1)],
                                       remote: [entry("b", "y", at: 1)])
        XCTAssertEqual(merged.map(\.id), ["a", "b"])
    }

    func testADeleteIsNotUndoneByAnOlderCopy() {
        let tombstone = entry("a", "", at: 200, deleted: true)
        let stale = entry("a", "hunter2", at: 100)
        XCTAssertTrue(VaultMerge.merged(local: [stale], remote: [tombstone]).isEmpty,
                      "an old copy brought a deleted entry back")
    }

    func testARecordedAgainEntryComesBack() {
        let tombstone = entry("a", "", at: 100, deleted: true)
        let again = entry("a", "fresh", at: 200)
        XCTAssertEqual(VaultMerge.merged(local: [again], remote: [tombstone]).first?.password, "fresh")
    }

    /// Same millisecond, two devices
    func testATieIsBrokenTheSameWayOnBothDevices() {
        let a = entry("id", "from-a", at: 500, by: "phone-a")
        let b = entry("id", "from-b", at: 500, by: "phone-b")
        let onOnePhone = VaultMerge.merged(local: [a], remote: [b]).first?.password
        let onTheOther = VaultMerge.merged(local: [b], remote: [a]).first?.password
        XCTAssertEqual(onOnePhone, onTheOther)
        XCTAssertEqual(onOnePhone, "from-b")
    }

    func testOnlyWhatIsNewerOrUnknownIsPushed() {
        let local = [entry("newer", "x", at: 200),
                     entry("older", "x", at: 100),
                     entry("unseen", "x", at: 100)]
        let remote = [entry("newer", "y", at: 100),
                      entry("older", "y", at: 200)]
        XCTAssertEqual(VaultMerge.toPush(local: local, remote: remote).map(\.id),
                       ["newer", "unseen"])
    }

    func testALocalDeleteIsPushed() {
        let local = [entry("a", "", at: 300, deleted: true)]
        let remote = [entry("a", "hunter2", at: 100)]
        XCTAssertEqual(VaultMerge.toPush(local: local, remote: remote).map(\.id), ["a"])
    }

    func testAnEntryWithNoIdIsIgnoredRatherThanSyncedAsBlank() {
        XCTAssertTrue(VaultMerge.merged(local: [entry("", "x", at: 1)], remote: []).isEmpty)
        XCTAssertTrue(VaultMerge.toPush(local: [entry("", "x", at: 1)], remote: []).isEmpty)
    }
}
