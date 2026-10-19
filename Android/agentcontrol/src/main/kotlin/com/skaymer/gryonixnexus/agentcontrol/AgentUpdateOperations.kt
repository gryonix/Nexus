package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceUpdateStatus
import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import com.skaymer.gryonixnexus.servercontrol.AutoUpdateSettings
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import com.skaymer.gryonixnexus.servercontrol.ServiceUpdateManaging
import com.skaymer.gryonixnexus.servercontrol.ServiceUpdateReport
import com.skaymer.gryonixnexus.servercontrol.ServiceUpdateRunLog
import com.skaymer.gryonixnexus.servercontrol.ServiceUpdateRunRecord
import gryonixnexusd.v1.ServiceOperationPhase
import gryonixnexusd.v1.UpdateAvailability
import gryonixnexusd.v1.UpdateOutcome
import java.time.Instant

class AgentUpdateOperations(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) : ServiceUpdateManaging {
    /** What has moved, across the whole server */
    override suspend fun check(): List<ServiceUpdateReport> {
        val result = mapping { client.checkUpdates() }
        return result.services.map { status ->
            ServiceUpdateReport(serviceID(status.service_id), status(status))
        }
    }

    /** Applies one service's update, streaming the wrapper's output */
    override suspend fun run(
        service: ServiceID,
        onChunk: (String) -> Unit,
    ): ServiceUpdateRunRecord {
        val id = agentID(service)
        var record: ServiceUpdateRunRecord? = null
        try {
            client.runUpdate(id).collect { event ->
                when (event.phase) {
                    ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS ->
                        onChunk(if (event.text.endsWith("\n")) event.text else event.text + "\n")

                    ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED ->
                        record = ServiceUpdateRunRecord(service, outcome(event.outcome, event.reason))

                    else -> Unit
                }
            }
        } catch (error: Throwable) {
            record?.let { return it }
            if (error is AgentError.Rpc && error.text.isNotEmpty()) {
                throw ServerControlError.CommandFailed("update", null, error.text)
            }
            throw error
        }
        return record ?: throw ServerControlError.CommandFailed(
            "update",
            null,
            "the agent sent no result for this update",
        )
    }

    /** The stored schedule */
    override suspend fun loadSchedule(): AutoUpdateSettings {
        val policy = mapping { client.getUpdatePolicy() }
        return AutoUpdateSettings(
            schedule = CommandCatalog.Backups.Schedule.fromWrapperArgument(policy.schedule),
            services = policy.services.toSet(),
        )
    }

    /** What the last scheduled (or manual) run left behind */
    override suspend fun loadStatus(): ServiceUpdateRunLog {
        val policy = mapping { client.getUpdatePolicy() }
        val lastRun = policy.last_run_at.takeIf { it > 0 }?.let { Instant.ofEpochMilli(it) }
        return ServiceUpdateRunLog(
            lastRun = lastRun,
            records = policy.last_run.map { record ->
                ServiceUpdateRunRecord(
                    serviceID(record.service_id),
                    outcome(record.outcome, record.reason),
                )
            },
        )
    }

    /** Writes a new schedule */
    override suspend fun save(settings: AutoUpdateSettings) {
        mapping {
            client.setUpdateSchedule(
                settings.schedule.wrapperArgument,
                settings.services.sorted(),
            )
        }
    }

    // --------------------------------------------------------------- Helpers

    private fun agentID(service: ServiceID): String =
        AgentServiceMapping.agentID(service)
            ?: throw AgentControlError.UnsupportedService(service.rawValue)

    private suspend fun <T> mapping(body: suspend () -> T): T =
        agentFailure("update") { gate.gated(body) }

    companion object {
        /** The app's id for one of the agent's own ids */
        internal fun serviceID(agentID: String): ServiceID =
            AgentServiceMapping.serviceIDs(listOf(agentID)).firstOrNull() ?: ServiceID(agentID)

        internal fun status(status: gryonixnexusd.v1.ServiceUpdateStatus): ServiceUpdateStatus =
            when (status.availability) {
                UpdateAvailability.UPDATE_AVAILABILITY_CURRENT -> ServiceUpdateStatus.Current
                UpdateAvailability.UPDATE_AVAILABILITY_AVAILABLE ->
                    ServiceUpdateStatus.Available(status.moved_images)
                else -> ServiceUpdateStatus.Unknown
            }

        internal fun outcome(
            outcome: UpdateOutcome,
            reason: String,
        ): ServiceUpdateRunRecord.Outcome = when (outcome) {
            UpdateOutcome.UPDATE_OUTCOME_UPDATED -> ServiceUpdateRunRecord.Outcome.Updated
            UpdateOutcome.UPDATE_OUTCOME_ROLLED_BACK ->
                ServiceUpdateRunRecord.Outcome.RolledBack(reason)
            else -> ServiceUpdateRunRecord.Outcome.Failed(reason)
        }
    }
}
