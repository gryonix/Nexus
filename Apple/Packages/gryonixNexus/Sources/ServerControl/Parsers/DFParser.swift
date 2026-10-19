import Foundation

public enum DFParser {
    public static func parse(_ output: String) throws -> [DiskMount] {
        let lines = output.split(separator: "\n")
        guard lines.count > 1 else {
            throw ServerControlError.parseFailure(command: "df", detail: "empty output")
        }

        var mounts: [DiskMount] = []
        for line in lines.dropFirst() {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 4,
                  let size = Int64(fields[fields.count - 3]),
                  let used = Int64(fields[fields.count - 2]),
                  let percent = Int(fields[fields.count - 1].dropLast(fields.last!.hasSuffix("%") ? 1 : 0))
            else { continue }
            // Mount point may contain spaces: everything before the size field.
            let target = fields[0..<(fields.count - 3)].joined(separator: " ")
            mounts.append(DiskMount(target: target, sizeBytes: size,
                                    usedBytes: used, usedPercent: percent))
        }

        guard !mounts.isEmpty else {
            throw ServerControlError.parseFailure(command: "df", detail: "no parsable rows")
        }
        return mounts
    }
}
