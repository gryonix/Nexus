package com.skaymer.gryonixnexus.servercontrol

import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/** Progress of the "restart WireGuard on both machines" flow */
sealed class WGRestartEvent {
    data object RestartingVPS : WGRestartEvent()
    data object VPSDone : WGRestartEvent()
    data object RestartSentToHome : WGRestartEvent()

    data class PollingTunnel(val attempt: Int, val maxAttempts: Int) : WGRestartEvent()

    data object Recovered : WGRestartEvent()
    data object FailedToRecover : WGRestartEvent()
}

class WireGuardRestartOperation(
    private val runner: SSHCommandRunner,
    private val config: DashboardConfig,
    private val sleeper: SleepProvider = CoroutineSleeper,
) {
    fun restartBoth(): Flow<WGRestartEvent> = flow {
        val restart = CommandCatalog.restartWireGuard(config.wgInterface)

        emit(WGRestartEvent.RestartingVPS)
        val vpsResult = runner.run(restart, SSHHostID.VPS, config.restartTimeout)
        if (!vpsResult.succeeded) {
            throw ServerControlError.commandFailure(restart, vpsResult.exitCode, vpsResult.stderr)
        }
        emit(WGRestartEvent.VPSDone)

        runner.fireAndForget(restart, SSHHostID.HOME)
        emit(WGRestartEvent.RestartSentToHome)

        val ping = CommandCatalog.pingTunnel(config.homeWGAddress)
        for (attempt in 1..MAX_POLL_ATTEMPTS) {
            sleeper.sleep(POLL_INTERVAL)
            emit(WGRestartEvent.PollingTunnel(attempt, MAX_POLL_ATTEMPTS))
            if (tunnelAnswers(ping)) {
                emit(WGRestartEvent.Recovered)
                return@flow
            }
        }
        emit(WGRestartEvent.FailedToRecover)
    }

    private suspend fun tunnelAnswers(ping: String): Boolean =
        runCatching {
            PingParser.parse(runner.run(ping, SSHHostID.VPS, config.quickTimeout).stdout).isAlive
        }.getOrDefault(false)

    companion object {
        val POLL_INTERVAL: Duration = 3.seconds
        const val MAX_POLL_ATTEMPTS = 20
    }
}

/** Progress of the "restart everything" flow */
sealed class FullRestartEvent {
    data class RestartingService(val name: String) : FullRestartEvent()
    data class ServiceRestarted(val name: String) : FullRestartEvent()

    /** The service refused to restart */
    data class ServiceFailed(val name: String, val detail: String) : FullRestartEvent()

    data object RestartSentToHomeTunnel : FullRestartEvent()
    data object RestartingVPSTunnel : FullRestartEvent()
    data object VPSTunnelDone : FullRestartEvent()
    data class WaitingForTunnel(val attempt: Int, val maxAttempts: Int) : FullRestartEvent()
    data object Recovered : FullRestartEvent()
    data object FailedToRecover : FullRestartEvent()
}

class FullRestartOperation(
    private val runner: SSHCommandRunner,
    private val config: DashboardConfig,
    private val services: List<ServiceRestartTarget>,
    private val sleeper: SleepProvider = CoroutineSleeper,
) {
    data class ServiceRestartTarget(val name: String, val command: String)

    fun run(): Flow<FullRestartEvent> = flow {
        for (service in services) {
            emit(FullRestartEvent.RestartingService(service.name))
            val result = runCatching {
                runner.run(service.command, SSHHostID.HOME, config.restartTimeout)
            }.getOrNull()
            if (result != null && result.succeeded) {
                emit(FullRestartEvent.ServiceRestarted(service.name))
            } else {
                val detail = when {
                    result == null -> "no answer"
                    result.stderr.isEmpty() -> "exit ${result.exitCode?.toString() ?: "unknown"}"
                    else -> result.stderr
                }
                emit(FullRestartEvent.ServiceFailed(service.name, detail))
            }
        }

        val restart = CommandCatalog.restartWireGuard(config.wgInterface)
        runner.fireAndForget(restart, SSHHostID.HOME)
        emit(FullRestartEvent.RestartSentToHomeTunnel)

        // 3. The VPS, reached directly rather than through the tunnel.
        emit(FullRestartEvent.RestartingVPSTunnel)
        val vpsResult = runner.run(restart, SSHHostID.VPS, config.restartTimeout)
        if (!vpsResult.succeeded) {
            throw ServerControlError.commandFailure(restart, vpsResult.exitCode, vpsResult.stderr)
        }
        emit(FullRestartEvent.VPSTunnelDone)

        // 4. Wait for the tunnel to re-form on its own.
        val ping = CommandCatalog.pingTunnel(config.homeWGAddress)
        for (attempt in 1..MAX_POLL_ATTEMPTS) {
            sleeper.sleep(POLL_INTERVAL)
            emit(FullRestartEvent.WaitingForTunnel(attempt, MAX_POLL_ATTEMPTS))
            val alive = runCatching {
                PingParser.parse(runner.run(ping, SSHHostID.VPS, config.quickTimeout).stdout).isAlive
            }.getOrDefault(false)
            if (alive) {
                emit(FullRestartEvent.Recovered)
                return@flow
            }
        }
        emit(FullRestartEvent.FailedToRecover)
    }

    companion object {
        val POLL_INTERVAL: Duration = 3.seconds
        const val MAX_POLL_ATTEMPTS = 20
    }
}
