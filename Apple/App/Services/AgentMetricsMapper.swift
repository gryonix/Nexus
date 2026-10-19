import Foundation
import ServerControl
import AgentClient

struct AgentMetricsAccumulator {
    private var totalTicks: Int64 = 0
    private var idleTicks: Int64 = 0

    mutating func hostSample(from sample: Gryonixnexusd_V1_MetricsSample) -> HostMetricsSample {
        let cores = max(1, Int(sample.cpuCores))
        let totalDelta = Int64(100 * cores)
        let busyDelta = Int64((sample.cpuPercent / 100.0) * Double(totalDelta))
        totalTicks += totalDelta
        idleTicks += totalDelta - busyDelta

        return HostMetricsSample(
            cpuTotalTicks: totalTicks,
            cpuIdleTicks: idleTicks,
            cpuCores: Int(sample.cpuCores),
            memTotalBytes: sample.memTotalBytes,
            memUsedBytes: sample.memUsedBytes,
            swapTotalBytes: sample.swapTotalBytes,
            swapUsedBytes: sample.swapUsedBytes,
            uptimeSeconds: sample.uptimeSeconds,
            load1: sample.load1,
            load5: sample.load5,
            load15: sample.load15,
            netReceivedBytes: sample.netReceivedBytes,
            netSentBytes: sample.netSentBytes,
            diskReadBytes: sample.diskReadBytes,
            diskWrittenBytes: sample.diskWrittenBytes,
            mounts: sample.mounts.map { mount in
                DiskMount(
                    target: mount.target,
                    sizeBytes: mount.sizeBytes,
                    usedBytes: mount.usedBytes,
                    usedPercent: mount.sizeBytes > 0 ? Int(mount.usedBytes * 100 / mount.sizeBytes) : 0)
            },
            osID: nil,
            osPrettyName: nil,
            temperatureCelsius: sample.hasTemperatureCelsius ? sample.temperatureCelsius : nil)
    }
}
