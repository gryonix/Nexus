import ServiceCatalog
import XCTest
@testable import VPNTunnel

final class FleetSnapshotMetricsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func store() -> FleetSnapshotStore {
        FleetSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
    }

    private func reading(cpu: Double? = 40, memUsed: Int64 = 4, memTotal: Int64 = 8,
                         diskUsed: Int64 = 1, diskTotal: Int64 = 4,
                         label: String = "VPS",
                         takenAt: Date = Date()) -> FleetSnapshot.Reading {
        .init(cpuPercent: cpu, memUsedBytes: memUsed, memTotalBytes: memTotal,
              diskUsedBytes: diskUsed, diskTotalBytes: diskTotal,
              machineLabel: label, takenAt: takenAt)
    }

    // MARK: - The two writers must not erase each other

    func testWritingLoadKeepsTheDevicesAlreadyThere() {
        let store = store()
        let id = UUID()
        store.upsertServer(id: id, name: "Home",
                           protocols: [.init(protocolID: .wireguardVPN, deviceCount: 3,
                                             deviceNames: ["iPhone", "Mac", "iPad"])],
                           failure: nil)
        store.upsertMetrics(id: id, name: "Home", reading: reading())

        let server = store.read()?.servers.first
        XCTAssertEqual(server?.protocols.first?.deviceCount, 3,
                       "writing a load reading wiped the devices")
        XCTAssertEqual(server?.metrics?.cpuPercent, 40)
    }

    func testWritingDevicesKeepsTheLoadAlreadyThere() {
        let store = store()
        let id = UUID()
        store.upsertMetrics(id: id, name: "Home", reading: reading(cpu: 61))
        store.upsertServer(id: id, name: "Home",
                           protocols: [.init(protocolID: .wireguardVPN, deviceCount: 1,
                                             deviceNames: ["iPhone"])],
                           failure: nil)

        let server = store.read()?.servers.first
        XCTAssertEqual(server?.metrics?.cpuPercent, 61,
                       "writing devices wiped the load reading")
        XCTAssertEqual(server?.protocols.first?.deviceCount, 1)
    }

    func testALoadReadingForAnUnknownServerCreatesIt() {
        let store = store()
        store.upsertMetrics(id: UUID(), name: "Fresh", reading: reading())
        XCTAssertEqual(store.read()?.servers.count, 1)
        XCTAssertEqual(store.read()?.servers.first?.name, "Fresh")
    }

    func testASecondReadingReplacesTheFirstRatherThanAccumulating() {
        let store = store()
        let id = UUID()
        store.upsertMetrics(id: id, name: "Home", reading: reading(cpu: 10))
        store.upsertMetrics(id: id, name: "Home", reading: reading(cpu: 90))
        XCTAssertEqual(store.read()?.servers.count, 1)
        XCTAssertEqual(store.read()?.servers.first?.metrics?.cpuPercent, 90)
    }

    // MARK: - The percentages

    func testThePercentagesAreComputedFromTheTwoCounts() {
        let r = reading(memUsed: 3, memTotal: 4, diskUsed: 1, diskTotal: 8)
        XCTAssertEqual(r.memoryPercent ?? 0, 75, accuracy: 0.001)
        XCTAssertEqual(r.diskPercent ?? 0, 12.5, accuracy: 0.001)
    }

    func testAZeroTotalIsNoAnswerRatherThanZeroPercent() {
        let r = reading(memUsed: 0, memTotal: 0, diskUsed: 0, diskTotal: 0)
        XCTAssertNil(r.memoryPercent)
        XCTAssertNil(r.diskPercent)
    }

    func testTheReadingKnowsHowOldItIs() {
        let r = reading(takenAt: Date().addingTimeInterval(-120))
        XCTAssertEqual(r.age, 120, accuracy: 5)
    }

    func testTheReadingSurvivesTheFile() {
        let store = store()
        let id = UUID()
        let taken = Date().addingTimeInterval(-3_600)
        store.upsertMetrics(id: id, name: "Home",
                            reading: reading(cpu: nil, label: "Local", takenAt: taken))
        let back = store.read()?.servers.first?.metrics
        XCTAssertNil(back?.cpuPercent, "an unmeasured CPU came back as a number")
        XCTAssertEqual(back?.machineLabel, "Local")
        XCTAssertEqual(back?.takenAt.timeIntervalSince1970 ?? 0,
                       taken.timeIntervalSince1970, accuracy: 1)
    }
}
