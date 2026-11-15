/// Parses `systemctl show` blocks into one status per loaded unit
public enum SystemdShowParser {
    public static func parse(_ output: String) -> [ContainerStatus] {
        output.components(separatedBy: "\n\n").compactMap { block in
            var fields: [String: String] = [:]
            for line in block.split(separator: "\n") {
                guard let equals = line.firstIndex(of: "=") else { continue }
                fields[String(line[..<equals])] = String(line[line.index(after: equals)...])
            }
            guard let name = fields["Id"], fields["LoadState"] != "not-found" else { return nil }
            return ContainerStatus(name: name, status: status(fields["ActiveState"] ?? ""))
        }
    }

    private static func status(_ state: String) -> String {
        switch state {
        case "active", "reloading": return "Up (active)"
        case "failed": return "Exited (failed)"
        default: return "not running (\(state))"
        }
    }
}
