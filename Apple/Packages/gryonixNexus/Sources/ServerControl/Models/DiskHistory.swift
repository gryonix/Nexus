import Foundation

/// One filesystem's use at one moment of history
public struct DiskHistoryPoint: Sendable, Hashable {
    public let date: Date
    public let mount: String
    public let usedBytes: Int64
    public let totalBytes: Int64

    public init(date: Date, mount: String, usedBytes: Int64, totalBytes: Int64) {
        self.date = date
        self.mount = mount
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }

    public var usedPercent: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100 : 0 }
}

/// Which disks a disk chart draws
public enum DiskChoice: Hashable, Sendable {
    case average
    case each
    case one(String)
}

/// Reads `disks-<bucket>.csv` and turns it into chart lines
public enum DiskHistory {
    /// Rows of epoch,mount,used,total; bad rows are skipped
    public static func parse(_ text: String) -> [DiskHistoryPoint] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count == 4, let epoch = Double(fields[0]), !fields[1].isEmpty,
                  let used = Int64(fields[2]), let total = Int64(fields[3]), total > 0 else { return nil }
            return DiskHistoryPoint(date: Date(timeIntervalSince1970: epoch), mount: String(fields[1]),
                                    usedBytes: used, totalBytes: total)
        }.sorted { $0.date < $1.date }
    }

    /// Mounts in the order the chart lists them, root first
    public static func mounts(_ points: [DiskHistoryPoint]) -> [String] {
        Set(points.map(\.mount)).sorted { lhs, rhs in
            lhs == "/" || (rhs != "/" && lhs < rhs)
        }
    }

    /// Named lines of used percent over time for the choice
    public static func lines(_ points: [DiskHistoryPoint],
                             choice: DiskChoice) -> [(name: String, values: [(date: Date, value: Double)])] {
        switch choice {
        case .one(let mount):
            return [(mount, values(points.filter { $0.mount == mount }))]
        case .each:
            return mounts(points).map { mount in (mount, values(points.filter { $0.mount == mount })) }
        case .average:
            let byDate = Dictionary(grouping: points, by: \.date)
            let averaged = byDate.map { date, rows in
                (date: date, value: rows.reduce(0) { $0 + $1.usedPercent } / Double(rows.count))
            }.sorted { $0.date < $1.date }
            return [("", averaged)]
        }
    }

    private static func values(_ points: [DiskHistoryPoint]) -> [(date: Date, value: Double)] {
        points.map { (date: $0.date, value: $0.usedPercent) }
    }
}
