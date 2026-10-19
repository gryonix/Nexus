import Foundation

/// One process as `top` saw it
public struct ProcessSample: Sendable, Hashable {
    public let pid: Int
    public let user: String
    public let cpu: Double
    public let memoryKiB: Int64
    public let command: String
}

/// A line of the top-processes list
public struct ProcessRow: Sendable, Hashable, Identifiable {
    public let name: String
    /// The full command, or empty for a group
    public let detail: String
    public let count: Int
    public let cpu: Double
    public let memoryKiB: Int64

    public var id: String { name + "\u{1}" + detail }
}

/// Reads `top` and names what it lists
public enum TopProcesses {
    /// Two samples a second apart: the second is current load
    public static let command = "LC_ALL=C top -b -n 2 -d 1 -w 512 -c -e k 2>/dev/null"

    public static func parse(_ output: String) -> [ProcessSample] {
        let blocks = output.components(separatedBy: "\ntop - ")
        guard let last = blocks.last else { return [] }
        var inTable = false
        return last.split(separator: "\n").compactMap { line in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("PID ") { inTable = true; return nil }
            guard inTable else { return nil }
            return sample(String(line))
        }.filter { !$0.command.hasPrefix("top -b -n 2") }
    }

    private static func sample(_ line: String) -> ProcessSample? {
        let fields = line.split(separator: " ", maxSplits: 11, omittingEmptySubsequences: true).map(String.init)
        guard fields.count == 12, let pid = Int(fields[0]),
              let cpu = Double(fields[8].replacingOccurrences(of: ",", with: ".")) else { return nil }
        return ProcessSample(pid: pid, user: fields[1], cpu: cpu,
                             memoryKiB: Int64(fields[5]) ?? 0, command: fields[11])
    }

    /// Named and grouped, or as the system names them
    public static func rows(_ samples: [ProcessSample], friendly: Bool, byMemory: Bool,
                            limit: Int = 15) -> [ProcessRow] {
        let rows = friendly ? grouped(samples) : samples.map {
            ProcessRow(name: executable($0.command), detail: $0.command, count: 1,
                       cpu: $0.cpu, memoryKiB: $0.memoryKiB)
        }
        let sorted = rows.sorted {
            byMemory ? ($0.memoryKiB, $0.cpu) > ($1.memoryKiB, $1.cpu) : ($0.cpu, $0.memoryKiB) > ($1.cpu, $1.memoryKiB)
        }
        return Array(sorted.prefix(limit))
    }

    private static func grouped(_ samples: [ProcessSample]) -> [ProcessRow] {
        Dictionary(grouping: samples) { ProcessNames.friendly($0.command) ?? executable($0.command) }
            .map { name, members in
                ProcessRow(name: name, detail: "", count: members.count,
                           cpu: members.reduce(0) { $0 + $1.cpu },
                           memoryKiB: members.reduce(0) { $0 + $1.memoryKiB })
            }
    }

    /// The program's own name, without path or arguments
    public static func executable(_ command: String) -> String {
        if command.hasPrefix("[") { return command }
        let first = command.split(separator: " ").first.map(String.init) ?? command
        return (first.split(separator: "/").last.map(String.init) ?? first)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
    }
}
