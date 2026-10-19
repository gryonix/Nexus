import XCTest

@testable import ServerControl

final class DiskRowPlanTests: XCTestCase {
    private func mount(_ target: String, used: Int64 = 1, size: Int64 = 10) -> DiskMount {
        DiskMount(target: target, sizeBytes: size, usedBytes: used,
                  usedPercent: Int(used * 100 / size))
    }

    func testTheRootFilesystemIsTheOnlyPrimaryRow() {
        let plan = DiskRowPlan.make(mounts: [mount("/boot"), mount("/"), mount("/boot/efi")])
        XCTAssertEqual(plan.primary.map(\.target), ["/"])
        XCTAssertEqual(plan.others.map(\.target), ["/boot", "/boot/efi"])
        XCTAssertFalse(plan.namesPrimaryByTarget)
    }

    func testTheOtherVolumesAreKeptBehindTheirOwnLine() {
        let plan = DiskRowPlan.make(mounts: [mount("/"), mount("/boot"), mount("/srv")])
        XCTAssertEqual(plan.primary.map(\.target), ["/"])
        XCTAssertEqual(plan.others.map(\.target), ["/boot", "/srv"])
        XCTAssertFalse(plan.namesPrimaryByTarget,
                       "a root was reported, so the row is called 'Disk' and not '/'")
    }

    func testAHostWithNoRootMountListsEveryMountItDidReport() {
        let plan = DiskRowPlan.make(mounts: [mount("/mnt/data"), mount("/mnt/backup")])
        XCTAssertEqual(plan.primary.map(\.target), ["/mnt/data", "/mnt/backup"])
        XCTAssertTrue(plan.namesPrimaryByTarget,
                      "three rows all called 'Disk' are not three answers")
        XCTAssertEqual(plan.others, [], "everything is already primary; nothing is left to fold")
    }

    func testNoMountsAtAllPlansNoRows() {
        let plan = DiskRowPlan.make(mounts: [])
        XCTAssertEqual(plan.primary, [])
        XCTAssertEqual(plan.others, [])
    }

    func testTheHostsOwnOrderIsKept() {
        let plan = DiskRowPlan.make(mounts: [mount("/"), mount("/srv"), mount("/boot")])
        XCTAssertEqual(plan.others.map(\.target), ["/srv", "/boot"])
    }
}
