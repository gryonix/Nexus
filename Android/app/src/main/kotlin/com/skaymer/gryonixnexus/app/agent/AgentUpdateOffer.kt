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
    private val now: () -> Long = System::currentTimeMillis,
    private val retryDelayMillis: Long = RETRY_DELAY_MILLIS,
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

    /** The server updating now and its place in the list */
    data class Progress(val server: String, val index: Int, val total: Int)

    private val _offer = MutableStateFlow<Offer?>(null)
    val offer: StateFlow<Offer?> = _offer.asStateFlow()
    private val _progress = MutableStateFlow<Progress?>(null)
    val progress: StateFlow<Progress?> = _progress.asStateFlow()

    private var dismissedThisRun = false
    private var checking = false
    private var lastCheckedMillis: Long? = null
    private var foundOutdated = false

    /** Each time the app is opened */
    fun checkOnLaunch() {
        val version = AgentBootstrapSections.BUNDLED_VERSION
        if (_offer.value != null || dismissedThisRun || checking) return
        if (!foundOutdated) lastCheckedMillis?.let { if (now() - it < RECHECK_AFTER_MILLIS) return }
        checking = true
        scope.launch {
            try {
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
                    val outdated = checks.mapNotNull { it.getOrNull() }.sortedBy { it.deployment.name }
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

    /** Updates each server in turn */
    fun updateAll() {
        val offer = _offer.value ?: return
        dismissedThisRun = true
        foundOutdated = false
        lastCheckedMillis = now()
        _offer.value = null
        scope.launch {
            offer.servers.forEachIndexed { index, server ->
                _progress.value = Progress(server.deployment.name, index + 1, offer.servers.size)
                if (server.source == Source.PUBLISHED) applyPublished(server.deployment) else install(server.deployment)
            }
            _progress.value = null
        }
    }

    companion object {
        const val DEADLINE_MILLIS: Long = 45_000
        const val RECHECK_AFTER_MILLIS: Long = 120_000
        const val RETRY_DELAY_MILLIS: Long = 15_000
        const val MAX_RETRIES = 4
    }
}
