package com.skaymer.gryonixnexus.servercontrol

import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/** Fetches one [HostMetricsSample] over SSH */
class HostMetricsProbe(
    private val runner: SSHCommandRunner,
    private val timeout: Duration = 15.seconds,
) {
    suspend fun sample(host: SSHHostID): HostMetricsSample {
        val result = runner.run(CommandCatalog.HOST_METRICS, host, timeout)
        if (!result.succeeded) {
            throw ServerControlError.commandFailure(
                CommandCatalog.HOST_METRICS,
                result.exitCode,
                result.stderr,
            )
        }
        return HostMetricsParser.parse(result.stdout)
    }
}

interface MetricsHistoryReading {
    suspend fun history(bucket: MetricsHistoryBucket, host: SSHHostID): List<MetricsHistoryPoint>
}

object MetricsHistoryRouting {
    fun route(
        usesAgent: Boolean,
        agentTransportAvailable: Boolean,
        host: SSHHostID,
        agentHost: SSHHostID,
    ): ServiceControlRoute {
        if (host != agentHost) return ServiceControlRoute.SSH
        return ServiceControlRouting.route(usesAgent, agentTransportAvailable)
    }
}

/** Reads one history bucket of one host over SSH */
class MetricsHistoryProbe(
    private val runner: SSHCommandRunner,
    private val timeout: Duration = 15.seconds,
) : MetricsHistoryReading {
    override suspend fun history(
        bucket: MetricsHistoryBucket,
        host: SSHHostID,
    ): List<MetricsHistoryPoint> {
        val command = CommandCatalog.metricsHistory(bucket)
        val result = runner.run(command, host, timeout)
        if (!result.succeeded) {
            throw ServerControlError.commandFailure(command, result.exitCode, result.stderr)
        }
        return MetricsHistoryParser.parse(result.stdout)
    }
}
