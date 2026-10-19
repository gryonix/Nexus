import Foundation

/// Idle and full-load watts for hosts without a sensor
public struct EnergyProfile: Codable, Sendable, Hashable {
    public var idleWatts: Double
    public var peakWatts: Double

    public init(idleWatts: Double, peakWatts: Double) {
        self.idleWatts = idleWatts
        self.peakWatts = peakWatts
    }

    /// A starting guess from the core count
    public static func guess(cores: Int) -> EnergyProfile {
        let cores = Double(max(cores, 1))
        let idle = 8 + cores
        return EnergyProfile(idleWatts: idle, peakWatts: min(idle + 6 * cores, 400))
    }

    public func watts(cpuPercent: Double) -> Double {
        let load = min(max(cpuPercent, 0), 100) / 100
        return idleWatts + (peakWatts - idleWatts) * load
    }
}

/// Watts, energy and money from history points
public enum EnergyMath {
    public static let estimateSource = "estimate"

    /// Suffix of a partial reading completed from the estimate
    public static let completedSuffix = "+estimate"

    /// Estimates missing points, completes partial sensor readings
    public static func filled(_ points: [MetricsHistoryPoint], profile: EnergyProfile,
                              estimate: PowerEstimate? = nil) -> [MetricsHistoryPoint] {
        points.map { point in
            var filled = point
            if let watts = point.powerWatts {
                guard let estimate, let source = point.powerSource,
                      PowerEstimate.covered(by: source) != nil else { return point }
                filled.powerWatts = watts + estimate.unseenWatts(source: source, measured: watts,
                                                                 cpuPercent: point.cpuPercent)
                filled.powerSource = source + completedSuffix
            } else if let cpu = point.cpuPercent {
                filled.powerWatts = profile.watts(cpuPercent: cpu)
                filled.powerSource = estimateSource
            }
            return filled
        }
    }

    /// Kilowatt-hours of points each standing for `interval` seconds
    public static func kilowattHours(_ points: [MetricsHistoryPoint], interval: TimeInterval,
                                     from start: Date, to end: Date) -> Double {
        points
            .filter { $0.date >= start && $0.date < end }
            .compactMap(\.powerWatts)
            .reduce(0) { $0 + $1 * interval / 3_600 } / 1_000
    }

    /// Whether any point came from a real sensor
    public static func isMeasured(_ points: [MetricsHistoryPoint]) -> Bool {
        points.contains { $0.powerWatts != nil && $0.powerSource != estimateSource }
    }

    /// Mean watts of the points that carry a reading
    public static func averageWatts(_ points: [MetricsHistoryPoint]) -> Double? {
        let watts = points.compactMap(\.powerWatts)
        return watts.isEmpty ? nil : watts.reduce(0, +) / Double(watts.count)
    }

    /// Hours of a range covered by points of `interval` seconds
    public static func coveredHours(_ points: [MetricsHistoryPoint], interval: TimeInterval,
                                    from start: Date, to end: Date) -> Double {
        Double(points.filter { $0.date >= start && $0.date < end && $0.powerWatts != nil }.count)
            * interval / 3_600
    }

    /// Known energy plus the average rate for the other hours
    public static func monthForecast(daily: [MetricsHistoryPoint], hourly: [MetricsHistoryPoint],
                                     now: Date, calendar: Calendar) -> Double {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return 0 }
        let today = calendar.startOfDay(for: now)
        let known = kilowattHours(daily, interval: 86_400, from: month.start, to: today)
            + kilowattHours(hourly, interval: 3_600, from: today, to: .distantFuture)
        let knownHours = coveredHours(daily, interval: 86_400, from: month.start, to: today)
            + coveredHours(hourly, interval: 3_600, from: today, to: .distantFuture)
        guard let average = averageWatts(hourly) ?? averageWatts(daily) else { return known }
        return known + average * max(month.duration / 3_600 - knownHours, 0) / 1_000
    }
}
