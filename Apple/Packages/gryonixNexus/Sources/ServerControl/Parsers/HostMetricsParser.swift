import Foundation

/// Parses the combined `CommandCatalog.hostMetrics` probe output into one `HostMetricsSample`
public enum HostMetricsParser {
    public static func parse(_ output: String) throws -> HostMetricsSample {
        let sections = splitSections(output)
        var sample = HostMetricsSample()

        guard let stat = sections["STAT"], parseStat(stat, into: &sample),
              let mem = sections["MEM"], parseMeminfo(mem, into: &sample),
              let uptime = sections["UPTIME"], parseUptime(uptime, into: &sample)
        else {
            throw ServerControlError.parseFailure(command: "hostMetrics",
                                                  detail: "missing cpu/mem/uptime sections")
        }

        if let load = sections["LOAD"] { parseLoadavg(load, into: &sample) }
        if let net = sections["NET"] { parseNetDev(net, into: &sample) }
        if let disks = sections["DISKSTATS"] { parseDiskstats(disks, into: &sample) }
        if let df = sections["DF"] { sample.mounts = (try? DFParser.parse(df)) ?? [] }
        if let os = sections["OS"] { parseOSRelease(os, into: &sample) }
        if let nproc = sections["NPROC"], sample.cpuCores == 0 {
            sample.cpuCores = Int(nproc.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        if let temp = sections["TEMP"] { parseTemperatures(temp, into: &sample) }

        return sample
    }

    // MARK: - Sections

    private static func splitSections(_ output: String) -> [String: String] {
        var sections: [String: String] = [:]
        var currentName: String?
        var currentBody: [Substring] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("@@"), trimmed.hasSuffix("@@"), trimmed.count > 4 {
                if let name = currentName {
                    sections[name] = currentBody.joined(separator: "\n")
                }
                currentName = String(trimmed.dropFirst(2).dropLast(2))
                currentBody = []
            } else {
                currentBody.append(line)
            }
        }
        if let name = currentName {
            sections[name] = currentBody.joined(separator: "\n")
        }
        return sections
    }

    // MARK: - /proc/stat

    private static func parseStat(_ body: String, into sample: inout HostMetricsSample) -> Bool {
        var cores = 0
        var parsedAggregate = false
        for line in body.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let first = fields.first else { continue }
            if first == "cpu" {
                // user nice system idle iowait irq softirq steal
                let ticks = fields.dropFirst().prefix(8).compactMap { Int64($0) }
                guard ticks.count >= 4 else { continue }
                sample.cpuTotalTicks = ticks.reduce(0, +)
                sample.cpuIdleTicks = ticks[3] + (ticks.count > 4 ? ticks[4] : 0)
                parsedAggregate = true
            } else if first.hasPrefix("cpu") {
                cores += 1
            }
        }
        if cores > 0 { sample.cpuCores = cores }
        return parsedAggregate
    }

    // MARK: - /proc/meminfo

    private static func parseMeminfo(_ body: String, into sample: inout HostMetricsSample) -> Bool {
        var values: [String: Int64] = [:]
        for line in body.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let number = parts[1].split(separator: " ", omittingEmptySubsequences: true).first
            guard let number, let kb = Int64(number) else { continue }
            values[String(parts[0])] = kb * 1024
        }
        guard let total = values["MemTotal"] else { return false }
        let available = values["MemAvailable"]
            ?? ((values["MemFree"] ?? 0) + (values["Buffers"] ?? 0) + (values["Cached"] ?? 0))
        sample.memTotalBytes = total
        sample.memUsedBytes = max(0, total - available)
        let swapTotal = values["SwapTotal"] ?? 0
        sample.swapTotalBytes = swapTotal
        sample.swapUsedBytes = max(0, swapTotal - (values["SwapFree"] ?? 0))
        return true
    }

    // MARK: - /proc/uptime, /proc/loadavg

    private static func parseUptime(_ body: String, into sample: inout HostMetricsSample) -> Bool {
        guard let first = body.split(separator: " ").first,
              let seconds = Double(first.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        sample.uptimeSeconds = seconds
        return true
    }

    private static func parseLoadavg(_ body: String, into sample: inout HostMetricsSample) {
        let fields = body.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 3 else { return }
        sample.load1 = Double(fields[0]) ?? 0
        sample.load5 = Double(fields[1]) ?? 0
        sample.load15 = Double(fields[2]) ?? 0
    }

    // MARK: - /proc/net/dev

    /// Interfaces whose bytes also pass a real one
    static func isVirtualInterface(_ name: String) -> Bool {
        let prefixes = ["veth", "docker", "br-", "virbr", "wg", "awg", "tun", "tap", "tailscale",
                        "zt", "cali", "flannel", "cni", "ifb", "dummy"]
        return name == "lo" || prefixes.contains { name.hasPrefix($0) }
    }

    private static func parseNetDev(_ body: String, into sample: inout HostMetricsSample) {
        var received: Int64 = 0
        var sent: Int64 = 0
        for line in body.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue } // header lines have no colon
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard !isVirtualInterface(name) else { continue }
            let fields = parts[1].split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 9, let rx = Int64(fields[0]), let tx = Int64(fields[8]) else { continue }
            received += rx
            sent += tx
        }
        sample.netReceivedBytes = received
        sample.netSentBytes = sent
    }

    // MARK: - /proc/diskstats

    /// Whole physical/virtual disks only — partitions would double-count
    private static let wholeDiskPattern = #/^(sd[a-z]+|vd[a-z]+|xvd[a-z]+|hd[a-z]+|nvme\d+n\d+|mmcblk\d+)$/#

    private static func parseDiskstats(_ body: String, into sample: inout HostMetricsSample) {
        var readBytes: Int64 = 0
        var writtenBytes: Int64 = 0
        for line in body.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            // major minor name reads rmerged rsectors rms writes wmerged wsectors ...
            guard fields.count >= 10 else { continue }
            let name = String(fields[2])
            guard name.wholeMatch(of: wholeDiskPattern) != nil,
                  let readSectors = Int64(fields[5]),
                  let writtenSectors = Int64(fields[9])
            else { continue }
            // /proc/diskstats sector counts are always in 512-byte units.
            readBytes += readSectors * 512
            writtenBytes += writtenSectors * 512
        }
        sample.diskReadBytes = readBytes
        sample.diskWrittenBytes = writtenBytes
    }

    // MARK: - /etc/os-release, thermal zones

    private static func parseOSRelease(_ body: String, into sample: inout HostMetricsSample) {
        for line in body.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            switch parts[0] {
            case "ID": sample.osID = value
            case "PRETTY_NAME": sample.osPrettyName = value
            default: break
            }
        }
    }

    private static func parseTemperatures(_ body: String, into sample: inout HostMetricsSample) {
        let temps = body.split(separator: "\n")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .map { $0 / 1000 } // millidegrees
            .filter { $0 > 0 && $0 < 150 }
        sample.temperatureCelsius = temps.max()
    }
}
