package com.skaymer.gryonixnexus.app.servers.demo

import com.skaymer.gryonixnexus.app.servers.DemoHostMetrics
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import gryonixnexusd.v1.AgentUpdateEvent
import gryonixnexusd.v1.ControlSecurityRequest
import gryonixnexusd.v1.ControlServiceRequest
import gryonixnexusd.v1.DiskMount
import gryonixnexusd.v1.JobPhase
import gryonixnexusd.v1.LogLine
import gryonixnexusd.v1.LogsRequest
import gryonixnexusd.v1.MetricsSample
import gryonixnexusd.v1.SecurityAction
import gryonixnexusd.v1.SecurityOperationEvent
import gryonixnexusd.v1.ServiceAction
import gryonixnexusd.v1.ServiceOperationEvent
import gryonixnexusd.v1.ServiceOperationPhase

/** Metrics, logs and the operations that report while they run */
object DemoAgentStreams {
    private val PROGRESS = ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS
    private val COMPLETED = ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED

    fun steps(path: String, request: ByteArray, machine: DemoAgentMachine): List<DemoAgentStep>? = when (path) {
        "/gryonixnexusd.v1.Control/HostMetrics" -> metricsSamples(machine).map { it.demoStep(delay = 1_000) }
        "/gryonixnexusd.v1.Control/Logs" ->
            logLines(LogsRequest.ADAPTER.decode(request).service_id).map { it.demoStep(delay = 120) }
        "/gryonixnexusd.v1.Control/ControlService" ->
            controlService(ControlServiceRequest.ADAPTER.decode(request), machine)
        "/gryonixnexusd.v1.Security/ControlSecurity" ->
            securityRun(ControlSecurityRequest.ADAPTER.decode(request).action, machine)
        "/gryonixnexusd.v1.AgentUpdate/ApplyAgentUpdate" -> agentUpdateRun()
        else -> null
    }

    private fun metricsSamples(machine: DemoAgentMachine): List<MetricsSample> {
        val profile = DemoHostMetrics.profile(machine.id, SSHHostID.VPS)
        return (0 until 6).map { index ->
            MetricsSample(
                sampled_at = System.currentTimeMillis(),
                cpu_cores = 4,
                cpu_percent = 16.0 + index * 2,
                mem_total_bytes = profile.memTotalBytes,
                mem_used_bytes = (profile.memTotalBytes * profile.memUsedFraction).toLong(),
                uptime_seconds = 986_400.0,
                load1 = 0.7,
                load5 = 0.6,
                load15 = 0.5,
                net_received_bytes = 8_100_000_000,
                net_sent_bytes = 3_400_000_000,
                mounts = listOf(
                    DiskMount(
                        target = "/",
                        size_bytes = profile.diskTotalBytes,
                        used_bytes = (profile.diskTotalBytes * profile.diskUsedFraction).toLong(),
                    ),
                ),
            )
        }
    }

    private fun logLines(service: String): List<LogLine> = listOf(
        "Listening on 0.0.0.0:8080",
        "Database migrations are up to date",
        "GET /api/health 200 3ms",
        "Certificate renewed, expires in 89 days",
        "GET /api/health 200 2ms",
    ).map { text ->
        LogLine(
            service_id = service, at = System.currentTimeMillis(), stream = "stdout",
            text = text, container = "$service-app-1",
        )
    }

    // Starting and stopping things

    private fun controlService(asked: ControlServiceRequest, machine: DemoAgentMachine): List<DemoAgentStep> {
        val stop = asked.action == ServiceAction.SERVICE_ACTION_STOP
        DemoFleetState.setPower(stop, asked.service_id, machine)
        val verb = when (asked.action) {
            ServiceAction.SERVICE_ACTION_STOP -> "Stopping"
            ServiceAction.SERVICE_ACTION_RESTART -> "Restarting"
            else -> "Starting"
        }
        val lines = DemoAgentState.progressLines(asked.service_id, verb).map { text ->
            ServiceOperationEvent(
                phase = PROGRESS, service_id = asked.service_id, action = asked.action,
                text = text, stream = "stdout",
            ).demoStep()
        }
        val done = ServiceOperationEvent(phase = COMPLETED, service_id = asked.service_id, action = asked.action)
        return lines + done.demoStep()
    }

    private fun securityRun(action: SecurityAction, machine: DemoAgentMachine): List<DemoAgentStep> {
        val removing = action == SecurityAction.SECURITY_ACTION_REMOVE
        val bans = if (removing) emptyList() else DemoAgentState.memory(machine) { it.bans.toList() }
        val lines = DemoAgentState.progressLines("CrowdSec", verb(action)).map { text ->
            SecurityOperationEvent(phase = PROGRESS, action = action, text = text, stream = "stdout").demoStep()
        }
        val status = DemoAgentSecurity.status(
            bans,
            present = !removing,
            running = action != SecurityAction.SECURITY_ACTION_STOP && !removing,
        )
        return lines + SecurityOperationEvent(phase = COMPLETED, action = action, status = status).demoStep()
    }

    private fun verb(action: SecurityAction): String = when (action) {
        SecurityAction.SECURITY_ACTION_STOP -> "Stopping"
        SecurityAction.SECURITY_ACTION_RESTART -> "Restarting"
        SecurityAction.SECURITY_ACTION_UPDATE -> "Updating"
        SecurityAction.SECURITY_ACTION_INSTALL -> "Installing"
        SecurityAction.SECURITY_ACTION_REMOVE -> "Removing"
        else -> "Starting"
    }

    private fun agentUpdateRun(): List<DemoAgentStep> =
        listOf("Fetching the agent sources", "Building", "Restarting the service").map {
            AgentUpdateEvent(phase = JobPhase.JOB_PHASE_PROGRESS, text = it).demoStep(delay = 500)
        } + AgentUpdateEvent(phase = JobPhase.JOB_PHASE_COMPLETED).demoStep()
}
