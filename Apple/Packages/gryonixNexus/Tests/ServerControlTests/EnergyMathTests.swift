import Foundation
@testable import ServerControl
import XCTest

final class EnergyMathTests: XCTestCase {
    private func point(_ seconds: Double, cpu: Double?, watts: Double? = nil) -> MetricsHistoryPoint {
        MetricsHistoryPoint(date: Date(timeIntervalSince1970: seconds), cpuPercent: cpu,
                            memUsedBytes: 1, memTotalBytes: 2, diskUsedBytes: 1, diskTotalBytes: 2,
                            netReceivedPerSecond: nil, netSentPerSecond: nil,
                            diskReadPerSecond: nil, diskWrittenPerSecond: nil,
                            load1: 0, temperatureCelsius: nil, powerWatts: watts)
    }

    func testTheSshOutputCarriesPowerOnTheSameSecond() {
        let output = "100,10,1,2,3,4,,,,,0.1,\n110,20,1,2,3,4,,,,,0.1,\n@@POWER@@\n110,33.5,rapl\njunk\n"
        let points = MetricsHistoryParser.parse(output)
        XCTAssertEqual(points.count, 2)
        XCTAssertNil(points[0].powerWatts)
        XCTAssertEqual(points[1].powerWatts, 33.5)
        XCTAssertEqual(points[1].powerSource, "rapl")
        XCTAssertEqual(MetricsHistoryParser.parse("100,10,1,2,3,4,,,,,0.1,\n").count, 1)
    }

    func testAMeasuredPointIsKeptAndTheRestIsEstimated() {
        let profile = EnergyProfile(idleWatts: 10, peakWatts: 50)
        let filled = EnergyMath.filled([point(0, cpu: 50), point(10, cpu: 90, watts: 80), point(20, cpu: nil)],
                                       profile: profile)
        XCTAssertEqual(filled[0].powerWatts, 30)
        XCTAssertEqual(filled[0].powerSource, EnergyMath.estimateSource)
        XCTAssertEqual(filled[1].powerWatts, 80)
        XCTAssertNil(filled[2].powerWatts)
        XCTAssertTrue(EnergyMath.isMeasured(filled))
        XCTAssertFalse(EnergyMath.isMeasured([filled[0]]))
    }

    func testOneHourAtOneHundredWattsIsATenthOfAKilowattHour() {
        let points = (0..<60).map { point(Double($0) * 60, cpu: nil, watts: 100) }
        let kwh = EnergyMath.kilowattHours(points, interval: 60, from: Date(timeIntervalSince1970: 0),
                                           to: Date(timeIntervalSince1970: 3_600))
        XCTAssertEqual(kwh, 0.1, accuracy: 1e-9)
    }

    func testTheForecastProjectsTheAverageOntoTheWholeMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        let now = midnight.addingTimeInterval(12 * 3_600)
        let hourly = (0..<12).map { point(midnight.timeIntervalSince1970 + Double($0) * 3_600, cpu: nil, watts: 50) }
        let forecast = EnergyMath.monthForecast(daily: [], hourly: hourly, now: now, calendar: calendar)
        XCTAssertEqual(forecast, 0.6 + 50 * (720 - 12) / 1_000, accuracy: 1e-9)
        XCTAssertEqual(EnergyMath.monthForecast(daily: [], hourly: [], now: now, calendar: calendar), 0)
        XCTAssertEqual(EnergyProfile.guess(cores: 4), EnergyProfile(idleWatts: 12, peakWatts: 36))
    }

    func testKnownDaysCountAsTheyWereAndOnlyTheRestIsProjected() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let first = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let now = first.addingTimeInterval(2 * 86_400 + 3_600)
        let daily = [point(first.timeIntervalSince1970, cpu: nil, watts: 100),
                     point(first.timeIntervalSince1970 + 86_400, cpu: nil, watts: 20)]
        let hourly = [point(first.timeIntervalSince1970 + 2 * 86_400, cpu: nil, watts: 40)]
        let forecast = EnergyMath.monthForecast(daily: daily, hourly: hourly, now: now, calendar: calendar)
        XCTAssertEqual(forecast, 2.4 + 0.48 + 0.04 + 40 * (720 - 49) / 1_000, accuracy: 1e-9)
    }
}
