package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.recipe.AgentBootstrapSections
import com.skaymer.gryonixnexus.recipe.AgentVersion
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/** Servers whose agent is older than available */
class AgentUpdateOffer(
    private val scope: CoroutineScope,
    private val fleet: () -> List<Deployment>,
    private val installed: suspend (Deployment, SSHHostID) -> String,
    /** Installs the agent on one server, then returns */
    private val install: suspend (Deployment) -> Unit,
    /** The published update's version, if any */
    private val published: suspend (Deployment, SSHHostID) -> String? = { _, _ -> null },
    /** Has the agent apply its published update, then returns */
    private val applyPublished: suspend (Deployment) -> Unit = {},
    private val target: suspend () -> String = { AgentBootstrapSections.BUNDLED_VERSION },
    private val now: () -> Long = System::currentTimeMillis,
    private val retryDelayMillis: Long = RETRY_DELAY_MILLIS,
    private val pending: PendingAgentUpdates = PendingAgentUpdates(null),
) {
    /** Where the newer version comes from */
    enum class Source { BUNDLED, PUBLISHED }

    data class Outdated(
        val deployment: Deployment,
        val installed: String,
        val target: String = "",
        val source: Source = Source.BUNDLED,
    )

    data class Offer(val version: String, val servers: List<Outdated>)

    /** The server that ended last and how many have ended */
    data class Progress(val server: String, val index: Int, val total: Int)

    private val _offer = MutableStateFlow<Offer?>(null)
    val offer: StateFlow<Offer?> = _offer.asStateFlow()
    private val _progress = MutableStateFlow<Progress?>(null)
    val progress: StateFlow<Progress?> = _progress.asStateFlow()

    private var dismissedThisRun = false
    private var checking = false
    private var lastCheckedMillis: Long? = null
    private var foundOutdated = false
    /** Servers whose update runs right now */
    private val updating = java.util.Collections.synchronizedSet(mutableSetOf<String>())

    /** Each time the app is opened */
    fun checkOnLaunch() {
        resumePending()
        if (_offer.value != null || dismissedThisRun || checking) return
        if (!foundOutdated) lastCheckedMillis?.let { if (now() - it < RECHECK_AFTER_MILLIS) return }
        checking = true
        scope.launch {
            try {
                val version = target()
                var attempt = 0
                while (true) {
                    val soFar = java.util.concurrent.ConcurrentLinkedQueue<Outdated>()
                    val checks = coroutineScope {
                        fleet().filter { it.usesAgent }.map { deployment ->
                            async {
                                checkWithin(deployment, version).also { check ->
                                    check.getOrNull()?.let { offerSoFar(soFar, it) }
                                }
                            }
                        }.awaitAll()
                    }
                    val outdated = checks.mapNotNull { it.getOrNull() }
                        .filterNot { it.deployment.id in updating }
                        .sortedBy { it.deployment.name }
                    foundOutdated = outdated.isNotEmpty()
                    if (outdated.isNotEmpty()) {
                        if (!dismissedThisRun) _offer.value = Offer(highest(outdated), outdated)
                        lastCheckedMillis = now()
                        break
                    }
                    if (checks.none { it.isFailure }) {
                        lastCheckedMillis = now()
                        break
                    }
                    if (attempt++ >= MAX_RETRIES || dismissedThisRun) break
                    delay(retryDelayMillis)
                }
            } finally {
                checking = false
            }
        }
    }

    /** The window opens with the first outdated server */
    private fun offerSoFar(soFar: java.util.concurrent.ConcurrentLinkedQueue<Outdated>, found: Outdated) {
        synchronized(soFar) {
            if (found.deployment.id in updating) return
            soFar.add(found)
            val servers = soFar.sortedBy { it.deployment.name }
            if (!dismissedThisRun) _offer.value = Offer(highest(servers), servers)
        }
    }

    private fun highest(servers: List<Outdated>): String =
        servers.map { it.target }.reduce { best, next -> if (AgentVersion.isNewer(next, best)) next else best }

    private suspend fun checkWithin(deployment: Deployment, version: String): Result<Outdated?> =
        withTimeoutOrNull(DEADLINE_MILLIS) { check(deployment, version) }
            ?: Result.failure(IllegalStateException("no answer"))

    /** The first outdated machine; a failure when one stayed silent */
    private suspend fun check(deployment: Deployment, version: String): Result<Outdated?> {
        var silent: Exception? = null
        for (host in deployment.agentHosts) {
            val current = try {
                installed(deployment, host)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                silent = failure
                continue
            }
            if (AgentVersion.isNewer(version, current)) {
                return Result.success(Outdated(deployment, current, version))
            }
            val offered = try {
                published(deployment, host)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                null
            }
            if (offered != null && AgentVersion.isNewer(offered, current)) {
                return Result.success(Outdated(deployment, current, offered, Source.PUBLISHED))
            }
        }
        return silent?.let { Result.failure(it) } ?: Result.success(null)
    }

    fun later() {
        dismissedThisRun = true
        _offer.value = null
    }

    /** The next opening asks again, even after Later */
    fun appLeft() {
        dismissedThisRun = false
    }

    /** Updates every server at once */
    fun updateAll() {
        val offer = _offer.value ?: return
        dismissedThisRun = true
        foundOutdated = false
        lastCheckedMillis = now()
        _offer.value = null
        pending.add(offer.servers.map(pending::entry))
        run(offer.servers, resumed = false)
    }

    /** Resumes updates left running when the app closed */
    private fun resumePending() {
        val known = fleet()
        val servers = pending.load().mapNotNull { entry ->
            if (entry.deploymentID in updating) return@mapNotNull null
            val deployment = known.firstOrNull { it.id == entry.deploymentID } ?: return@mapNotNull null
            Outdated(deployment, entry.installed, entry.target, if (entry.published) Source.PUBLISHED else Source.BUNDLED)
        }
        pending.keep(known.map { it.id }.toSet())
        if (servers.isNotEmpty()) run(servers, resumed = true)
    }

    /** Every server at once, each remembered until it ends */
    private fun run(servers: List<Outdated>, resumed: Boolean) {
        updating += servers.map { it.deployment.id }
        val done = java.util.concurrent.atomic.AtomicInteger(0)
        _progress.value = Progress(servers.first().deployment.name, 0, servers.size)
        scope.launch {
            coroutineScope {
                servers.forEach { server ->
                    launch {
                        try {
                            if (!resumed || !isCurrent(server)) update(server)
                        } finally {
                            updating -= server.deployment.id
                            pending.remove(server.deployment.id)
                            _progress.value = Progress(server.deployment.name, done.incrementAndGet(), servers.size)
                        }
                    }
                }
            }
            _progress.value = null
        }
    }

    private suspend fun update(server: Outdated) {
        if (server.source == Source.PUBLISHED) applyPublished(server.deployment) else install(server.deployment)
    }

    /** The agent already runs the target version */
    private suspend fun isCurrent(server: Outdated): Boolean {
        val check = checkWithin(server.deployment, server.target)
        return check.isSuccess && check.getOrNull() == null
    }

    companion object {
        const val DEADLINE_MILLIS: Long = 45_000
        const val RECHECK_AFTER_MILLIS: Long = 120_000
        const val RETRY_DELAY_MILLIS: Long = 15_000
        const val MAX_RETRIES = 4
    }
}
