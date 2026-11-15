import XCTest
@testable import gryonixNexus

final class PendingAgentUpdatesTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "PendingAgentUpdatesTests")
        defaults.removePersistentDomain(forName: "PendingAgentUpdatesTests")
    }

    private func entry(_ id: UUID = UUID(), startedAt: Date = Date()) -> PendingAgentUpdates.Entry {
        .init(deploymentID: id, installed: "26.10.20", target: "26.10.26", source: .bundled, startedAt: startedAt)
    }

    func testAnUpdateStartedBeforeARelaunchIsStillThere() {
        let started = entry()
        PendingAgentUpdates(defaults: defaults).add([started])
        XCTAssertEqual(PendingAgentUpdates(defaults: defaults).load(), [started])
    }

    func testAFinishedUpdateIsForgotten() {
        let first = entry(), second = entry()
        let store = PendingAgentUpdates(defaults: defaults)
        store.add([first, second])
        store.remove(first.deploymentID)
        XCTAssertEqual(store.load(), [second])
    }

    func testStartingAgainReplacesTheOldRecord() {
        let id = UUID()
        let store = PendingAgentUpdates(defaults: defaults)
        store.add([entry(id, startedAt: Date().addingTimeInterval(-60))])
        let again = entry(id)
        store.add([again])
        XCTAssertEqual(store.load(), [again])
    }

    func testAnUpdateFromLongAgoIsGivenUp() {
        let store = PendingAgentUpdates(defaults: defaults)
        store.add([entry(startedAt: Date().addingTimeInterval(-PendingAgentUpdates.keptFor - 1))])
        XCTAssertTrue(store.load().isEmpty)
    }

    func testARemovedServerTakesItsUpdateAlong() {
        let kept = entry(), gone = entry()
        let store = PendingAgentUpdates(defaults: defaults)
        store.add([kept, gone])
        store.keep([kept.deploymentID])
        XCTAssertEqual(store.load(), [kept])
    }
}
