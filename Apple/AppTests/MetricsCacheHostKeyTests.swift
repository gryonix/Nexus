import ServerControl
import XCTest

@testable import gryonixNexus

final class MetricsCacheHostKeyTests: XCTestCase {
    private var cache: MetricsCache!
    private var directory: URL!
    private let deployment = UUID()

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetricsCacheHostKeyTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cache = MetricsCache(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func point(cpu: Double) -> MetricsHistoryPoint {
        MetricsHistoryPoint(date: Date(timeIntervalSince1970: 1_758_000_000),
                            cpuPercent: cpu,
                            memUsedBytes: 1, memTotalBytes: 2,
                            diskUsedBytes: 3, diskTotalBytes: 4,
                            netReceivedPerSecond: nil, netSentPerSecond: nil,
                            diskReadPerSecond: nil, diskWrittenPerSecond: nil,
                            load1: 0.1, temperatureCelsius: nil)
    }

    private func store(_ cpu: Double, on host: SSHHostID) {
        cache.store([point(cpu: cpu)],
                    for: MetricPanel.Source(deploymentID: deployment,
                                            host: host,
                                            bucket: .tenSeconds))
    }

    func testTheShippedPairKeepsTheKeysItAlwaysHad() {
        XCTAssertEqual(SSHHostID.vps.persistedRaw, "vps")
        XCTAssertEqual(SSHHostID.home.persistedRaw, "home")

        store(11, on: .vps)
        store(22, on: .home)
        XCTAssertEqual(cache.latestPoint(deploymentID: deployment, host: .vps)?.cpuPercent, 11)
        XCTAssertEqual(cache.latestPoint(deploymentID: deployment, host: .home)?.cpuPercent, 22)
    }

    func testAThirdMachineDoesNotReadTheEntryMachinesReadings() {
        let third = SSHHostID.node(UUID())
        store(11, on: .vps)

        XCTAssertNil(cache.latestPoint(deploymentID: deployment, host: third),
                     "a machine with nothing cached must say so, not hand back another machine's numbers")
    }

    func testAThirdMachinesReadingsDoNotOverwriteTheEntryMachines() {
        let third = SSHHostID.node(UUID())
        store(11, on: .vps)
        store(99, on: third)

        XCTAssertEqual(cache.latestPoint(deploymentID: deployment, host: .vps)?.cpuPercent, 11,
                       "the entry machine's cached reading was overwritten by another machine's")
        XCTAssertEqual(cache.latestPoint(deploymentID: deployment, host: third)?.cpuPercent, 99)
    }

    func testTwoSlotlessMachinesGetTheirOwnRows() {
        let first = SSHHostID.node(UUID())
        let second = SSHHostID.node(UUID())
        store(30, on: first)
        store(70, on: second)

        XCTAssertEqual(cache.latestPoint(deploymentID: deployment, host: first)?.cpuPercent, 30)
        XCTAssertEqual(cache.latestPoint(deploymentID: deployment, host: second)?.cpuPercent, 70)
    }
}
