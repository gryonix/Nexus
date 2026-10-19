package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryBucket
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryPoint
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryReading
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import java.time.Instant
import kotlin.time.Duration

class AgentMetricsHistory(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
    private val window: Duration? = null,
    private val now: () -> Instant = { Instant.now() },
) : MetricsHistoryReading {
    override suspend fun history(
        bucket: MetricsHistoryBucket,
        host: SSHHostID,
    ): List<MetricsHistoryPoint> {
        val since = window?.let { now().toEpochMilli() - it.inWholeMilliseconds }
        val response = gate.gated {
            client.metricsHistory(bucket.rawValue, sinceEpochMillis = since)
        }
        return response.points.map(::historyPoint)
    }

    companion object {
        /** The agent's point in the shape the chart already reads */
        internal fun historyPoint(point: gryonixnexusd.v1.MetricsHistoryPoint) = MetricsHistoryPoint(
            date = Instant.ofEpochMilli(point.at),
            cpuPercent = point.cpu_percent,
            memUsedBytes = point.mem_used_bytes,
            memTotalBytes = point.mem_total_bytes,
            diskUsedBytes = point.disk_used_bytes,
            diskTotalBytes = point.disk_total_bytes,
            netReceivedPerSecond = point.net_received_per_second,
            netSentPerSecond = point.net_sent_per_second,
            diskReadPerSecond = point.disk_read_per_second,
            diskWrittenPerSecond = point.disk_written_per_second,
            load1 = point.load1,
            temperatureCelsius = point.temperature_celsius,
            powerWatts = point.power_watts,
            powerSource = point.power_source.ifEmpty { null },
        )
    }
}
