package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.servercontrol.CoroutineSleeper
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.HostMetricsProbe
import com.skaymer.gryonixnexus.servercontrol.HostMetricsSample
import com.skaymer.gryonixnexus.servercontrol.HostMetricsSnapshot
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.SleepProvider
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.coroutines.coroutineContext

data class HostMetricsState(
    val snapshot: HostMetricsSnapshot? = null,
    val errorMessage: String? = null,
    /** When the machine last answered, in epoch milliseconds */
    val lastSeen: Long? = null,
    /** When the current silence began, in epoch milliseconds */
    val offlineSince: Long? = null,
) {
    /** True until the first reading or the first failure arrives */
    val isConnecting: Boolean get() = snapshot == null && errorMessage == null
}

class FleetMetrics(
    private val scope: CoroutineScope,
    /** Where a live runner comes from — `ServerSessions::runner` in the app */
    private val runners: suspend (Deployment) -> SSHCommandRunner,
    /** Let go of this server's session */
    private val release: suspend (Deployment) -> Unit = {},
    private val interval: Duration = 5.seconds,
    private val sleeper: SleepProvider = CoroutineSleeper,
    private val silence: SilenceWatch? = null,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private class Poller(val deployment: Deployment, val job: Job)

    private val cards =
        java.util.concurrent.ConcurrentHashMap<String, MutableStateFlow<Map<SSHHostID, HostMetricsState>>>()
    private val pollers = mutableMapOf<String, Poller>()
    private val started = java.util.concurrent.ConcurrentHashMap<String, Long>()
    private val lastRestart = java.util.concurrent.ConcurrentHashMap<String, Long>()
    private var watchdog: Job? = null

    /** The readings of one server */
    fun card(deploymentID: String): StateFlow<Map<SSHHostID, HostMetricsState>> =
        box(deploymentID).asStateFlow()

    fun sync(deployments: List<Deployment>) {
        val wanted = deployments.associateBy { it.id }
        for ((id, poller) in pollers.toList()) {
            val updated = wanted[id]
            if (updated == null) {
                poller.job.cancel()
                pollers.remove(id)
            } else if (Fingerprint(updated) != Fingerprint(poller.deployment)) {
                poller.job.cancel()
                pollers.remove(id)
            } else if (updated != poller.deployment) {
                pollers[id] = Poller(updated, poller.job)
            }
        }
        cards.keys.retainAll(wanted.keys)
        for (deployment in deployments) {
            if (pollers[deployment.id] == null) start(deployment)
        }
    }

    fun resume(deployments: List<Deployment>) {
        sync(deployments)
        retryFailedHosts()
    }

    /** Probe again NOW — but only the servers that are failing */
    fun retryFailedHosts() {
        for ((id, poller) in pollers.toList()) {
            if (!isFailing(id)) continue
            poller.job.cancel()
            pollers.remove(id)
            start(poller.deployment)
        }
    }

    /** The app is going away */
    fun stopAll() {
        watchdog?.cancel()
        watchdog = null
        pollers.values.forEach { it.job.cancel() }
        pollers.clear()
    }

    private fun isFailing(deploymentID: String): Boolean {
        val states = cards[deploymentID]?.value?.values ?: return false
        return states.isNotEmpty() && states.all { it.errorMessage != null }
    }

    private fun start(deployment: Deployment) {
        started[deployment.id] = clock()
        val job = scope.launch { poll(deployment) }
        pollers[deployment.id] = Poller(deployment, job)
        startWatchdog()
    }

    private fun startWatchdog() {
        val watch = silence ?: return
        if (watchdog != null) return
        watchdog = scope.launch {
            while (coroutineContext.isActive) {
                sleeper.sleep(interval)
                markSilentHosts(watch)
            }
        }
    }

    /** Quiet servers show No connection; long silence rebuilds the session */
    internal suspend fun markSilentHosts(watch: SilenceWatch, now: Long = clock()) {
        val waits = watch.waits()
        for ((id, poller) in pollers.toList()) {
            val since = started[id] ?: continue
            var restart = false
            for (host in poller.deployment.nodes.map { it.sshHost }) {
                val state = box(id).value[host]
                val last = state?.lastSeen?.takeIf { it >= since }
                val quiet = (now - (last ?: since)) / 1000
                val limit = if (last == null) waits.firstAnswerSeconds else waits.silenceSeconds
                if (quiet <= limit) continue
                if (state?.errorMessage == null) fail(id, host, watch.reason(waits.silenceSeconds))
                val rebuild = waits.rebuildSeconds
                if (last != null && rebuild != null && quiet > rebuild) restart = true
            }
            val spacing = maxOf(MIN_RESTART_SPACING_SECONDS, waits.rebuildSeconds ?: 0) * 1000L
            if (restart && now - (lastRestart[id] ?: 0L) > spacing) {
                lastRestart[id] = now
                restartPoller(poller)
            }
        }
    }

    private suspend fun restartPoller(poller: Poller) {
        poller.job.cancel()
        pollers.remove(poller.deployment.id)
        release(poller.deployment)
        start(poller.deployment)
    }

    private suspend fun poll(deployment: Deployment) {
        val hosts = deployment.nodes.map { it.sshHost }
        val entry = entryHost(deployment)
        val timeout = deployment.timeouts.quickSeconds.seconds
        val previous = mutableMapOf<SSHHostID, HostMetricsSample>()
        var consecutiveFailures = 0

        while (coroutineContext.isActive) {
            val runner = try {
                runners(deployment)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                hosts.forEach { fail(deployment.id, it, reason(failure)) }
                sleeper.sleep(interval)
                continue
            }
            val probe = HostMetricsProbe(runner, timeout)
            var entryFailed = false
            var farSideFailed = false
            for (host in hosts) {
                if (!coroutineContext.isActive) break
                try {
                    val sample = probe.sample(host)
                    publish(
                        deployment.id,
                        host,
                        HostMetricsState(
                            snapshot = HostMetricsSnapshot.from(sample, previous[host]),
                            lastSeen = clock(),
                        )
                    )
                    previous[host] = sample
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (failure: Exception) {
                    previous.remove(host)
                    if (host == entry) entryFailed = true else farSideFailed = true
                    fail(deployment.id, host, reason(failure))
                }
            }
            if (entryFailed) release(deployment)
            consecutiveFailures = if (entryFailed || farSideFailed) {
                minOf(consecutiveFailures + 1, MAX_BACKOFF_STEPS)
            } else {
                0
            }
            sleeper.sleep(interval * (1 shl consecutiveFailures))
        }
    }

    private fun entryHost(deployment: Deployment): SSHHostID =
        deployment.nodes.firstOrNull { it.endpoint == deployment.entry }?.sshHost ?: SSHHostID.VPS

    private fun publish(deploymentID: String, host: SSHHostID, state: HostMetricsState) {
        val box = box(deploymentID)
        box.value = box.value + (host to state)
    }

    /** Drops the numbers, keeps when the machine last answered */
    private fun fail(deploymentID: String, host: SSHHostID, reason: String) {
        val before = box(deploymentID).value[host]
        val since = before?.offlineSince?.takeIf { before.errorMessage != null } ?: System.currentTimeMillis()
        publish(deploymentID, host, HostMetricsState(errorMessage = reason, lastSeen = before?.lastSeen, offlineSince = since))
    }

    private fun box(deploymentID: String): MutableStateFlow<Map<SSHHostID, HostMetricsState>> =
        cards.getOrPut(deploymentID) { MutableStateFlow(emptyMap()) }

    private fun reason(failure: Exception): String =
        failure.message ?: failure::class.simpleName.orEmpty()

    private data class Fingerprint(
        val host: String,
        val port: Int,
        val user: String,
        val homeWGAddress: String?,
        /** The machines and where to reach them */
        val machines: Map<SSHHostID, HostEndpoint>,
        val usesPasswordAuth: Boolean,
        val quickSeconds: Int,
    ) {
        constructor(deployment: Deployment) : this(
            host = deployment.entry.host,
            port = deployment.entry.port,
            user = deployment.entry.user,
            homeWGAddress = deployment.homeWGAddress,
            machines = deployment.nodes.associate { it.sshHost to it.endpoint },
            usesPasswordAuth = deployment.usesPasswordAuth,
            quickSeconds = deployment.timeouts.quickSeconds,
        )
    }

    private companion object {
        const val MAX_BACKOFF_STEPS = 3
        const val MIN_RESTART_SPACING_SECONDS = 120
    }
}
