import Foundation

/// Parses `sysctl net.ipv4.ip_forward` output: "net.ipv4.ip_forward = 1"
public enum SysctlParser {
    public static func parseIPForwarding(_ output: String) throws -> Bool {
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces) == "net.ipv4.ip_forward" else {
                continue
            }
            switch parts[1].trimmingCharacters(in: .whitespaces) {
            case "1": return true
            case "0": return false
            default: break
            }
        }
        throw ServerControlError.parseFailure(
            command: "sysctl net.ipv4.ip_forward",
            detail: "no 'net.ipv4.ip_forward = 0|1' line in output"
        )
    }
}
