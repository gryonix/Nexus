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
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
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
    /** Where the sources come from — see `AgentSource` */
    private val chosenSource: () -> AgentSource = { AgentSource.APP },
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
            failures = installEverywhere(deployment, notice, reinstall)
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

    /** Every machine at once; the other machines' failures as text */
    private suspend fun installEverywhere(deployment: Deployment, notice: OperationNotice, reinstall: Boolean): List<String> {
        val hosts = listOf(deployment.servicesHost) + deployment.agentHosts.filter { it != deployment.servicesHost }
        val machines = AgentBuildMachines(hosts.map { machineName(deployment, it) }, summaryWords())
        return coroutineScope {
            val ticker = if (machines.isSeveral) launch { showSummaryWhileBuilding(machines, notice) } else null
            try {
                val others = hosts.drop(1).map { host ->
                    async { installOnOther(deployment, host, notice, reinstall, machines) }
                }
                installOn(deployment, hosts.first(), notice, reinstall, machines)
                others.awaitAll().filterNotNull()
            } finally {
                ticker?.cancel()
                if (machines.isSeveral) showSummary(machines, notice)
            }
        }
    }

    /** Another machine of the server; its failure as text */
    private suspend fun installOnOther(
        deployment: Deployment,
        host: SSHHostID,
        notice: OperationNotice,
        reinstall: Boolean,
        machines: AgentBuildMachines,
    ): String? {
        val name = machineName(deployment, host)
        return try {
            val probe = runners(deployment).run(SudoAccess.probeCommand(AgentBootstrapSections.SCRIPT_PATH), host, 20.seconds)
            if (!SudoAccess.isReady(probe.stdout)) {
                machines.finished(name, ok = false)
                return OperationNotices.text(R.string.agent_update_needs_access, name)
            }
            installOn(deployment, host, notice, reinstall, machines)
            null
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            "$name: ${failure.message ?: failure::class.simpleName}"
        }
    }

    private suspend fun installOn(
        deployment: Deployment,
        host: SSHHostID,
        notice: OperationNotice,
        reinstall: Boolean,
        machines: AgentBuildMachines,
    ) {
        val name = machineName(deployment, host)
        machines.started(name)
        try {
            AgentBootstrapOperations.install(
                reinstall = reinstall,
                runner = runners(deployment),
                files = browsers(deployment),
                host = host,
                sources = sources,
                source = chosenSource(),
                onPhase = { line -> phase(line, name, machines, notice) },
                onOutput = { line -> append(machines.line(line, name)) },
            )
            machines.finished(name, ok = true)
        } catch (failure: Exception) {
            machines.finished(name, ok = false)
            throw failure
        }
    }

    private fun phase(line: String, name: String, machines: AgentBuildMachines, notice: OperationNotice) {
        if (machines.isSeveral) {
            append(machines.line(line, name))
            return
        }
        _state.update { it.copy(phase = line) }
        notice.update(line)
    }

    private fun append(line: String) {
        _state.update { it.copy(log = tail(it.log + line + "\n")) }
    }

    private suspend fun showSummaryWhileBuilding(machines: AgentBuildMachines, notice: OperationNotice) {
        while (true) {
            showSummary(machines, notice)
            delay(SUMMARY_EVERY_MILLIS)
        }
    }

    private fun showSummary(machines: AgentBuildMachines, notice: OperationNotice) {
        val summary = machines.summary()
        _state.update { it.copy(phase = summary) }
        notice.update(summary)
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
        const val SUMMARY_EVERY_MILLIS = 30_000L

        /** What a machine is called in the run's lines */
        fun machineName(deployment: Deployment, host: SSHHostID): String {
            val node = deployment.nodes.firstOrNull { it.sshHost == host }
            return when {
                node != null && node.name.isNotEmpty() -> node.name
                host == SSHHostID.HOME -> OperationNotices.text(R.string.terminal_machine_local).ifEmpty { "Local" }
                host == SSHHostID.VPS -> "VPS"
                else -> node?.endpoint?.host ?: "VPS"
            }
        }

        fun summaryWords() = AgentBuildMachines.Words(
            done = { OperationNotices.text(R.string.agent_machine_done, it).ifEmpty { "$it: done" } },
            failed = { OperationNotices.text(R.string.agent_machine_failed, it).ifEmpty { "$it: failed" } },
            building = { OperationNotices.text(R.string.agent_machine_building, it).ifEmpty { "$it: building" } },
            buildingFor = { name, minutes ->
                OperationNotices.text(R.string.agent_machine_building_for, name, minutes).ifEmpty { "$name: building, $minutes min" }
            },
            waiting = { OperationNotices.text(R.string.agent_machine_waiting, it).ifEmpty { "$it: waiting" } },
        )

        fun tail(log: String): String {
            val lines = log.split("\n")
            return if (lines.size <= LINES) log else lines.takeLast(LINES).joinToString("\n")
        }
    }
}
