import Foundation
@testable import ServiceCatalog
import XCTest

final class ArrayChangeTests: XCTestCase {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Android/catalog/src/test/resources/storage")
    }

    private func fixture(_ name: String) throws -> String {
        try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
    }

    private func assertGolden(_ text: String, _ name: String) throws {
        let url = fixtures.appendingPathComponent(name)
        if ProcessInfo.processInfo.environment["GRYONIXNEXUS_WRITE_STORAGE_GOLDEN"] != nil {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(text, try fixture(name), name)
    }

    private func healthy() throws -> ServerHardware {
        try XCTUnwrap(ServerHardware.parse(try fixture("probe-healthy-arrays.txt")))
    }

    private func array(_ kind: StorageArray.Kind, in hardware: ServerHardware) throws -> StorageArray {
        try XCTUnwrap(StorageArray.all(in: hardware).first { $0.kind == kind })
    }

    private struct Case: Decodable {
        let golden, action, kind, address, name, level, member: String
        let disks, members, checkDisks: [String]
        let devices, newLevel: Int
        let identities: [Identity]

        struct Identity: Decodable {
            let path, serial: String
            let sizeBytes: Int64
        }

        var spec: ArrayChangeSpec {
            ArrayChangeSpec(action: ArrayChange.Action(rawValue: action)!, kind: StorageArray.Kind(rawValue: kind)!,
                            address: address, name: name, level: level, member: member, disks: disks,
                            devices: devices, newLevel: newLevel, members: members, checkDisks: checkDisks,
                            identities: identities.map { DiskIdentity(path: $0.path, serial: $0.serial, sizeBytes: $0.sizeBytes) })
        }
    }

    private func cases() throws -> [Case] {
        try JSONDecoder().decode([Case].self, from: Data(try fixture("array-change-cases.json").utf8))
    }

    func testEveryChangeScriptMatchesItsGolden() throws {
        let all = try cases()
        XCTAssertEqual(all.count, 28)
        for item in all { try assertGolden(item.spec.script(), item.golden) }
    }

    func testTheProbeReadsSerialsAndTheDiskJob() throws {
        let hardware = try healthy()
        XCTAssertEqual(hardware.disks.first { $0.name == "sdb" }?.serial, "WD-WCC4E1AAAAA1")
        let job = try XCTUnwrap(hardware.diskJob)
        XCTAssertEqual(job.action, "grow")
        XCTAssertEqual(job.target, "gryonixnexus")
        XCTAssertEqual(job.outcome, .running)
        XCTAssertEqual(job.lastLines, ["mdadm: Need to wait for the reshape"])
        XCTAssertEqual(RaidPlan.candidates(in: hardware).map(\.name), ["sdi", "sdj"])
    }

    func testAJobThatEndedSaysHow() {
        let done = DiskJob.parse("inactive|GRYONIXNEXUS_DISK_JOB_START remove data 100|moved|GRYONIXNEXUS_DISK_JOB_DONE 200|")
        XCTAssertEqual(done?.outcome, .done)
        XCTAssertEqual(done?.lastLines, ["moved"])
        XCTAssertEqual(done?.isRecent(now: Date(timeIntervalSince1970: 1000)), true)
        XCTAssertEqual(done?.isRecent(now: Date(timeIntervalSince1970: 400_000)), false)
        let failed = DiskJob.parse("failed|GRYONIXNEXUS_DISK_JOB_START grow md 100|oops|GRYONIXNEXUS_DISK_JOB_FAILED 150|")
        XCTAssertEqual(failed?.outcome, .failed)
        let cut = DiskJob.parse("inactive|GRYONIXNEXUS_DISK_JOB_START grow md 100|halfway|")
        XCTAssertEqual(cut?.outcome, .failed, "a job gone without its last line was cut off")
        XCTAssertNil(DiskJob.parse("inactive||"))
    }

    func testEachKindOffersOnlyWhatItCanDo() throws {
        let hardware = try healthy()
        let md = try array(.md, in: hardware)
        XCTAssertEqual(md.raidLevel, .raid5)
        XCTAssertEqual(ArrayChange.actions(for: md, in: hardware),
                       [.addSpare, .grow, .replace, .detach, .changeLevel, .check, .delete],
                       "three disks of RAID 5 cannot shrink")
        XCTAssertEqual(ArrayChange.levels(for: md), [.raid6])
        let pool = try array(.zfs, in: hardware)
        XCTAssertEqual(pool.raidLevel, .raid1)
        XCTAssertEqual(ArrayChange.actions(for: pool, in: hardware),
                       [.addSpare, .grow, .replace, .detach, .remove, .check, .delete])
        let btrfs = try array(.btrfs, in: hardware)
        XCTAssertEqual(ArrayChange.actions(for: btrfs, in: hardware),
                       [.grow, .replace, .changeLevel, .check, .delete])
        XCTAssertEqual(ArrayChange.levels(for: btrfs), [.raid0])
    }

    func testABrokenArrayCanOnlyBeDeleted() throws {
        let degraded = try XCTUnwrap(StorageArray.all(in: try XCTUnwrap(ServerHardware.parse(
            try fixture("probe-raid-degraded.txt")))).first)
        let hardware = try healthy()
        XCTAssertEqual(ArrayChange.actions(for: degraded, in: hardware), [.delete])
        var cache = try array(.md, in: hardware)
        cache = StorageArray(name: RaidPlan.cacheName, uuid: nil, device: "/dev/md126", level: "raid1",
                             members: ["/dev/sdb", "/dev/sdc"], failed: [], slots: 2, working: 2,
                             state: .clean, mountpoint: nil, filesystem: nil)
        XCTAssertFalse(ArrayChange.actions(for: cache, in: hardware).contains(.delete))
    }

    func testThePreviewShowsSpaceAndProtection() throws {
        let hardware = try healthy()
        let sdi = try XCTUnwrap(hardware.disks.first { $0.name == "sdi" })
        let md = try array(.md, in: hardware)
        let grown = ArrayChange(action: .grow, array: md, disks: [sdi]).preview(in: hardware)
        XCTAssertEqual(grown.usableBefore, 2 * 4_000_787_030_016)
        XCTAssertEqual(grown.usableAfter, 3 * 4_000_787_030_016)
        XCTAssertEqual(grown.failuresAfter, 1)
        XCTAssertTrue(grown.takesLong)
        let detached = ArrayChange(action: .detach, array: md, member: "/dev/sdc").preview(in: hardware)
        XCTAssertEqual(detached.failuresAfter, 0)
        XCTAssertFalse(detached.takesLong)
        let pool = try array(.zfs, in: hardware)
        let third = ArrayChange(action: .grow, array: pool, disks: [sdi]).preview(in: hardware)
        XCTAssertEqual(third.usableAfter, third.usableBefore)
        XCTAssertEqual([third.failuresBefore, third.failuresAfter], [1, 2])
        let btrfs = try array(.btrfs, in: hardware)
        let striped = ArrayChange(action: .changeLevel, array: btrfs, level: .raid0).preview(in: hardware)
        XCTAssertEqual(striped.usableAfter, 2 * striped.usableBefore)
        XCTAssertEqual(striped.failuresAfter, 0)
    }

    func testTheSpecFromARealArrayMatchesTheSharedCase() throws {
        let hardware = try healthy()
        let sdi = try XCTUnwrap(hardware.disks.first { $0.name == "sdi" })
        let byName = Dictionary(uniqueKeysWithValues: try cases().map { ($0.golden, $0.spec) })
        let md = try array(.md, in: hardware)
        XCTAssertEqual(ArrayChange(action: .grow, array: md, disks: [sdi]).spec(in: hardware),
                       byName["change-md-grow.sh"])
        XCTAssertEqual(ArrayChange(action: .replace, array: md, member: "/dev/sdc", disks: [sdi]).spec(in: hardware),
                       byName["change-md-replace.sh"])
        let pool = try array(.zfs, in: hardware)
        XCTAssertEqual(ArrayChange(action: .grow, array: pool, disks: [sdi]).spec(in: hardware),
                       byName["change-zfs-grow-mirror.sh"])
        XCTAssertEqual(ArrayChange(action: .delete, array: pool).spec(in: hardware), byName["change-zfs-delete.sh"])
        let btrfs = try array(.btrfs, in: hardware)
        XCTAssertEqual(ArrayChange(action: .replace, array: btrfs, member: "/dev/sdh", disks: [sdi]).spec(in: hardware),
                       byName["change-btrfs-replace.sh"])
    }

    func testNewKindsOfArrayAndDiskWorkMatchTheGolden() throws {
        let hardware = try healthy()
        let free = RaidPlan.candidates(in: hardware)
        let named = RaidPlan.storage(level: .raid1, disks: free, kind: .zfs, in: hardware)
        XCTAssertEqual(named.name, "gryonixnexus2", "the md array holds the first name")
        try assertGolden(named.script(), "zfs-create.sh")
        let four = hardware.disks.filter { ["sdb", "sdc", "sdi", "sdj"].contains($0.name) }
        let pairs = RaidPlan(level: .raid10, disks: four, kind: .zfs, name: "gryonixnexus2",
                             mountPoint: "/srv/gryonixnexus-storage2")
        XCTAssertEqual(pairs.survivableFailures, 1)
        try assertGolden(pairs.script(), "zfs-create-pairs.sh")
        let btrfs = RaidPlan(level: .raid1, disks: free, kind: .btrfs, name: "gryonixnexus2",
                             mountPoint: "/srv/gryonixnexus-storage2")
        XCTAssertEqual(btrfs.survivableFailures, 1)
        XCTAssertFalse(RaidPlan(level: .raid5, disks: free + free, kind: .btrfs).isValid)
        try assertGolden(btrfs.script(), "btrfs-create.sh")
        let format = DiskFormatPlan.plan(for: free[0], filesystem: .ext4, in: hardware)
        XCTAssertEqual(format.mountPoint, "/srv/disk-sdi")
        XCTAssertEqual(format.label, "gnx-sdi")
        try assertGolden(format.script(), "disk-format.sh")
        try assertGolden(DiskFormatPlan(disk: "/dev/sdj", filesystem: .xfs, label: "gnx-sdj",
                                        mountPoint: "/srv/disk-sdj").script(), "disk-format-xfs.sh")
        try assertGolden(DiskReleasePlan(mountPoint: "/srv/disk-sdi").script(), "disk-release.sh")
        try assertGolden(DiskBlink.script(disk: "/dev/sdi"), "disk-blink.sh")
    }
}
