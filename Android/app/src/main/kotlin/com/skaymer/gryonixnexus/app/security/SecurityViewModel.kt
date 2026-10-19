package com.skaymer.gryonixnexus.app.security

import com.skaymer.gryonixnexus.agentcontrol.AgentSecurityOperations
import com.skaymer.gryonixnexus.servercontrol.AccessGrantCommand
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostSecurityAllowlist
import com.skaymer.gryonixnexus.servercontrol.HostSecurityAutoRules
import com.skaymer.gryonixnexus.servercontrol.HostSecurityDecisions
import com.skaymer.gryonixnexus.servercontrol.HostSecurityStatus
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SshPasswordAccess
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.Locale

/** What the Security card is showing about one server */
data class SecurityScreenState(
    /** What the HOST says its intrusion defence is doing */
    val status: HostSecurityStatus? = null,
    val hasAnswered: Boolean = false,
    /** The read itself failed */
    val statusUnread: Boolean = false,
    /** A read of the status is on its way */
    val reading: Boolean = false,
    val sshAccess: SshPasswordAccess? = null,
    /** A read of SSH access is on its way */
    val readingSsh: Boolean = false,
    val busy: Boolean = false,
    val autoRules: HostSecurityAutoRules? = null,
    val autoRulesBusy: Boolean = false,
    val autoRulesFailure: String? = null,
    /** Why the last action did not happen */
    val failure: String? = null,
    val runningAction: AgentSecurityOperations.Action? = null,
    /** The last line the running action printed */
    val actionProgress: String = "",
    /** Who the host is blocking right now */
    val decisions: HostSecurityDecisions? = null,
    /** The addresses this host will never ban */
    val allowlist: HostSecurityAllowlist? = null,
    /** A change to either list is in flight */
    val listBusy: Boolean = false,
    val listFailure: String? = null,
)

