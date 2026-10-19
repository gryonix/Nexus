import Foundation

public enum MetricsHistoryParser {
    public static let powerMarker = "@@POWER@@"

    public static func parse(_ output: String) -> [MetricsHistoryPoint] {
        let sections = output.components(separatedBy: powerMarker)
        var points = sections[0].split(separator: "\n").compactMap(parseLine)
        if sections.count > 1 { attachPower(sections[1], to: &points) }
        return points
    }

    /// Joins `epoch,watts,sensor` rows onto the points of the same second
    static func attachPower(_ text: String, to points: inout [MetricsHistoryPoint]) {
        var readings: [Int: (Double, String)] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 2, let epoch = Int(fields[0]), let watts = Double(fields[1])
            else { continue }
            readings[epoch] = (watts, fields.count > 2 ? String(fields[2]) : "")
        }
        for index in points.indices {
            let epoch = Int(points[index].date.timeIntervalSince1970)
            guard let (watts, source) = readings[epoch] else { continue }
            points[index].powerWatts = watts
            points[index].powerSource = source
        }
    }

    private static func parseLine(_ line: Substring) -> MetricsHistoryPoint? {
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count == 12,
              let epoch = Double(fields[0]),
              let memUsed = Int64(fields[2]),
              let memTotal = Int64(fields[3]),
              let diskUsed = Int64(fields[4]),
              let diskTotal = Int64(fields[5]),
              let load1 = Double(fields[10])
        else { return nil }

        func optionalDouble(_ field: Substring) -> Double? {
            field.isEmpty ? nil : Double(field)
        }

        return MetricsHistoryPoint(
            date: Date(timeIntervalSince1970: epoch),
            cpuPercent: optionalDouble(fields[1]),
            memUsedBytes: memUsed,
            memTotalBytes: memTotal,
            diskUsedBytes: diskUsed,
            diskTotalBytes: diskTotal,
            netReceivedPerSecond: optionalDouble(fields[6]),
            netSentPerSecond: optionalDouble(fields[7]),
            diskReadPerSecond: optionalDouble(fields[8]),
            diskWrittenPerSecond: optionalDouble(fields[9]),
            load1: load1,
            temperatureCelsius: optionalDouble(fields[11])
        )
    }
}
