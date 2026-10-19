import ServerControl
import XCTest

@testable import gryonixNexus

final class MetricsPollRecoveryTests: XCTestCase {
    private let third = SSHHostID.node(UUID())
    private let fourth = SSHHostID.node(UUID())

    func testACleanTickKeepsEverything() {
        XCTAssertEqual(MetricsPollRecovery.after(failed: []), .none)
    }

    func testTheEntryHostFailingCostsTheWholeRunner() {
        XCTAssertEqual(MetricsPollRecovery.after(failed: [.vps]), .rebuildRunner)
        XCTAssertEqual(MetricsPollRecovery.after(failed: [.home, .vps]), .rebuildRunner)
        XCTAssertEqual(MetricsPollRecovery.after(failed: [third, .vps]), .rebuildRunner,
                       "the entry host is the entry host whoever else missed the tick")
    }

    func testTheHomeHalfFailingDropsOnlyItsOwnLink() {
        XCTAssertEqual(MetricsPollRecovery.after(failed: [.home]), .dropLinks([.home]))
    }

    /// The case the two flags got wrong
    func testAThirdMachineFailingDoesNotCloseTheHomeSession() {
        let recovery = MetricsPollRecovery.after(failed: [third])
        XCTAssertEqual(recovery, .dropLinks([third]))
        guard case .dropLinks(let hosts) = recovery else { return XCTFail("expected per-host recovery") }
        XCTAssertFalse(hosts.contains(.home),
                       "a machine that did not fail must not lose its session")
        XCTAssertFalse(hosts.contains(.vps),
                       "the parent everything is jumped through must not be dropped for a child's hiccup")
    }

    func testEveryFailingMachineBehindTheEntryHostDropsItsOwnLink() {
        XCTAssertEqual(MetricsPollRecovery.after(failed: [.home, third, fourth]),
                       .dropLinks([.home, third, fourth]))
    }

    func testTheEntryHostIsWhicheverMachineEverythingHangsOff() {
        XCTAssertEqual(MetricsPollRecovery.after(failed: [third], entry: third), .rebuildRunner)
        XCTAssertEqual(MetricsPollRecovery.after(failed: [.vps], entry: third), .dropLinks([.vps]))
    }
}
