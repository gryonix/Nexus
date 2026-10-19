/// One mounted filesystem from `df -B1`.
public struct DiskMount: Sendable, Hashable {
    public let target: String
    public let sizeBytes: Int64
    public let usedBytes: Int64
    public let usedPercent: Int

    public init(target: String, sizeBytes: Int64, usedBytes: Int64, usedPercent: Int) {
        self.target = target
        self.sizeBytes = sizeBytes
        self.usedBytes = usedBytes
        self.usedPercent = usedPercent
    }

    /// 0...1 for ProgressView-style bars
    public var usedFraction: Double {
        sizeBytes > 0 ? Double(usedBytes) / Double(sizeBytes) : 0
    }
}

/// Mem:/Swap: rows of `free -b`
public struct MemoryUsage: Sendable, Hashable {
    public let memTotalBytes: Int64
    public let memUsedBytes: Int64
    public let swapTotalBytes: Int64
    public let swapUsedBytes: Int64

    public init(memTotalBytes: Int64, memUsedBytes: Int64,
                swapTotalBytes: Int64, swapUsedBytes: Int64) {
        self.memTotalBytes = memTotalBytes
        self.memUsedBytes = memUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.swapUsedBytes = swapUsedBytes
    }

    public var memUsedFraction: Double {
        memTotalBytes > 0 ? Double(memUsedBytes) / Double(memTotalBytes) : 0
    }

    public var swapUsedFraction: Double {
        swapTotalBytes > 0 ? Double(swapUsedBytes) / Double(swapTotalBytes) : 0
    }
}

/// Result of a ping probe: packets received out of transmitted
public struct GeneralVPSStatus: Sendable, Hashable {
    public let forwarding: Bool
    public let selfPing: PingResult
    public let tunnelPing: PingResult

    public init(forwarding: Bool, selfPing: PingResult, tunnelPing: PingResult) {
        self.forwarding = forwarding
        self.selfPing = selfPing
        self.tunnelPing = tunnelPing
    }
}

public struct PingResult: Sendable, Hashable {
    public let transmitted: Int
    public let received: Int

    public init(transmitted: Int, received: Int) {
        self.transmitted = transmitted
        self.received = received
    }

    public var isAlive: Bool { received > 0 }
}
