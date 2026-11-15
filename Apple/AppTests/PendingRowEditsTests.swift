import ServerControl
import XCTest

@testable import gryonixNexus

/// Edits of several rows wait and apply together
@MainActor
final class PendingRowEditsTests: XCTestCase {
    private func edit(_ id: String, succeeds: Bool = true, applied: @escaping () -> Void = {},
                      reverted: @escaping () -> Void = {}) -> PendingRowEdits.Edit {
        PendingRowEdits.Edit(id: id, text: .apply,
                             apply: {
                                 applied()
                                 return succeeds
                             },
                             revert: reverted)
    }

    func testAnOfferedEditRaisesTheBarAndAnUnchangedOneLowersIt() {
        let edits = PendingRowEdits()
        XCTAssertNil(edits.phase)
        edits.offer(edit("a"), changed: true)
        XCTAssertEqual(edits.phase, .waiting)
        edits.offer(edit("a"), changed: false)
        XCTAssertNil(edits.phase)
        XCTAssertTrue(edits.edits.isEmpty)
    }

    func testOneRowOfferedTwiceWaitsOnce() {
        let edits = PendingRowEdits()
        edits.offer(edit("a"), changed: true)
        edits.offer(edit("a"), changed: true)
        edits.offer(edit("b"), changed: true)
        XCTAssertEqual(edits.edits.map(\.id), ["a", "b"])
    }

    func testCancelPutsEveryRowBack() {
        let edits = PendingRowEdits()
        var reverted: [String] = []
        edits.offer(edit("a", reverted: { reverted.append("a") }), changed: true)
        edits.offer(edit("b", reverted: { reverted.append("b") }), changed: true)
        edits.revert()
        XCTAssertEqual(reverted, ["a", "b"])
        XCTAssertNil(edits.phase)
    }

    func testApplyRunsEveryEditAndKeepsTheFailedOneWaiting() async throws {
        let edits = PendingRowEdits()
        var applied: [String] = []
        edits.offer(edit("a", applied: { applied.append("a") }), changed: true)
        edits.offer(edit("b", succeeds: false, applied: { applied.append("b") }), changed: true)
        edits.apply()
        XCTAssertEqual(edits.phase, .applying)
        for _ in 0..<50 where edits.phase == .applying { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(applied, ["a", "b"])
        XCTAssertEqual(edits.edits.map(\.id), ["b"])
        XCTAssertEqual(edits.phase, .waiting)
    }

    func testANewOfferIsIgnoredWhileApplying() async throws {
        let edits = PendingRowEdits()
        edits.offer(edit("a"), changed: true)
        edits.apply()
        edits.offer(edit("b"), changed: true)
        XCTAssertEqual(edits.edits.map(\.id), ["a"])
        for _ in 0..<50 where edits.phase == .applying { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(edits.phase, .done)
    }

    func testHubSettingsBecomeCallsOnlyWhereTheyDiffer() {
        var state = AudioHubState()
        state.bluetoothPowered = false
        var draft = AudioHubDraft()
        XCTAssertTrue(draft.calls(against: state).isEmpty)
        draft.bluetooth = false
        XCTAssertTrue(draft.calls(against: state).isEmpty, "the same value is no change")
        draft.bluetooth = true
        XCTAssertEqual(draft.calls(against: state), ["/bluetooth/power_up"])
        state.bluetoothPowered = true
        draft.bluetooth = false
        XCTAssertEqual(draft.calls(against: state), ["/bluetooth/power_down"])
    }
}
