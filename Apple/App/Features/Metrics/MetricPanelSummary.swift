import Foundation
import ServerControl

enum MetricPanelSummary {
    static func text(metrics: [HistoryMetric], range: HistoryRange,
                     points: [MetricsHistoryPoint]) -> String {
        guard metrics.count > 1 else {
            return text(metric: metrics.first ?? .cpu, range: range, points: points)
        }
        return metrics.map { metric in
            "\(UIL10n.string(metricName(metric))) \(text(metric: metric, range: range, points: points))"
        }.joined(separator: "  ·  ")
    }

    /// The metric's name as a plain key
    private static func metricName(_ metric: HistoryMetric) -> String {
        switch metric {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .network: return "Network"
        case .diskIO: return "Disk I/O"
        case .load: return "Load"
        case .temperature: return "Temperature"
        case .power: return "Power"
        }
    }

    static func text(metric: HistoryMetric, range: HistoryRange,
                     points: [MetricsHistoryPoint]) -> String {
        let windowed = points.windowed(to: range)
        guard !windowed.isEmpty else { return "—" }
        switch metric {
        case .network:
            return pair(UIL10n.string("Received"), total(windowed, range, \.netReceivedPerSecond),
                        UIL10n.string("Sent"), total(windowed, range, \.netSentPerSecond))
        case .diskIO:
            return pair(UIL10n.string("Read"), total(windowed, range, \.diskReadPerSecond),
                        UIL10n.string("Write"), total(windowed, range, \.diskWrittenPerSecond))
        case .cpu:
            return percentLine(windowed.compactMap(\.cpuPercent))
        case .memory:
            return percentLine(windowed.map { $0.memUsedFraction * 100 })
        case .disk:
            return percentLine(windowed.map { $0.diskUsedFraction * 100 })
        case .load:
            return plainLine(windowed.compactMap(\.load1)) { String(format: "%.2f", $0) }
        case .temperature:
            return plainLine(windowed.compactMap(\.temperatureCelsius)) {
                MetricsFormat.temperature($0)
            }
        case .power:
            return plainLine(windowed.compactMap(\.powerWatts)) { EnergyFormat.watts($0) }
        }
    }

    private static func total(_ points: [MetricsHistoryPoint], _ range: HistoryRange,
                              _ value: (MetricsHistoryPoint) -> Double?) -> Int64 {
        let interval = range.bucket.pointInterval
        return Int64(points.reduce(0.0) { $0 + (value($1) ?? 0) * interval })
    }

    private static func pair(_ firstName: String, _ first: Int64,
                             _ secondName: String, _ second: Int64) -> String {
        "\(firstName) \(MetricsFormat.bytes(first)) · \(secondName) \(MetricsFormat.bytes(second))"
    }

    private static func percentLine(_ values: [Double]) -> String {
        plainLine(values) { String(format: "%.0f %%", $0) }
    }

    /// "avg 12 % · peak 61 %"
    private static func plainLine(_ values: [Double],
                                  format: (Double) -> String) -> String {
        guard !values.isEmpty else { return "—" }
        let average = values.reduce(0, +) / Double(values.count)
        let peak = values.max() ?? average
        return "\(UIL10n.string("avg")) \(format(average)) · \(UIL10n.string("peak")) \(format(peak))"
    }
}
