import Foundation

/// The parts of a machine that decide its power draw
public struct PowerHardware: Sendable, Hashable {
    public var processor = ""
    public var sockets = 1
    public var coresPerSocket = 0
    public var threads = 0
    public var memoryBytes: Int64 = 0
    public var board = ""
    /// SMBIOS chassis type number, 0 when unknown
    public var chassis = 0
    public var virtualization = ""
    public var nvme = 0
    public var ssd = 0
    public var hdd = 0
    public var graphics = 0

    public init() {}

    public var isVirtual: Bool {
        if !virtualization.isEmpty { return virtualization != "none" }
        return board.range(of: Self.virtualBoards, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static let virtualBoards = "KVM|QEMU|VMware|VirtualBox|HVM domU|Virtual Machine|Standard PC \\("

    public static let beginMarker = "GRYONIXNEXUS_POWER_BEGIN"
    public static let endMarker = "GRYONIXNEXUS_POWER_END"

    /// Read-only probe; prints key=value lines between markers
    public static let probeCommand = [
        "echo \(beginMarker)",
        "echo \"cpu=$(grep -m1 '^model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2-)\"",
        "echo \"lscpu=$(LC_ALL=C lscpu 2>/dev/null | awk -F: '/^Model name/ {print $2; exit}')\"",
        "echo \"sockets=$(grep '^physical id' /proc/cpuinfo 2>/dev/null | sort -u | wc -l)\"",
        "echo \"cores=$(grep -m1 '^cpu cores' /proc/cpuinfo 2>/dev/null | cut -d: -f2)\"",
        "echo \"threads=$(nproc 2>/dev/null)\"",
        "echo \"mem=$(awk '/^MemTotal:/ {printf \"%.0f\", $2 * 1024}' /proc/meminfo 2>/dev/null)\"",
        "echo \"board=$({ cat /proc/device-tree/model || cat /sys/class/dmi/id/product_name; } 2>/dev/null | tr -d '\\000')\"",
        "echo \"chassis=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)\"",
        "echo \"virt=$(systemd-detect-virt 2>/dev/null)\"",
        "echo \"disks=$(lsblk -dn -o NAME,ROTA,TRAN 2>/dev/null | awk '{print $1\":\"$2\":\"$3}' | tr '\\n' ' ')\"",
        "echo \"gpus=$(cat /sys/class/drm/card[0-9]*/device/vendor 2>/dev/null | tr '\\n' ' ')\"",
        "echo \(endMarker)",
    ].joined(separator: "; ")

    public static func parse(_ output: String) -> PowerHardware? {
        guard let begin = output.range(of: beginMarker),
              let end = output.range(of: endMarker, range: begin.upperBound..<output.endIndex)
        else { return nil }
        var fields: [String: String] = [:]
        for line in output[begin.upperBound..<end.lowerBound].split(separator: "\n") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            fields[String(line[..<equals])] = line[line.index(after: equals)...]
                .trimmingCharacters(in: .whitespaces)
        }
        return make(fields)
    }

    private static func make(_ fields: [String: String]) -> PowerHardware {
        func number(_ key: String) -> Int { Int(fields[key] ?? "") ?? 0 }
        var hardware = PowerHardware()
        let cpu = fields["cpu"] ?? ""
        hardware.processor = cpu.isEmpty ? fields["lscpu"] ?? "" : cpu
        hardware.sockets = max(number("sockets"), 1)
        hardware.threads = number("threads")
        hardware.coresPerSocket = number("cores") > 0
            ? number("cores") : max(hardware.threads / hardware.sockets, 1)
        hardware.memoryBytes = Int64(fields["mem"] ?? "") ?? 0
        hardware.board = fields["board"] ?? ""
        hardware.chassis = number("chassis")
        hardware.virtualization = fields["virt"] ?? ""
        hardware.countDisks(fields["disks"] ?? "")
        hardware.countGraphics(fields["gpus"] ?? "")
        return hardware
    }

    private static let skippedDisks = ["loop", "zram", "ram", "sr", "fd", "md", "dm-", "nbd", "mmcblk"]

    private mutating func countDisks(_ text: String) {
        for entry in text.split(separator: " ") {
            let parts = entry.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard let name = parts.first, !Self.skippedDisks.contains(where: name.hasPrefix) else { continue }
            let transport = parts.count > 2 ? parts[2] : ""
            if transport == "nvme" || name.hasPrefix("nvme") { nvme += 1 }
            else if parts.count > 1, parts[1] == "1" { hdd += 1 }
            else { ssd += 1 }
        }
    }

    /// Add-in cards; AMD graphics on AMD processors are integrated
    private mutating func countGraphics(_ text: String) {
        let onAMD = processor.localizedCaseInsensitiveContains("AMD")
        graphics = text.split(separator: " ").filter { vendor in
            vendor == "0x10de" || (vendor == "0x1002" && !onAMD)
        }.count
    }
}
