import XCTest
@testable import ServerControl

final class HostMetricsTests: XCTestCase {
    // MARK: - Fixtures

    /// A realistic probe output for a small Debian VPS
    private func probeOutput(cpuUser: Int = 1000, cpuIdle: Int = 8000, cpuIOWait: Int = 200,
                             netRx: Int = 1_000_000, netTx: Int = 500_000,
                             sectorsRead: Int = 2000, sectorsWritten: Int = 4000,
                             uptime: Double = 7_776_000) -> String {
        """
        @@STAT@@
        cpu  \(cpuUser) 50 300 \(cpuIdle) \(cpuIOWait) 0 25 10 0 0
        cpu0 500 25 150 4000 100 0 12 5 0 0
        cpu1 500 25 150 4000 100 0 13 5 0 0
        intr 12345
        @@MEM@@
        MemTotal:         430080 kB
        MemFree:           51200 kB
        MemAvailable:     174080 kB
        Buffers:           20480 kB
        Cached:            81920 kB
        SwapTotal:        102400 kB
        SwapFree:          92160 kB
        @@UPTIME@@
        \(String(format: "%.2f", uptime + 0.35)) 15130655.92
        @@LOAD@@
        0.42 0.31 0.25 1/123 4567
        @@NET@@
        Inter-|   Receive                                                |  Transmit
         face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
            lo: 999999    9999    0    0    0     0          0         0  999999    9999    0    0    0     0       0          0
          eth0: \(netRx)   66666    0    0    0     0          0         0 \(netTx)   55555    0    0    0     0       0          0
        @@DISKSTATS@@
           8       0 sda 5000 100 \(sectorsRead) 3000 7000 200 \(sectorsWritten) 9000 0 5000 12000 0 0 0 0
           8       1 sda1 4900 90 999999 2900 6900 190 999999 8900 0 4900 11800 0 0 0 0
         254       0 dm-0 100 0 500 50 100 0 500 60 0 100 110 0 0 0 0
        @@DF@@
        Mounted on     1B-blocks       Used Use%
        /            45000000000 5364000000  12%
        /boot         512000000   52000000   11%
        @@OS@@
        PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
        NAME="Debian GNU/Linux"
        ID=debian
        @@NPROC@@
        2
        @@TEMP@@
        42500
        38000
        """
    }

    // MARK: - Parser

    func testParsesFullProbeOutput() throws {
        let sample = try HostMetricsParser.parse(probeOutput())

        // cpu line: 1000+50+300+8000+200+0+25+10 = 9585; idle 8000+200 = 8200.
        XCTAssertEqual(sample.cpuTotalTicks, 9585)
        XCTAssertEqual(sample.cpuIdleTicks, 8200)
        XCTAssertEqual(sample.cpuCores, 2)

        XCTAssertEqual(sample.memTotalBytes, 430_080 * 1024)
        XCTAssertEqual(sample.memUsedBytes, (430_080 - 174_080) * 1024)
        XCTAssertEqual(sample.swapTotalBytes, 102_400 * 1024)
        XCTAssertEqual(sample.swapUsedBytes, 10_240 * 1024)

        XCTAssertEqual(sample.uptimeSeconds, 7_776_000.35, accuracy: 0.01)
        XCTAssertEqual(sample.load1, 0.42, accuracy: 0.001)
        XCTAssertEqual(sample.load15, 0.25, accuracy: 0.001)

        // lo is excluded.
        XCTAssertEqual(sample.netReceivedBytes, 1_000_000)
        XCTAssertEqual(sample.netSentBytes, 500_000)

        // Only sda counts: partitions (sda1) and dm-0 are excluded.
        XCTAssertEqual(sample.diskReadBytes, 2000 * 512)
        XCTAssertEqual(sample.diskWrittenBytes, 4000 * 512)

        XCTAssertEqual(sample.mounts.count, 2)
        XCTAssertEqual(sample.osID, "debian")
        XCTAssertEqual(sample.osPrettyName, "Debian GNU/Linux 12 (bookworm)")
        XCTAssertEqual(sample.temperatureCelsius ?? 0, 42.5, accuracy: 0.01)
    }

    func testParsesNVMeAndVirtioDisks() throws {
        let output = probeOutput().replacingOccurrences(
            of: "   8       0 sda 5000 100 2000 3000 7000 200 4000 9000 0 5000 12000 0 0 0 0",
            with: """
               259     0 nvme0n1 5000 100 1000 3000 7000 200 1000 9000 0 5000 12000 0 0 0 0
               259     1 nvme0n1p1 100 0 999 50 100 0 999 60 0 100 110 0 0 0 0
               254     0 vda 100 0 500 50 100 0 500 60 0 100 110 0 0 0 0
            """
        ).replacingOccurrences(
            of: "   8       1 sda1 4900 90 999999 2900 6900 190 999999 8900 0 4900 11800 0 0 0 0\n",
            with: ""
        )
        let sample = try HostMetricsParser.parse(output)
        XCTAssertEqual(sample.diskReadBytes, (1000 + 500) * 512)
        XCTAssertEqual(sample.diskWrittenBytes, (1000 + 500) * 512)
    }

