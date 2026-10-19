import Foundation

public enum BackupListParser {
    public static let defaultLimit = 10

    public static func parse(_ output: String, limit: Int = defaultLimit) -> [BackupEntry] {
        var entries: [BackupEntry] = []
        for line in output.split(separator: "\n") {
            guard line.hasPrefix("-") || line.hasPrefix("d") else { continue }
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 9 else { continue }
            let sizeText = String(fields[4])
            let dateText = fields[5...7].joined(separator: " ")
            guard let name = nameAfterMetadataColumns(of: line) else { continue }
            entries.append(BackupEntry(name: name, sizeText: sizeText, dateText: dateText,
                                       isDirectory: line.hasPrefix("d"),
                                       sizeBytes: line.hasPrefix("d") ? nil : approximateBytes(sizeText),
                                       modifiedAt: approximateDate(fields[5...7].map(String.init))))
            if entries.count == limit { break }
        }
        return entries
    }

    /// Bytes from an `ls -h` size such as 1.2G
    static func approximateBytes(_ text: String) -> Int64? {
        let units: [Character: Double] = ["K": 1_024, "M": 1_048_576, "G": 1_073_741_824, "T": 1_099_511_627_776]
        guard let last = text.last else { return nil }
        if let unit = units[last] {
            return Double(text.dropLast()).map { Int64($0 * unit) }
        }
        return Int64(text)
    }

    /// Date from the three `ls` date columns
    static func approximateDate(_ columns: [String], now: Date = Date()) -> Date? {
        guard columns.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard let month = months.firstIndex(of: columns[0]), let day = Int(columns[1]) else { return nil }
        var parts = DateComponents(month: month + 1, day: day)
        if columns[2].contains(":") {
            let clock = columns[2].split(separator: ":").compactMap { Int($0) }
            guard clock.count == 2 else { return nil }
            parts.hour = clock[0]
            parts.minute = clock[1]
            parts.year = calendar.component(.year, from: now)
            guard let date = calendar.date(from: parts) else { return nil }
            // A time without a year is within six months
            if date > now.addingTimeInterval(86_400) {
                parts.year = (parts.year ?? 0) - 1
                return calendar.date(from: parts)
            }
            return date
        }
        guard let year = Int(columns[2]) else { return nil }
        parts.year = year
        return calendar.date(from: parts)
    }

    private static func nameAfterMetadataColumns(of line: Substring) -> String? {
        var index = line.startIndex
        for _ in 0..<8 {
            while index < line.endIndex, line[index] != " " { index = line.index(after: index) }
            while index < line.endIndex, line[index] == " " { index = line.index(after: index) }
        }
        guard index < line.endIndex else { return nil }
        return String(line[index...])
    }
}
