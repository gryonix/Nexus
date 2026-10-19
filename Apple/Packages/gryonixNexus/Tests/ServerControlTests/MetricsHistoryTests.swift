import XCTest
@testable import ServerControl

final class MetricsHistoryTests: XCTestCase {
    // MARK: - Command literals

    func testCommandReadsThePinnedCollectorPath() {
        XCTAssertEqual(CommandCatalog.metricsHistory(bucket: .tenSeconds),
                       "cat /var/lib/gryonixnexus/metrics/10s.csv 2>/dev/null; echo @@POWER@@; cat /var/lib/gryonixnexus/metrics/power-10s.csv 2>/dev/null; true")
        XCTAssertEqual(CommandCatalog.metricsHistory(bucket: .oneWeek),
                       "cat /var/lib/gryonixnexus/metrics/1w.csv 2>/dev/null; echo @@POWER@@; cat /var/lib/gryonixnexus/metrics/power-1w.csv 2>/dev/null; true")
    }

    func testBucketNamesMatchTheCollector() {
        XCTAssertEqual(MetricsHistoryBucket.allCases.map(\.rawValue),
                       ["10s", "1m", "10m", "1h", "1d", "1w"])
    }

    // MARK: - Parser

    func testParsesFullAndSparseRows() {
        let output = """
        1758000000,12.5,1073741824,2147483648,32000000000,110000000000,1024,2048,100,200,0.42,55.0
        1758000010,,1073741824,2147483648,32000000000,110000000000,,,,,0.42,
        """
        let points = MetricsHistoryParser.parse(output)
        XCTAssertEqual(points.count, 2)

        let full = points[0]
        XCTAssertEqual(full.date, Date(timeIntervalSince1970: 1_758_000_000))
        XCTAssertEqual(full.cpuPercent, 12.5)
        XCTAssertEqual(full.memUsedBytes, 1_073_741_824)
        XCTAssertEqual(full.memUsedFraction, 0.5)
        XCTAssertEqual(full.diskTotalBytes, 110_000_000_000)
        XCTAssertEqual(full.netReceivedPerSecond, 1024)
        XCTAssertEqual(full.netSentPerSecond, 2048)
        XCTAssertEqual(full.diskReadPerSecond, 100)
        XCTAssertEqual(full.diskWrittenPerSecond, 200)
        XCTAssertEqual(full.load1, 0.42)
        XCTAssertEqual(full.temperatureCelsius, 55.0)

        // First-sample row: no rates, no cpu, no temperature.
        let sparse = points[1]
        XCTAssertNil(sparse.cpuPercent)
        XCTAssertNil(sparse.netReceivedPerSecond)
        XCTAssertNil(sparse.diskWrittenPerSecond)
        XCTAssertNil(sparse.temperatureCelsius)
    }

    func testMalformedAndTruncatedLinesAreSkipped() {
        let output = """
        garbage
        1758000000,1.0,1,2,3,4,5,6,7,8,0.1,
        1758000010,1.0,1,2,3
        1758000020,1.0,1,2,3,4,5,6,7,8,not-a-number,
        """
        let points = MetricsHistoryParser.parse(output)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].date, Date(timeIntervalSince1970: 1_758_000_000))
    }

    func testEmptyOutputMeansNoHistory() {
        XCTAssertEqual(MetricsHistoryParser.parse(""), [])
    }

    func testBucketPointIntervals() {
        XCTAssertEqual(MetricsHistoryBucket.tenSeconds.pointInterval, 10)
        XCTAssertEqual(MetricsHistoryBucket.oneDay.pointInterval, 86_400)
        XCTAssertEqual(MetricsHistoryBucket.oneWeek.pointInterval, 604_800)
    }

    // MARK: - Probe

    func testProbeParsesRunnerOutput() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub(CommandCatalog.metricsHistory(bucket: .oneMinute),
                    stdout: "1758000000,50.0,1,2,3,4,5,6,7,8,1.00,\n")
        let probe = MetricsHistoryProbe(runner: runner)
        let points = try await probe.history(bucket: .oneMinute, on: .vps)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].cpuPercent, 50.0)
    }
}
