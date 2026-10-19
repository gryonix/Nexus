import Foundation

/// Raw counters read in one probe pass
public struct HostMetricsSample: Sendable, Hashable {
    /// Aggregate jiffies from the first `cpu` line of /proc/stat
    public var cpuTotalTicks: Int64
    /// idle + iowait jiffies
    public var cpuIdleTicks: Int64
    public var cpuCores: Int

    /// MemTotal / (MemTotal - MemAvailable) from /proc/meminfo, in bytes
    public var memTotalBytes: Int64
    public var memUsedBytes: Int64
    public var swapTotalBytes: Int64
    public var swapUsedBytes: Int64

    public var uptimeSeconds: Double
    public var load1: Double
    public var load5: Double
    public var load15: Double

    /// Bytes since boot, summed over every interface except loopback
    public var netReceivedBytes: Int64
    public var netSentBytes: Int64

    public var diskReadBytes: Int64
    public var diskWrittenBytes: Int64

    public var mounts: [DiskMount]

    /// ID= / PRETTY_NAME= from /etc/os-release, when present
    public var osID: String?
    public var osPrettyName: String?

    /// Hottest thermal zone, °C
    public var temperatureCelsius: Double?

    public init(cpuTotalTicks: Int64 = 0, cpuIdleTicks: Int64 = 0, cpuCores: Int = 0,
                memTotalBytes: Int64 = 0, memUsedBytes: Int64 = 0,
                swapTotalBytes: Int64 = 0, swapUsedBytes: Int64 = 0,
                uptimeSeconds: Double = 0, load1: Double = 0, load5: Double = 0, load15: Double = 0,
                netReceivedBytes: Int64 = 0, netSentBytes: Int64 = 0,
                diskReadBytes: Int64 = 0, diskWrittenBytes: Int64 = 0,
                mounts: [DiskMount] = [],
                osID: String? = nil, osPrettyName: String? = nil,
                temperatureCelsius: Double? = nil) {
        self.cpuTotalTicks = cpuTotalTicks
        self.cpuIdleTicks = cpuIdleTicks
        self.cpuCores = cpuCores
        self.memTotalBytes = memTotalBytes
        self.memUsedBytes = memUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.swapUsedBytes = swapUsedBytes
        self.uptimeSeconds = uptimeSeconds
        self.load1 = load1
        self.load5 = load5
        self.load15 = load15
        self.netReceivedBytes = netReceivedBytes
        self.netSentBytes = netSentBytes
        self.diskReadBytes = diskReadBytes
        self.diskWrittenBytes = diskWrittenBytes
        self.mounts = mounts
        self.osID = osID
        self.osPrettyName = osPrettyName
        self.temperatureCelsius = temperatureCelsius
    }
}

public struct HostMetricsSnapshot: Sendable, Hashable {
    public let cpuCores: Int
    /// 0...100; nil until two samples exist
    public let cpuPercent: Double?

    public let memTotalBytes: Int64
    public let memUsedBytes: Int64
    public let swapTotalBytes: Int64
    public let swapUsedBytes: Int64

    public let diskTotalBytes: Int64
    public let diskUsedBytes: Int64

    public let uptimeSeconds: Double
    public let load1: Double
    public let load5: Double
    public let load15: Double

    /// Since-boot totals, always available
    public let netReceivedBytes: Int64
    public let netSentBytes: Int64
    public let diskReadBytes: Int64
    public let diskWrittenBytes: Int64

    /// Bytes per second; nil until two samples exist
    public let netReceivedPerSecond: Double?
    public let netSentPerSecond: Double?
    public let diskReadPerSecond: Double?
    public let diskWrittenPerSecond: Double?

    public let osID: String?
    public let osPrettyName: String?
    public let temperatureCelsius: Double?

    public let isPartial: Bool

    public init(current: HostMetricsSample, previous: HostMetricsSample?) {
        isPartial = false
        cpuCores = current.cpuCores
        memTotalBytes = current.memTotalBytes
        memUsedBytes = current.memUsedBytes
        swapTotalBytes = current.swapTotalBytes
        swapUsedBytes = current.swapUsedBytes
        uptimeSeconds = current.uptimeSeconds
        load1 = current.load1
        load5 = current.load5
        load15 = current.load15
        netReceivedBytes = current.netReceivedBytes
        netSentBytes = current.netSentBytes
        diskReadBytes = current.diskReadBytes
        diskWrittenBytes = current.diskWrittenBytes
        osID = current.osID
        osPrettyName = current.osPrettyName
        temperatureCelsius = current.temperatureCelsius

        let root = current.mounts.first { $0.target == "/" }
            ?? current.mounts.max { $0.sizeBytes < $1.sizeBytes }
        diskTotalBytes = root?.sizeBytes ?? 0
        diskUsedBytes = root?.usedBytes ?? 0

        let elapsed = previous.map { current.uptimeSeconds - $0.uptimeSeconds } ?? 0
        guard let previous, elapsed > 0 else {
            cpuPercent = nil
            netReceivedPerSecond = nil
            netSentPerSecond = nil
            diskReadPerSecond = nil
            diskWrittenPerSecond = nil
            return
        }

        let totalDelta = current.cpuTotalTicks - previous.cpuTotalTicks
        let idleDelta = current.cpuIdleTicks - previous.cpuIdleTicks
        cpuPercent = totalDelta > 0
            ? (Double(totalDelta - idleDelta) / Double(totalDelta) * 100).clamped(to: 0...100)
            : nil

        func rate(_ currentValue: Int64, _ previousValue: Int64) -> Double {
            max(0, Double(currentValue - previousValue) / elapsed)
        }
        netReceivedPerSecond = rate(current.netReceivedBytes, previous.netReceivedBytes)
        netSentPerSecond = rate(current.netSentBytes, previous.netSentBytes)
        diskReadPerSecond = rate(current.diskReadBytes, previous.diskReadBytes)
        diskWrittenPerSecond = rate(current.diskWrittenBytes, previous.diskWrittenBytes)
    }

    public init(collectorRow point: MetricsHistoryPoint) {
        isPartial = true
        cpuCores = 0
        cpuPercent = point.cpuPercent
        memTotalBytes = point.memTotalBytes
        memUsedBytes = point.memUsedBytes
        swapTotalBytes = 0
        swapUsedBytes = 0
        diskTotalBytes = point.diskTotalBytes
        diskUsedBytes = point.diskUsedBytes
        uptimeSeconds = 0
        load1 = point.load1
        load5 = 0
        load15 = 0
        netReceivedBytes = 0
        netSentBytes = 0
        diskReadBytes = 0
        diskWrittenBytes = 0
        netReceivedPerSecond = point.netReceivedPerSecond
        netSentPerSecond = point.netSentPerSecond
        diskReadPerSecond = point.diskReadPerSecond
        diskWrittenPerSecond = point.diskWrittenPerSecond
        osID = nil
        osPrettyName = nil
        temperatureCelsius = point.temperatureCelsius
    }

    public var memUsedFraction: Double {
        memTotalBytes > 0 ? Double(memUsedBytes) / Double(memTotalBytes) : 0
    }

    public var diskUsedFraction: Double {
        diskTotalBytes > 0 ? Double(diskUsedBytes) / Double(diskTotalBytes) : 0
    }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
