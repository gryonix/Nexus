package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.agentclient.AgentHostSurface
import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import com.skaymer.gryonixnexus.servercontrol.ContainerStatus
import com.skaymer.gryonixnexus.servercontrol.OutputTail
import gryonixnexusd.v1.ServiceOperationPhase
import java.time.Instant

class AgentInstallOperations(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) {
    suspend fun provisionHost(context: AgentInstallContext): ProvisionOutcome {
        val response = gate.gated {
            client.provisionHost(
                domain = context.domain,
                additionalDomains = context.additionalDomains,
                localOnly = context.localOnly,
                adminUsername = context.adminUsername,
                language = context.language.code,
                settings = context.settings,
                host = context.host,
            )
        }
        return ProvisionOutcome(response.written, response.control_user, response.notes)
    }

    /** Start an install and narrate it */
    suspend fun install(
        service: ServiceID,
        context: AgentInstallContext,
        onJobID: ((String) -> Unit)? = null,
        onChunk: (String) -> Unit,
        onWarning: ((String) -> Unit)? = null,
    ): String {
        val id = agentID(service)
        return follow(
            onJobID,
            onChunk,
            onWarning,
        ) {
            client.installService(
                serviceID = id,
                domain = context.domain,
                additionalDomains = context.additionalDomains,
                localOnly = context.localOnly,
                adminUsername = context.adminUsername,
                language = context.language.code,
                settings = context.settings,
                host = context.host,
            )
        }
    }

    suspend fun watch(
        jobID: String,
        from: Long = 0,
        onChunk: (String) -> Unit,
        onWarning: ((String) -> Unit)? = null,
    ): String =
        follow(onJobID = null, onChunk = onChunk, onWarning = onWarning) { client.watchInstall(jobID, from) }

    /** Starts a plan, or joins the running one */
    suspend fun startPlan(
        services: List<Pair<ServiceID, AgentInstallContext>>,
        purpose: AgentPlanPurpose = AgentPlanPurpose.ADD,
    ): AgentInstallPlan {
        val requests = services.map { (service, context) ->
            AgentClient.installRequest(
                serviceID = agentID(service),
                domain = context.domain,
                additionalDomains = context.additionalDomains,
                localOnly = context.localOnly,
                adminUsername = context.adminUsername,
                language = context.language.code,
                settings = context.settings,
                host = context.host,
            )
        }
        return try {
            AgentInstallPlan.of(gate.gated { client.startInstallPlan(requests, purpose.wire) })
        } catch (error: AgentError.Rpc) {
            if (error.code != "already_exists") throw error
            plan()
        }
    }

    /** A plan by id; empty id means newest */
    suspend fun plan(id: String = ""): AgentInstallPlan = AgentInstallPlan.of(client.installPlan(id))

    /** Follows a plan's own log; [mark] survives a drop */
    suspend fun followPlan(
        started: AgentInstallPlan,
        onService: (String) -> Unit,
        onProgress: (settled: Int, total: Int) -> Unit,
        onChunk: (String) -> Unit,
        onWarning: ((String) -> Unit)? = null,
        pauseMillis: Long = 2_000,
        mark: PlanLogMark = PlanLogMark(),
    ): AgentInstallPlan {
        var plan = started
        while (true) {
            onProgress(plan.settled, plan.items.size)
            client.watchJob(plan.id, mark.next).collect { event ->
                mark.next = event.sequence + 1
                if (event.phase != gryonixnexusd.v1.JobPhase.JOB_PHASE_PROGRESS || event.text.isEmpty()) return@collect
                val step = AgentInstallPlan.step(event.text)
                if (step != null) {
                    onService(step.third)
                    onProgress(step.first - 1, step.second)
                } else {
                    onChunk(if (event.text.endsWith("\n")) event.text else event.text + "\n")
                    if (event.stream == "warning") onWarning?.invoke(event.text)
                }
            }
            plan = plan(plan.id).also { if (it.id != started.id) throw PlanLost() }
            if (plan.finished) {
                onProgress(plan.settled, plan.items.size)
                return plan
            }
            kotlinx.coroutines.delay(pauseMillis)
        }
    }

    /** The next log line to ask the agent for */
    class PlanLogMark {
        @Volatile var next: Long = 0L
    }

    /** The agent restarted and forgot the plan */
    class PlanLost : Exception(
        "The agent restarted during the installation and lost its list. " +
            "Start the installation again: what is already installed is skipped.",
    )

    // --------------------------------------------------------------- Helpers

    private suspend fun follow(
        onJobID: ((String) -> Unit)?,
        onChunk: (String) -> Unit,
        onWarning: ((String) -> Unit)? = null,
        open: () -> kotlinx.coroutines.flow.Flow<gryonixnexusd.v1.InstallServiceEvent>,
    ): String {
        val log = StringBuilder()
        var status: List<ContainerStatus>? = null
        var announcedJob = false
        try {
            open().collect { event ->
                if (!announcedJob && event.job_id.isNotEmpty()) {
                    announcedJob = true
                    onJobID?.invoke(event.job_id)
                }
                when (event.phase) {
                    ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS -> {
                        val line = if (event.text.endsWith("\n")) event.text else event.text + "\n"
                        log.append(line)
                        onChunk(line)
                        if (event.stream == "warning") {
                            onWarning?.invoke(event.text)
                        }
                    }

                    ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED ->
                        status = event.service?.containers.orEmpty()
                            .map(AgentCommandRunner::containerStatus)

                    else -> Unit
                }
            }
        } catch (error: Throwable) {
            val seen = status ?: throw error
            throw AgentControlError.OperationFailed(AgentCommandRunner.asAgentError(error), seen)
        }
        return OutputTail.tail(log.toString())
    }

    private fun agentID(service: ServiceID): String =
        AgentServiceMapping.agentID(service)
            ?: throw AgentControlError.UnsupportedService(service.rawValue)
}

/** What [AgentInstallOperations.provisionHost] answered */
data class ProvisionOutcome(
    /** The paths written */
    val written: List<String>,
    val controlUser: String,
    /** What the call did BESIDES writing files */
    val notes: List<String>,
)

data class AgentInstallContext(
    val domain: String,
    val additionalDomains: List<String> = emptyList(),
    /** Whether Caddy signs its own certificate instead of asking ACME */
    val localOnly: Boolean = false,
    val adminUsername: String = "",
    val language: AppLanguage = AppLanguage.EN,
    val settings: Map<String, String> = emptyMap(),
    val host: AgentHostSurface = AgentHostSurface(),
)
