import Foundation
import SwiftUI

/// Which periods and which metrics the app OFFERS
@MainActor
final class MetricsPreferences: ObservableObject {
    static let shared = MetricsPreferences()

    private enum Key {
        static let ranges = "metrics.offeredRanges"
        static let metrics = "metrics.offeredMetrics"
    }

    static let defaultRanges: [HistoryRange] =
        [.tenMinutes, .hour, .threeHours, .tenHours, .day, .week, .month, .year]

    /// Every metric the collector records
    static let defaultMetrics: [HistoryMetric] = HistoryMetric.allCases

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        offeredRanges = Self.load(from: defaults, key: Key.ranges,
                                  all: HistoryRange.allCases, fallback: Self.defaultRanges)
        offeredMetrics = Self.load(from: defaults, key: Key.metrics,
                                   all: HistoryMetric.allCases, fallback: Self.defaultMetrics)
    }

    @Published var offeredRanges: [HistoryRange] {
        didSet { save(offeredRanges.map(\.rawValue), key: Key.ranges) }
    }

    @Published var offeredMetrics: [HistoryMetric] {
        didSet { save(offeredMetrics.map(\.rawValue), key: Key.metrics) }
    }

    func setRange(_ range: HistoryRange, offered: Bool) {
        var next = Set(offeredRanges)
        if offered { next.insert(range) } else if next.count > 1 { next.remove(range) }
        offeredRanges = HistoryRange.allCases.filter { next.contains($0) }
    }

    func setMetric(_ metric: HistoryMetric, offered: Bool) {
        var next = Set(offeredMetrics)
        if offered { next.insert(metric) } else if next.count > 1 { next.remove(metric) }
        offeredMetrics = HistoryMetric.allCases.filter { next.contains($0) }
    }

    func resolved(_ range: HistoryRange) -> HistoryRange {
        offeredRanges.contains(range) ? range : (offeredRanges.first ?? .hour)
    }

    private func save(_ values: [String], key: String) {
        defaults.set(values, forKey: key)
    }

    private static func load<T: RawRepresentable & CaseIterable>(
        from defaults: UserDefaults, key: String, all: [T], fallback: [T]
    ) -> [T] where T.RawValue == String, T: Equatable {
        guard let raw = defaults.array(forKey: key) as? [String] else { return fallback }
        let chosen = Set(raw)
        let kept = all.filter { chosen.contains($0.rawValue) }
        return kept.isEmpty ? fallback : kept
    }
}
