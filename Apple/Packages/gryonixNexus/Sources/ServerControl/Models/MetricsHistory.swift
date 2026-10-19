import Foundation

/// Downsampling levels the server-side collector maintains
public enum MetricsHistoryBucket: String, CaseIterable, Sendable, Hashable {
    case tenSeconds = "10s"
    case oneMinute = "1m"
    case tenMinutes = "10m"
    case oneHour = "1h"
    case oneDay = "1d"
    case oneWeek = "1w"

    /// Seconds between two points of this bucket
    public var pointInterval: TimeInterval {
        switch self {
        case .tenSeconds: return 10
        case .oneMinute: return 60
        case .tenMinutes: return 600
        case .oneHour: return 3_600
        case .oneDay: return 86_400
        case .oneWeek: return 604_800
        }
    }
}

public struct MetricsHistoryPoint: Sendable, Hashable {
    public let date: Date
    public let cpuPercent: Double?
    public let memUsedBytes: Int64
    public let memTotalBytes: Int64
    public let diskUsedBytes: Int64
    public let diskTotalBytes: Int64
    public let netReceivedPerSecond: Double?
    public let netSentPerSecond: Double?
    public let diskReadPerSecond: Double?
    public let diskWrittenPerSecond: Double?
    public let load1: Double
    public let temperatureCelsius: Double?
    /// Watts from the host's own sensor, when it has one
    public var powerWatts: Double?
    /// The sensor: rapl, hwmon, ipmi, ups or pi
    public var powerSource: String?

    public init(date: Date, cpuPercent: Double?,
                memUsedBytes: Int64, memTotalBytes: Int64,
                diskUsedBytes: Int64, diskTotalBytes: Int64,
                netReceivedPerSecond: Double?, netSentPerSecond: Double?,
                diskReadPerSecond: Double?, diskWrittenPerSecond: Double?,
                load1: Double, temperatureCelsius: Double?,
                powerWatts: Double? = nil, powerSource: String? = nil) {
        self.date = date
        self.cpuPercent = cpuPercent
        self.memUsedBytes = memUsedBytes
        self.memTotalBytes = memTotalBytes
        self.diskUsedBytes = diskUsedBytes
        self.diskTotalBytes = diskTotalBytes
        self.netReceivedPerSecond = netReceivedPerSecond
        self.netSentPerSecond = netSentPerSecond
        self.diskReadPerSecond = diskReadPerSecond
        self.diskWrittenPerSecond = diskWrittenPerSecond
        self.load1 = load1
        self.temperatureCelsius = temperatureCelsius
        self.powerWatts = powerWatts
        self.powerSource = powerSource
    }

    public var memUsedFraction: Double {
        memTotalBytes > 0 ? Double(memUsedBytes) / Double(memTotalBytes) : 0
    }

    public var diskUsedFraction: Double {
        diskTotalBytes > 0 ? Double(diskUsedBytes) / Double(diskTotalBytes) : 0
    }
}