    func testMissingOptionalSectionsStillParse() throws {
        // A stripped host: no os-release, no thermal zones, empty df.
        let output = """
        @@STAT@@
        cpu  100 0 50 800 50 0 0 0 0 0
        cpu0 100 0 50 800 50 0 0 0 0 0
        @@MEM@@
        MemTotal:  1024000 kB
        MemAvailable: 512000 kB
        @@UPTIME@@
        123.45 100.00
        @@LOAD@@
        @@NET@@
        @@DISKSTATS@@
        @@DF@@
        @@OS@@
        @@NPROC@@
        @@TEMP@@
        """
        let sample = try HostMetricsParser.parse(output)
        XCTAssertEqual(sample.cpuCores, 1)
        XCTAssertNil(sample.temperatureCelsius)
        XCTAssertNil(sample.osID)
        XCTAssertTrue(sample.mounts.isEmpty)
        XCTAssertEqual(sample.memUsedBytes, 512_000 * 1024)
    }

    func testMissingCriticalSectionThrows() {
        XCTAssertThrowsError(try HostMetricsParser.parse("@@MEM@@\nMemTotal: 1 kB"))
        XCTAssertThrowsError(try HostMetricsParser.parse(""))
    }

    // MARK: - Snapshot / rates

    func testFirstSnapshotHasNoRates() throws {
        let sample = try HostMetricsParser.parse(probeOutput())
        let snapshot = HostMetricsSnapshot(current: sample, previous: nil)
        XCTAssertNil(snapshot.cpuPercent)
        XCTAssertNil(snapshot.netReceivedPerSecond)
        XCTAssertNil(snapshot.diskWrittenPerSecond)
        // Absolute values are present immediately.
        XCTAssertEqual(snapshot.diskTotalBytes, 45_000_000_000)
        XCTAssertEqual(snapshot.diskUsedBytes, 5_364_000_000)
        XCTAssertEqual(snapshot.netReceivedBytes, 1_000_000)
    }

    func testSecondSnapshotComputesRates() throws {
        let first = try HostMetricsParser.parse(probeOutput())
        let second = try HostMetricsParser.parse(probeOutput(
            cpuUser: 2000, cpuIdle: 8900, cpuIOWait: 300,
            netRx: 3_000_000, netTx: 1_500_000,
            sectorsRead: 4000, sectorsWritten: 6000,
            uptime: 7_776_010
        ))
        let snapshot = HostMetricsSnapshot(current: second, previous: first)

        XCTAssertEqual(snapshot.cpuPercent ?? -1, 50, accuracy: 0.1)
        XCTAssertEqual(snapshot.netReceivedPerSecond ?? -1, 200_000, accuracy: 1)
        XCTAssertEqual(snapshot.netSentPerSecond ?? -1, 100_000, accuracy: 1)
        XCTAssertEqual(snapshot.diskReadPerSecond ?? -1, 2000 * 512 / 10, accuracy: 1)
        XCTAssertEqual(snapshot.diskWrittenPerSecond ?? -1, 2000 * 512 / 10, accuracy: 1)
    }

    func testRebootBetweenSamplesDropsRates() throws {
        let first = try HostMetricsParser.parse(probeOutput(uptime: 7_776_000))
        let second = try HostMetricsParser.parse(probeOutput(uptime: 60))
        let snapshot = HostMetricsSnapshot(current: second, previous: first)
        XCTAssertNil(snapshot.cpuPercent)
        XCTAssertNil(snapshot.netReceivedPerSecond)
    }

    // MARK: - Probe

    func testProbeRunsCatalogCommandAndParses() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("@@STAT@@", stdout: probeOutput())
        let probe = HostMetricsProbe(runner: runner)
        let sample = try await probe.sample(on: .vps)
        XCTAssertEqual(sample.cpuCores, 2)
        XCTAssertEqual(runner.calls, [.init(kind: .run, command: CommandCatalog.hostMetrics, host: .vps)])
    }

    func testProbeSurfacesCommandFailure() async {
        let runner = FakeSSHCommandRunner()
        runner.stub("", stdout: "", exitCode: 127)
        let probe = HostMetricsProbe(runner: runner)
        do {
            _ = try await probe.sample(on: .home)
            XCTFail("expected commandFailed")
        } catch let error as ServerControlError {
            guard case .commandFailed = error else { return XCTFail("wrong error: \(error)") }
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Deployment.tags decoding

    func testDeploymentWithoutTagsFieldStillDecodes() throws {
        let deployment = Deployment(name: "old", topology: .singleHost,
                                    entry: HostEndpoint(host: "203.0.113.4", user: "ops"))
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(deployment)) as! [String: Any]
        json.removeValue(forKey: "tags")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Deployment.self, from: data)
        XCTAssertEqual(decoded.tags, [])
        XCTAssertEqual(decoded.name, "old")
    }

    func testDeploymentTagsRoundTrip() throws {
        let deployment = Deployment(name: "n", topology: .singleHost,
                                    entry: HostEndpoint(host: "h", user: "u"),
                                    tags: ["web", "prod"])
        let decoded = try JSONDecoder().decode(Deployment.self,
                                               from: JSONEncoder().encode(deployment))
        XCTAssertEqual(decoded.tags, ["web", "prod"])
    }
}
