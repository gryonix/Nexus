package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.OperationNotice
import com.skaymer.gryonixnexus.app.notify.OperationKind
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import com.skaymer.gryonixnexus.recipe.AgentBootstrapSections
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.RemoteFileBrowser
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.SudoAccess
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the sheet shows while the agent is being installed */
data class AgentInstallState(
    val isRunning: Boolean = false,
    val phase: String = "",
    val log: String = "",
    val errorMessage: String? = null,
    val installedVersion: String? = null,
    val isFinished: Boolean = false,
)

data class AgentCheckState(
    val isChecking: Boolean = false,
    val answer: AgentPresence.Answer? = null,
)

class AgentInstallViewModel(
    private val scope: CoroutineScope,
    private val runners: suspend (Deployment) -> SSHCommandRunner,
    /** Its file half; see `AgentBootstrapOperations.install` */
    private val browsers: suspend (Deployment) -> RemoteFileBrowser,
    private val sources: AgentBootstrapOperations.Sources,
    /** Asks the AGENT for its version */
    private val version: suspend (Deployment) -> String,
    private val onAgentFound: suspend (Deployment) -> Unit = {},
    private val release: suspend (Deployment) -> Unit = {},
    /** Sets up passwordless sudo first, asking once */
    private val ensureSudo: suspend (Deployment) -> Unit = {},
) {
    private val _state = MutableStateFlow(AgentInstallState())
    val state: StateFlow<AgentInstallState> = _state.asStateFlow()

    private val _check = MutableStateFlow(AgentCheckState())
    val check: StateFlow<AgentCheckState> = _check.asStateFlow()

    /** Installs or updates; [reinstall] rebuilds even the same version */
    fun install(deployment: Deployment, reinstall: Boolean = false) {
        if (_state.value.isRunning) return
        _state.value = AgentInstallState(isRunning = true, phase = AgentBootstrapOperations.SENDING)
        scope.launch {
            val title = if (reinstall) R.string.notice_reinstalling_agent else R.string.notice_installing_agent
            val notice = OperationNotices.start(title, server = deployment.name, kind = OperationKind.INSTALL)
            try {
                runInstall(deployment, notice, reinstall)
            } finally {
                notice.finish(OperationNotices.text(R.string.notice_done), _state.value.errorMessage,
                    retry = { install(deployment, reinstall) })
            }
        }
    }

    private suspend fun runInstall(deployment: Deployment, notice: OperationNotice, reinstall: Boolean) {
        val failures: List<String>
        try {
            ensureSudo(deployment)
            installOn(deployment, deployment.servicesHost, notice, reinstall)
            failures = deployment.agentHosts.filter { it != deployment.servicesHost }
                .mapNotNull { installOnOther(deployment, it, notice, reinstall) }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            release(deployment)
            _state.value = _state.value.copy(
                isRunning = false,
                isFinished = true,
                errorMessage = failure.message ?: failure::class.simpleName,
            )
            return
        }

        try {
            val reported = version(deployment)
            val answer = AgentPresence.answered(reported)
            AgentPresence.repaired(deployment, answer)?.let { onAgentFound(it) }
            _check.value = AgentCheckState(answer = answer)
            _state.value = _state.value.copy(
                isRunning = false,
                isFinished = true,
                installedVersion = reported,
                errorMessage = failures.joinToString("\n").ifEmpty { null },
            )
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            release(deployment)
            _state.value = _state.value.copy(
                isRunning = false,
                isFinished = true,
                errorMessage = "The agent was installed but is not answering: " +
                    (failure.message ?: failure::class.simpleName),
            )
        }
    }

    /** Another machine of the server; its failure as text */
    private suspend fun installOnOther(
        deployment: Deployment,
        host: SSHHostID,
        notice: OperationNotice,
        reinstall: Boolean,
    ): String? {
        val name = OperationNotices.text(R.string.agent_host_relay)
        return try {
            val probe = runners(deployment).run(SudoAccess.probeCommand(AgentBootstrapSections.SCRIPT_PATH), host, 20.seconds)
            if (!SudoAccess.isReady(probe.stdout)) return OperationNotices.text(R.string.agent_update_needs_access, name)
            installOn(deployment, host, notice, reinstall)
            null
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            "$name: ${failure.message ?: failure::class.simpleName}"
        }
    }

    private suspend fun installOn(deployment: Deployment, host: SSHHostID, notice: OperationNotice, reinstall: Boolean) {
        AgentBootstrapOperations.install(
            reinstall = reinstall,
            runner = runners(deployment),
            files = browsers(deployment),
            host = host,
            sources = sources,
            onPhase = { line ->
                _state.value = _state.value.copy(phase = line)
                notice.update(line)
            },
            onOutput = { line ->
                _state.value = _state.value.copy(log = tail(_state.value.log + line + "\n"))
            },
        )
    }

    fun check(deployment: Deployment) {
        if (_check.value.isChecking) return
        _check.value = AgentCheckState(isChecking = true)
        scope.launch {
            val answer = try {
                AgentPresence.answered(version(deployment))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                AgentPresence.refused(failure)
            }
            AgentPresence.repaired(deployment, answer)?.let { onAgentFound(it) }
            _check.value = AgentCheckState(answer = answer)
        }
    }

    fun reset() {
        _state.value = AgentInstallState()
    }

    private companion object {
        /** How much of the server's chatter is kept */
        const val LINES = 20_000

        fun tail(log: String): String {
            val lines = log.split("\n")
            return if (lines.size <= LINES) log else lines.takeLast(LINES).joinToString("\n")
        }
    }
}
