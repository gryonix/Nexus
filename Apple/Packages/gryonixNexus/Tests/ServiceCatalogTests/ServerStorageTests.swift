import Foundation
@testable import ServiceCatalog
import XCTest

final class ServerStorageTests: XCTestCase {
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

    private func hardware() throws -> ServerHardware {
        try XCTUnwrap(ServerHardware.parse(try fixture("probe-output.txt")))
    }

    /// Compares with the shared golden, writing it on request
    private func assertGolden(_ text: String, _ name: String) throws {
        let url = fixtures.appendingPathComponent(name)
        if ProcessInfo.processInfo.environment["GRYONIXNEXUS_WRITE_STORAGE_GOLDEN"] != nil {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(text, try fixture(name), name)
    }

    func testTheProbeReadsCoresMemoryAndEveryRealDisk() throws {
        let hardware = try hardware()
        XCTAssertEqual(hardware.cpuCores, 8)
        XCTAssertEqual(hardware.memoryBytes, 16_777_216_000)
        XCTAssertEqual(hardware.architecture, "x86_64")
        XCTAssertEqual(hardware.disks.map(\.name), ["sda", "nvme0n1", "sdb", "sdc", "sdd"])
        XCTAssertEqual(hardware.disks.map(\.kind), [.ssd, .nvme, .hdd, .hdd, .ssd])
        XCTAssertTrue(hardware.disks[0].isSystem)
        XCTAssertTrue(hardware.disks[1].isBlank)
        XCTAssertFalse(hardware.disks[3].isBlank)
        XCTAssertEqual(hardware.disks[4].dataMount, "/mnt/fast")
    }

    func testARealDebianServerParses() throws {
        let live = try XCTUnwrap(ServerHardware.parse(try fixture("probe-live-debian13.txt")))
        XCTAssertEqual(live.cpuCores, 12)
        XCTAssertEqual(live.disks.map(\.name), ["vda"])
        XCTAssertTrue(live.disks[0].isSystem)
        XCTAssertEqual(live.disks[0].kind, .hdd)
        XCTAssertTrue(FastStoragePlan.candidates(in: live).isEmpty)
        XCTAssertTrue(RaidPlan.candidates(in: live).isEmpty)
    }

    func testCandidatesNeverOfferTheSystemDisk() throws {
        let hardware = try hardware()
        XCTAssertEqual(FastStoragePlan.candidates(in: hardware).map(\.name), ["nvme0n1", "sdd"])
        XCTAssertEqual(RaidPlan.candidates(in: hardware).map(\.name), ["nvme0n1", "sdb", "sdc"])
    }

    func testTheVerdictNamesWhatIsShort() throws {
        let hardware = try hardware()
        let roomy = HardwareVerdict.judge(hardware, against: ServerRequirements(
            memoryMB: 4096, diskGB: 20, installsDocker: true))
        XCTAssertEqual(roomy.level, .fits)
        let short = HardwareVerdict.judge(hardware, against: ServerRequirements(
            memoryMB: 32_768, diskGB: 55, installsDocker: true))
        XCTAssertEqual(short.level, .doesNotFit)
        XCTAssertEqual(short.findings.map(\.level), [.doesNotFit, .tight])
    }

    func testHotPathsComeFromTheComposeFiles() {
        let context = ServiceContext(domain: "example.com", sshUser: "admin")
        let files = [ServiceID.immich, .nextcloud].compactMap {
            ServiceRegistry.service($0)?.composeFile(context)
        }
        XCTAssertEqual(FastStoragePlan.hotPaths(in: files),
                       ["/opt/immich/ml-cache", "/opt/immich/postgres", "/opt/nextcloud/db"])
    }

    func testFastStorageScriptsMatchTheGolden() throws {
        let hardware = try hardware()
        let hot = ["/opt/immich/postgres", "/opt/nextcloud/db"]
        try assertGolden(FastStoragePlan(disk: hardware.disks[1], hotPaths: hot).script(),
                         "fast-blank.sh")
        try assertGolden(FastStoragePlan(disk: hardware.disks[4], hotPaths: hot).script(),
                         "fast-mounted.sh")
    }

    func testRaidScriptMatchesTheGoldenAndLevelsAddUp() throws {
        let hardware = try hardware()
        let plan = RaidPlan(level: .raid1, disks: [hardware.disks[2], hardware.disks[3]])
        XCTAssertTrue(plan.isValid)
        XCTAssertEqual(plan.usableBytes, 4_000_787_030_016)
        XCTAssertFalse(RaidPlan(level: .raid5, disks: [hardware.disks[2]]).isValid)
        XCTAssertEqual(RaidPlan.Level.raid6.usableBytes(of: [4, 4, 4, 5]), 8)
        try assertGolden(plan.script(), "raid1.sh")
    }

    func testTheGuardCarriesTheSerialAndSizeTheAppSaw() throws {
        let hardware = try hardware()
        var named = hardware.disks[2]
        named.serial = "WD WCC4E1 77"
        let plan = RaidPlan(level: .raid1, disks: [named, hardware.disks[3]])
        try assertGolden(plan.script(), "raid1-serials.sh")
        XCTAssertEqual(named.identity, DiskIdentity(path: "/dev/sdb", serial: "WDWCC4E177", sizeBytes: 4_000_787_030_016))
    }

    func testADiskWithoutASizeIsNotPinned() {
        let lines = ArrayScript.diskGuard([DiskIdentity(path: "/dev/sdz", serial: "X", sizeBytes: 0)])
        XCTAssertEqual(lines, ArrayScript.diskGuard())
    }

    private func arrays(_ name: String) throws -> [StorageArray] {
        StorageArray.all(in: try XCTUnwrap(ServerHardware.parse(try fixture(name))))
    }

    func testAnArrayLeftByAnEarlierInstallIsFoundStopped() throws {
        let found = try arrays("probe-raid-stopped.txt")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].name, "gryonixnexus")
        XCTAssertEqual(found[0].state, .stopped)
        XCTAssertEqual(found[0].uuid, "dd96909c:ae315ffe:3a59f52c:051376ba")
        XCTAssertTrue(found[0].isStorage)
        XCTAssertEqual(found[0].address, "/dev/md/gryonixnexus")
    }

    func testASecondArrayTakesTheNextFreeNameAndMount() throws {
        let empty = try XCTUnwrap(ServerHardware.parse(try fixture("probe-output.txt")))
        let first = RaidPlan.storage(level: .raid1, disks: [], in: empty)
        XCTAssertEqual(first.name, "gryonixnexus")
        XCTAssertEqual(first.mountPoint, "/srv/gryonixnexus-storage")
        let taken = try XCTUnwrap(ServerHardware.parse(try fixture("probe-raid-stopped.txt")))
        let second = RaidPlan.storage(level: .raid1, disks: [], in: taken)
        XCTAssertEqual(second.name, "gryonixnexus2")
        XCTAssertEqual(second.mountPoint, "/srv/gryonixnexus-storage2")
        XCTAssertEqual(second.device, "/dev/md/gryonixnexus2")
    }

    func testAFailedMemberMakesTheArrayDegradedAndIsNotASecondArray() throws {
        let found = try arrays("probe-raid-degraded.txt")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].state, .degraded)
        XCTAssertEqual(found[0].failed, ["/dev/vdd"])
        XCTAssertEqual(found[0].members, ["/dev/vdb"])
        XCTAssertEqual(found[0].device, "/dev/md127")
        XCTAssertTrue(found[0].needsAttention)
    }

    func testARebuildShowsItsProgress() throws {
        let found = try arrays("probe-raid-rebuilding.txt")
        XCTAssertEqual(found.count, 1)
        guard case .rebuilding(let percent) = found[0].state else {
            return XCTFail("expected rebuilding, got \(found[0].state)")
        }
        XCTAssertGreaterThanOrEqual(percent, 0)
        XCTAssertLessThanOrEqual(percent, 100)
    }

    func testRecoveryScriptsMatchTheGolden() throws {
        let stopped = try arrays("probe-raid-stopped.txt")[0]
        try assertGolden(RaidImportPlan(array: stopped).script(), "raid-import.sh")
        let degraded = try arrays("probe-raid-degraded.txt")[0]
        let degradedHardware = try XCTUnwrap(ServerHardware.parse(try fixture("probe-raid-degraded.txt")))
        let spare = try XCTUnwrap(RaidRepairPlan.candidates(in: degradedHardware, for: degraded).first)
        try assertGolden(RaidRepairPlan(array: degraded, replacement: spare).script(), "raid-repair.sh")
        let ssds = try hardware()
        let pair = [ssds.disks[1], ssds.disks[4]]
        try assertGolden(RaidPlan.cacheMirror(pair).script(), "cache-mirror.sh")
        try assertGolden(FastStoragePlan(target: .device(RaidPlan.cacheMirror(pair).device),
                                         hotPaths: ["/opt/immich/postgres"]).script(), "fast-mirror.sh")
    }

    func testATrueNASPoolLeftOnTheDisksIsFoundAndItsDisksAreNotOffered() throws {
        let hardware = try XCTUnwrap(ServerHardware.parse(try fixture("probe-zfs-truenas.txt")))
        let found = StorageArray.all(in: hardware)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].kind, .zfs)
        XCTAssertEqual(found[0].name, "tank")
        XCTAssertEqual(found[0].state, .stopped)
        XCTAssertEqual(found[0].members, ["/dev/sda2", "/dev/sdb2"])
        XCTAssertTrue(found[0].repairsHere)
        XCTAssertEqual(RaidPlan.candidates(in: hardware).map(\.path), [])
        try assertGolden(RaidImportPlan(array: found[0]).script(), "zfs-import.sh")
    }

    func testEveryPopularKindOfArrayIsFound() throws {
        let hardware = try XCTUnwrap(ServerHardware.parse(try fixture("probe-many-arrays.txt")))
        let found = Dictionary(grouping: StorageArray.all(in: hardware), by: \.kind)
        XCTAssertEqual(found[.md]?.count, 1, "md on partitions is one array, not a second stopped one")
        XCTAssertEqual(found[.md]?.first?.state, .clean)
        XCTAssertEqual(found[.md]?.first?.mountpoint, "/srv/md")

        let pool = try XCTUnwrap(found[.zfs]?.first)
        XCTAssertEqual(found[.zfs]?.count, 1)
        XCTAssertEqual(pool.level, "raidz1")
        XCTAssertEqual(pool.state, .degraded)
        XCTAssertEqual(pool.members, ["/dev/sda2", "/dev/sdb2"])
        XCTAssertEqual(pool.failed, ["9147389209417539263"])
        XCTAssertEqual(pool.mountpoint, "/mnt/tank")

        let btrfs = try XCTUnwrap(found[.btrfs]?.first)
        XCTAssertEqual(btrfs.name, "data")
        XCTAssertEqual(btrfs.level, "raid1")
        XCTAssertEqual(btrfs.state, .clean)
        XCTAssertEqual(btrfs.mountpoint, "/srv/data")

        let lvm = try XCTUnwrap(found[.lvm]?.first)
        XCTAssertEqual(lvm.name, "vg0-data")
        XCTAssertEqual(lvm.level, "raid1")
        XCTAssertEqual(lvm.members, ["/dev/sde", "/dev/sdf"])
        XCTAssertEqual(lvm.mountpoint, "/srv/lvm")

        XCTAssertEqual(found[.hardware]?.map(\.name), ["PERC H730 Mini"])
        XCTAssertEqual(found[.hardware]?.first?.state, .unknown)

        XCTAssertEqual(pool.spares, ["/dev/sdj"])
        let offered = RaidPlan.candidates(in: hardware).map(\.path)
        XCTAssertEqual(offered, ["/dev/sdi"], "a pool's spare is never offered for wiping")
        let spare = try XCTUnwrap(hardware.disks.first { $0.path == "/dev/sdj" })
        try assertGolden(RaidRepairPlan(array: pool, replacement: spare).script(), "zfs-replace.sh")
    }

    func testAZfsResilverAndScrubShowTheirProgressApart() {
        let resilver = """
          pool: tank
         state: DEGRADED
          scan: resilver in progress since Thu Sep 25 10:00:00 2026
                1.20T scanned at 400M/s, 600G issued at 200M/s, 2.40T total
                300G resilvered, 24.93% done, 02:30:00 to go
        config:
                NAME STATE READ WRITE CKSUM
                tank DEGRADED 0 0 0
                  mirror-0 DEGRADED 0 0 0
                    /dev/sda2 ONLINE 0 0 0
                    replacing-1 DEGRADED 0 0 0
                      /dev/sdb2 OFFLINE 0 0 0
                      /dev/sdc1 ONLINE 0 0 0
        errors: No known data errors
        """
        let pools = ZpoolReader.pools(resilver)
        XCTAssertEqual(pools.first?.state, .rebuilding(percent: 24.93))
        XCTAssertEqual(pools.first?.level, "mirror")
        let scrub = resilver.replacingOccurrences(of: "resilver in progress", with: "scrub in progress")
            .replacingOccurrences(of: "DEGRADED", with: "ONLINE")
        XCTAssertEqual(ZpoolReader.pools(scrub).first?.state, .checking(percent: 24.93))
        let degradedScrub = resilver.replacingOccurrences(of: "resilver in progress", with: "scrub in progress")
        XCTAssertEqual(ZpoolReader.pools(degradedScrub).first?.state, .degraded)
    }

    func testAnUnreadableLvmReportLeavesTheHealthUnknown() throws {
        let text = try fixture("probe-many-arrays.txt").replacingOccurrences(
            of: "lvm=vg0;data;raid1;;100.00|", with: "lvm=")
        let hardware = try XCTUnwrap(ServerHardware.parse(text))
        let lvm = StorageArray.all(in: hardware).first { $0.kind == .lvm }
        XCTAssertEqual(lvm?.state, .unknown)
        XCTAssertFalse(lvm?.needsAttention ?? true)
    }

    func testARunningServersHotDirectoriesAreReadFromItsComposeFiles() throws {
        let probe = """
        ### /opt/immich/docker-compose.yml
        services:
          database:
            volumes:
              - /opt/immich/postgres:/var/lib/postgresql/data
              - /opt/immich/upload:/usr/src/app/upload
        ### /opt/homeassistant/docker-compose.yml
        services:
          homeassistant:
            volumes:
              - /opt/homeassistant/config:/config
        ### /opt/nextcloud/docker-compose.yml
        services:
          db:
            volumes:
              - /opt/nextcloud/db:/var/lib/mysql
          redis:
            volumes:
              - /opt/nextcloud/redis:/data
        GRYONIXNEXUS_FAST_MOUNTED
        """
        let projects = FastStorageMove.projects(inProbe: probe)
        XCTAssertEqual(projects, [
            .init(directory: "/opt/immich", hotPaths: ["/opt/immich/postgres"]),
            .init(directory: "/opt/nextcloud", hotPaths: ["/opt/nextcloud/db", "/opt/nextcloud/redis"]),
        ])
        XCTAssertTrue(FastStorageMove.isMounted(inProbe: probe))
        let move = FastStorageMove(target: .folder(on: "/mnt/fast"), projects: projects)
        try assertGolden(move.script(), "fast-move.sh")
        try assertGolden(FastStorageRestore.script(projects: projects), "fast-restore.sh")
        try assertGolden(FastStorageRestore.cleanupScript(paths: ["/opt/immich/postgres"]), "fast-cleanup.sh")
        let bound = FastStorageMove.bound(inProbe: "x\nGRYONIXNEXUS_FAST_BOUND /opt/immich/postgres\n")
        XCTAssertEqual(bound, ["/opt/immich/postgres"])
    }

    func testSmartReportsEachDiskFromRealOutput() throws {
        let health = DiskHealth.parse(try fixture("smart-output.txt"))
        XCTAssertEqual(health.map(\.path), ["/dev/sda", "/dev/sdb", "/dev/sdc", "/dev/sdd"])
        XCTAssertEqual(health[0].verdict, .good, "the NVMe on orion")
        XCTAssertEqual(health[0].temperature, 54)
        XCTAssertEqual(health[0].powerOnHours, 3550)
        XCTAssertEqual(health[0].wornPercent, 0)
        XCTAssertEqual(health[1].verdict, .watch)
        XCTAssertEqual(health[1].badSectors, 10)
        XCTAssertEqual(health[1].powerOnHours, 41234)
        XCTAssertEqual(health[2].verdict, .failing)
        XCTAssertEqual(health[3].verdict, .unknown, "a USB bridge that hides SMART")
        try assertGolden(DiskHealth.script(paths: ["/dev/sda", "/dev/sdb"]), "smart.sh")
    }

    func testSpeedScriptsMatchTheGoldenAndParseRealOutput() throws {
        try assertGolden(SpeedTest.diskScript(directory: SpeedTest.systemDirectory), "speed-disk.sh")
        try assertGolden(SpeedTest.internetScript, "speed-internet.sh")
        let disk = try XCTUnwrap(SpeedTest.parseDisk(try fixture("speed-disk-output.txt")))
        XCTAssertEqual(disk.writeBytesPerSecond, 268_435_456 / 0.438679, accuracy: 1)
        XCTAssertFalse(disk.cached)
        let net = try XCTUnwrap(SpeedTest.parseInternet(try fixture("speed-internet-output.txt")))
        XCTAssertEqual(net.downloadBitsPerSecond, 208_073_241 * 8, accuracy: 1)
        XCTAssertNil(SpeedTest.parseInternet("nocurl\n"))
        XCTAssertNil(SpeedTest.parseInternet("down 22 403\nup 0 000\n"))
    }

    /// An old TrueNAS boot disk can be formatted for reuse
    func testAnEarlierTrueNASBootDiskIsFreeToFormat() throws {
        let hardware = try XCTUnwrap(ServerHardware.parse(try fixture("probe-truenas-boot-pool.txt")))
        let pool = try XCTUnwrap(StorageArray.all(in: hardware).first { $0.name == "boot-pool" })
        XCTAssertTrue(pool.isForeignSystemPool)
        XCTAssertEqual(DiskFormatPlan.candidates(in: hardware).map(\.path), ["/dev/sdb"])
    }

    /// Swap made on the server, and memory it covers
    func testSwapScriptMatchesTheGoldenAndCoversMissingMemory() throws {
        try assertGolden(SwapPlan(sizeGB: 2).script(), "swap-2g.sh")
        let gib: Int64 = 1_073_741_824
        XCTAssertEqual(SwapPlan.suggested(memoryBytes: gib, needBytes: 3 * gib), 2)
        XCTAssertEqual(SwapPlan.suggested(memoryBytes: gib, needBytes: 30 * gib), 8)
        var hardware = ServerHardware(cpuCores: 1, memoryBytes: 900 * 1_048_576, architecture: "x86_64",
                                      rootFreeBytes: 9 * gib, disks: [])
        let need = ServerRequirements(memoryMB: 2048, diskGB: 2, installsDocker: false)
        XCTAssertEqual(HardwareVerdict.judge(hardware, against: need).level, .doesNotFit)
        hardware.swapBytes = 2 * gib
        let verdict = HardwareVerdict.judge(hardware, against: need)
        XCTAssertEqual(verdict.level, .tight, "swap covers the missing memory")
        XCTAssertEqual(verdict.findings.first?.swapBytes, 2 * gib)
        XCTAssertEqual(HardwareVerdict.judge(hardware, against: ServiceRegistry.relayRequirements).level, .fits)
    }

    func testTheProbeReadsSwap() throws {
        let output = "\(ServerHardware.beginMarker)\ncpu=1\nmem=918000000\nswap=2147479552\n\(ServerHardware.endMarker)\n"
        XCTAssertEqual(ServerHardware.parse(output)?.swapBytes, 2_147_479_552)
    }
}