class SecurityViewModel(
    private val scope: CoroutineScope,
    private val operations: suspend (Deployment) -> AgentSecurityOperations,
    private val release: suspend (Deployment) -> Unit = {},
    private val publicKey: (Deployment) -> String = { "" },
    private val runner: suspend (Deployment) -> SSHCommandRunner = { error("no session") },
    private val detached: suspend (Deployment) -> SSHCommandRunner = { error("no session") },
    /** Records a server whose sign-in method this changed */
    private val onDeploymentUpdated: (Deployment) -> Unit = {},
    private val invalidate: suspend (Deployment) -> Unit = {},
) {
    private val _state = MutableStateFlow(SecurityScreenState())
    val state: StateFlow<SecurityScreenState> = _state.asStateFlow()

    private var job: Job? = null

    fun load(deployment: Deployment) {
        job?.cancel()
        DemoSecurity.status(deployment)?.let {
            _state.value = _state.value.copy(
                status = it, hasAnswered = true, statusUnread = false, reading = false,
            )
            return
        }
        _state.value = _state.value.copy(reading = true)
        job = scope.launch {
            try {
                val status = operations(deployment).status()
                _state.value = _state.value.copy(
                    status = status, hasAnswered = true, statusUnread = false, reading = false,
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                release(deployment)
                _state.value = _state.value.copy(
                    status = null, hasAnswered = true, statusUnread = true, reading = false,
                )
            }
        }
    }

    /** The rules edited during a save that is still running */
    private var queuedAutoRules: HostSecurityAutoRules? = null
    private var sendingAutoRules: HostSecurityAutoRules? = null

    /** Read both lists */
    fun loadAutoRules(deployment: Deployment) {
        scope.launch {
            try {
                _state.value = _state.value.copy(
                    autoRules = operations(deployment).autoRules(),
                    autoRulesFailure = null,
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                _state.value = _state.value.copy(autoRulesFailure = reason(failure))
            }
        }
    }

    fun saveAutoRules(deployment: Deployment, rules: HostSecurityAutoRules) {
        if (_state.value.autoRulesBusy) {
            queuedAutoRules = rules.takeIf { it != sendingAutoRules }
            return
        }
        queuedAutoRules = rules
        scope.launch {
            _state.value = _state.value.copy(autoRulesBusy = true)
            try {
                var next = queuedAutoRules
                while (next != null) {
                    queuedAutoRules = null
                    sendingAutoRules = next
                    _state.value = _state.value.copy(
                        autoRules = operations(deployment).setAutoRules(next),
                        autoRulesFailure = null,
                    )
                    next = queuedAutoRules
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                queuedAutoRules = null
                _state.value = _state.value.copy(autoRulesFailure = reason(failure))
            } finally {
                sendingAutoRules = null
                _state.value = _state.value.copy(autoRulesBusy = false)
            }
        }
    }

    fun loadLists(deployment: Deployment) {
        scope.launch {
            try {
                val ops = operations(deployment)
                val decisions = ops.decisions()
                val allowlist = ops.allowlist()
                _state.value = _state.value.copy(
                    decisions = decisions,
                    allowlist = allowlist,
                    listFailure = null,
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                release(deployment)
                _state.value = _state.value.copy(
                    decisions = HostSecurityDecisions.UNKNOWN,
                    allowlist = HostSecurityAllowlist.UNKNOWN,
                )
            }
        }
    }

    /** Lift a ban, or add one by hand */
    fun setBan(
        deployment: Deployment,
        banned: Boolean,
        value: String,
        decisionId: String = "",
        durationSeconds: Long = 0,
        reason: String = "",
    ) {
        if (_state.value.listBusy) return
        _state.value = _state.value.copy(listBusy = true, listFailure = null)
        scope.launch {
            try {
                val decisions = operations(deployment)
                    .setBan(banned, value, decisionId, durationSeconds, reason)
                _state.value = _state.value.copy(decisions = decisions, listBusy = false)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    listBusy = false,
                    listFailure = error.message ?: error.toString(),
                )
                loadLists(deployment)
            }
            // The card behind this screen counts bans.
            load(deployment)
        }
    }

    /** Block SEVERAL addresses, one after another */
    fun setBans(
        deployment: Deployment,
        values: List<String>,
        durationSeconds: Long = 0,
        reason: String = "",
    ) {
        if (_state.value.listBusy || values.isEmpty()) return
        _state.value = _state.value.copy(listBusy = true, listFailure = null)
        scope.launch {
            try {
                val ops = operations(deployment)
                var decisions = _state.value.decisions
                for (value in values) {
                    decisions = ops.setBan(true, value, "", durationSeconds, reason)
                }
                _state.value = _state.value.copy(decisions = decisions, listBusy = false)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    listBusy = false,
                    listFailure = error.message ?: error.toString(),
                )
                loadLists(deployment)
            }
            load(deployment)
        }
    }

    /** Put an address beyond banning, or stop protecting it */
    fun setAllowed(
        deployment: Deployment,
        allowed: Boolean,
        value: String,
        comment: String = "",
        durationSeconds: Long = 0,
    ) {
        if (_state.value.listBusy) return
        _state.value = _state.value.copy(listBusy = true, listFailure = null)
        scope.launch {
            try {
                val ops = operations(deployment)
                val allowlist = ops.setAllowed(allowed, value, comment, durationSeconds)
                val decisions = runCatching { ops.decisions() }.getOrNull()
                _state.value = _state.value.copy(
                    allowlist = allowlist,
                    decisions = decisions ?: _state.value.decisions,
                    listBusy = false,
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    listBusy = false,
                    listFailure = error.message ?: error.toString(),
                )
                loadLists(deployment)
            }
            load(deployment)
        }
    }

    fun loadSshAccess(deployment: Deployment) {
        val key = publicKey(deployment)
        DemoSecurity.sshAccess(deployment)?.let {
            _state.value = _state.value.copy(sshAccess = it, readingSsh = false)
            return
        }
        _state.value = _state.value.copy(readingSsh = true)
        scope.launch {
            val access = try {
                if (key.isEmpty()) {
                    SshPasswordAccess.UNKNOWN
                } else {
                    operations(deployment).sshPasswordAccess(loginUser(deployment), key)
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                release(deployment)
                SshPasswordAccess.UNKNOWN
            }
            _state.value = _state.value.copy(sshAccess = access, readingSsh = false)
        }
    }

    /** Reads the status and SSH access again */
    fun refreshAll(deployment: Deployment) {
        load(deployment)
        loadSshAccess(deployment)
    }

    fun runAction(deployment: Deployment, action: AgentSecurityOperations.Action) {
        if (_state.value.runningAction != null) return
        scope.launch {
            _state.value = _state.value.copy(
                runningAction = action, actionProgress = "", failure = null,
            )
            try {
                operations(deployment).control(action).collect { progress ->
                    when (progress) {
                        is AgentSecurityOperations.Progress.Line ->
                            _state.value = _state.value.copy(actionProgress = progress.text)
                        is AgentSecurityOperations.Progress.Finished ->
                            _state.value = _state.value.copy(
                                status = progress.status, hasAnswered = true,
                            )
                    }
                }
                _state.value = _state.value.copy(runningAction = null, actionProgress = "")
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    runningAction = null, actionProgress = "", failure = reason(error),
                )
                load(deployment)
            }
        }
    }

    fun setSshPasswordLogin(deployment: Deployment, allowPasswords: Boolean) {
        val key = publicKey(deployment)
        scope.launch {
            _state.value = _state.value.copy(busy = true, failure = null)
            try {
                if (key.isEmpty()) error("no key for this server")
                val access = operations(deployment)
                    .setSshPasswordLogin(allowPasswords, loginUser(deployment), key)
                _state.value = _state.value.copy(sshAccess = access, busy = false)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                _state.value = _state.value.copy(busy = false, failure = reason(error))
            }
        }
    }

    fun grantAppKey(deployment: Deployment) {
        val key = publicKey(deployment)
        scope.launch {
            _state.value = _state.value.copy(busy = true, failure = null)
            try {
                if (key.isEmpty()) error("no key for this server")
                val result = runner(deployment).run(
                    AccessGrantCommand.command(key),
                    deployment.servicesHost,
                    deployment.dashboardConfig.quickTimeout,
                )
                if (!result.stdout.contains(AccessGrantCommand.MARKER)) {
                    _state.value = _state.value.copy(
                        busy = false,
                        failure = result.stderr.ifBlank { result.stdout }.trim()
                            .ifEmpty { "the server did not confirm the key" },
                    )
                    return@launch
                }
                if (deployment.usesPasswordAuth) {
                    if (!keySignInWorks(deployment)) {
                        _state.value = _state.value.copy(
                            busy = false,
                            failure = "signing in with the key did not work",
                        )
                        return@launch
                    }
                    val next = deployment.copy(usesPasswordAuth = false)
                    onDeploymentUpdated(next)
                    invalidate(deployment)
                }
                _state.value = _state.value.copy(busy = false)
                loadSshAccess(deployment.copy(usesPasswordAuth = false))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                _state.value = _state.value.copy(busy = false, failure = reason(error))
            }
        }
    }

    private suspend fun keySignInWorks(deployment: Deployment): Boolean = try {
        val probe = detached(deployment.copy(usesPasswordAuth = false))
        probe.run(
            "echo GRYONIXNEXUS_PING",
            deployment.servicesHost,
            deployment.dashboardConfig.quickTimeout,
        ).stdout.contains("GRYONIXNEXUS_PING")
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: Exception) {
        false
    }

    /** The account the app signs in to this server with */
    private fun loginUser(deployment: Deployment): String = deployment.entry.user

    private fun reason(error: Throwable): String =
        error.message?.takeIf { it.isNotBlank() } ?: error.toString()

    fun clearFailure() {
        _state.value = _state.value.copy(failure = null)
    }

    fun reset() {
        job?.cancel()
        job = null
        _state.value = SecurityScreenState()
    }

    companion object {
        fun canShow(deployment: Deployment, agentTransportAvailable: Boolean): Boolean =
            deployment.usesAgent && agentTransportAvailable

        /** 15737 → "15.7k", 128000 → "128k", 2.1M → "2.1M" */
        fun compact(n: Long): String = when {
            n < 1_000 -> n.toString()
            n < 1_000_000 -> {
                val k = n / 1_000.0
                if (k < 100) String.format(Locale.ROOT, "%.1fk", k) else "${Math.round(k)}k"
            }
            else -> {
                val m = n / 1_000_000.0
                if (m < 100) String.format(Locale.ROOT, "%.1fM", m) else "${Math.round(m)}M"
            }
        }

        /** Two-letter country code → the flag emoji, "" for an unknown code */
        fun flag(code: String): String {
            val upper = code.uppercase()
            if (upper.length != 2 || !upper.all { it in 'A'..'Z' }) return ""
            return upper.map { Character.toChars(0x1F1E6 - 'A'.code + it.code).concatToString() }
                .joinToString("")
        }
    }
}
