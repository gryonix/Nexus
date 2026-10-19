import Foundation

public enum FreeParser {
    public static func parse(_ output: String) throws -> MemoryUsage {
        var mem: (total: Int64, used: Int64)?
        var swap: (total: Int64, used: Int64)?

        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3,
                  let total = Int64(fields[1]),
                  let used = Int64(fields[2]) else { continue }
            switch fields[0] {
            case "Mem:": mem = (total, used)
            case "Swap:": swap = (total, used)
            default: break
            }
        }

        guard let mem else {
            throw ServerControlError.parseFailure(command: "free -b", detail: "no 'Mem:' row")
        }
        return MemoryUsage(
            memTotalBytes: mem.total,
            memUsedBytes: mem.used,
            swapTotalBytes: swap?.total ?? 0,
            swapUsedBytes: swap?.used ?? 0
        )
    }
}
