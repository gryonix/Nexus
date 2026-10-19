import Foundation
import ServerControl

/// Which host's energy screen to open
struct EnergyTarget: Hashable {
    let deployment: Deployment
    let host: SSHHostID
    var cores: Int?
}

/// Loads the buckets the energy screen sums
@MainActor
final class EnergyViewModel: ObservableObject {
    let now: MetricsHistoryViewModel
    let hourly: MetricsHistoryViewModel
    let daily: MetricsHistoryViewModel
    let target: EnergyTarget

    init(target: EnergyTarget) {
        self.target = target
        now = MetricsHistoryViewModel(deployment: target.deployment, host: target.host)
        hourly = MetricsHistoryViewModel(deployment: target.deployment, host: target.host)
        daily = MetricsHistoryViewModel(deployment: target.deployment, host: target.host)
        now.range = .tenMinutes
        hourly.range = .twelveDays
        daily.range = .sixMonths
    }

    func load() async {
        async let first: Void = now.load()
        async let second: Void = hourly.load()
        async let third: Void = daily.load()
        _ = await (first, second, third)
        objectWillChange.send()
    }

    func teardown() {
        [now, hourly, daily].forEach { $0.teardown() }
    }

    /// The newest reading, falling back to the hourly series
    var latest: MetricsHistoryPoint? {
        now.points.last { $0.powerWatts != nil } ?? hourly.points.last { $0.powerWatts != nil }
    }

    var isMeasured: Bool { EnergyMath.isMeasured(now.points + hourly.points) }

    private var calendar: Calendar { .current }

    var today: Double {
        EnergyMath.kilowattHours(hourly.points, interval: 3_600,
                                 from: calendar.startOfDay(for: Date()), to: .distantFuture)
    }

    var monthSoFar: Double {
        let start = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        return EnergyMath.kilowattHours(daily.points, interval: 86_400,
                                        from: start, to: calendar.startOfDay(for: Date())) + today
    }

    var monthForecast: Double {
        EnergyMath.monthForecast(daily: daily.points, hourly: hourly.points, now: Date(), calendar: calendar)
    }

    var lastMonth: Double? {
        guard let thisMonth = calendar.dateInterval(of: .month, for: Date()),
              let previous = calendar.dateInterval(of: .month, for: thisMonth.start.addingTimeInterval(-1))
        else { return nil }
        let value = EnergyMath.kilowattHours(daily.points, interval: 86_400,
                                             from: previous.start, to: previous.end)
        return value > 0 ? value : nil
    }

    /// Kilowatt-hours per day for the last 30 days
    var days: [(date: Date, kilowattHours: Double)] {
        let start = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: Date())) ?? Date()
        let today = calendar.startOfDay(for: Date())
        let past = daily.points.filter { $0.date >= start && $0.date < today }.compactMap { point in
            point.powerWatts.map { (date: point.date, kilowattHours: $0 * 24 / 1_000) }
        }
        return past + [(date: today, kilowattHours: self.today)]
    }
}
