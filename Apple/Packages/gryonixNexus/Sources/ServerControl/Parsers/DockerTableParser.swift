import Foundation

enum DockerTableParser {
    struct Table {
        let header: String
        let rows: [String]

        func column(_ name: String, nextColumn: String?) -> [String]? {
            guard let start = header.range(of: name) else { return nil }
            let startOffset = header.distance(from: header.startIndex, to: start.lowerBound)
            let endOffset: Int?
            if let nextColumn, let next = header.range(of: nextColumn) {
                endOffset = header.distance(from: header.startIndex, to: next.lowerBound)
            } else {
                endOffset = nil
            }
            return rows.map { row in
                guard row.count > startOffset else { return "" }
                let from = row.index(row.startIndex, offsetBy: startOffset)
                let to: String.Index
                if let endOffset, row.count > endOffset {
                    to = row.index(row.startIndex, offsetBy: endOffset)
                } else {
                    to = row.endIndex
                }
                return row[from..<to].trimmingCharacters(in: .whitespaces)
            }
        }
    }

    static func table(from output: String, command: String) throws -> Table {
        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // Skip any warning lines docker prints before the actual table.
        guard let headerIndex = lines.firstIndex(where: {
            $0.contains("STATUS") && ($0.contains("NAME") || $0.contains("CONTAINER"))
        }) else {
            throw ServerControlError.parseFailure(command: command, detail: "no table header in output")
        }
        return Table(header: lines[headerIndex], rows: Array(lines[(headerIndex + 1)...]))
    }
}

/// Parses `docker compose -p <project> ps` into container statuses
public enum DockerComposePSParser {
    public static func parse(_ output: String) throws -> [ContainerStatus] {
        let table = try DockerTableParser.table(from: output, command: "docker compose ps")
        guard let names = table.column("NAME", nextColumn: "IMAGE"),
              let statuses = table.column("STATUS", nextColumn: "PORTS") else {
            throw ServerControlError.parseFailure(
                command: "docker compose ps", detail: "missing NAME/STATUS columns"
            )
        }
        return zip(names, statuses)
            .filter { !$0.0.isEmpty }
            .map { ContainerStatus(name: $0.0, status: $0.1) }
    }
}

public enum DockerPSParser {
    public static func parse(_ output: String) throws -> [ContainerStatus] {
        let table = try DockerTableParser.table(from: output, command: "docker ps -a")
        // NAMES is the last column; STATUS is followed by PORTS.
        guard let names = table.column("NAMES", nextColumn: nil),
              let statuses = table.column("STATUS", nextColumn: "PORTS") else {
            throw ServerControlError.parseFailure(
                command: "docker ps -a", detail: "missing NAMES/STATUS columns"
            )
        }
        return zip(names, statuses)
            .filter { !$0.0.isEmpty }
            .map { ContainerStatus(name: $0.0, status: $0.1) }
    }

    public static func find(container name: String, in statuses: [ContainerStatus]) -> ContainerStatus? {
        statuses.first { status in
            status.name.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .contains(name)
        }
    }
}
