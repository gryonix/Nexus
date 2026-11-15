package com.skaymer.gryonixnexus.app.servers.demo

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import gryonixnexusd.v1.BackupArchive
import gryonixnexusd.v1.BackupEvent
import gryonixnexusd.v1.ContainerBackupEvent
import gryonixnexusd.v1.ContainerOperationEvent
import gryonixnexusd.v1.ContainerRemovalEvent
import gryonixnexusd.v1.ContainerUpdateEvent
import gryonixnexusd.v1.ControlContainerGroupRequest
import gryonixnexusd.v1.InstallServiceEvent
import gryonixnexusd.v1.InstallServiceRequest
import gryonixnexusd.v1.JobEvent
import gryonixnexusd.v1.JobPhase
import gryonixnexusd.v1.ModelPullEvent
import gryonixnexusd.v1.PullModelRequest
import gryonixnexusd.v1.RemoveContainerGroupRequest
import gryonixnexusd.v1.RemoveServiceRequest
import gryonixnexusd.v1.RestoreEvent
import gryonixnexusd.v1.RunBackupRequest
import gryonixnexusd.v1.RunRestoreRequest
import gryonixnexusd.v1.RunUpdateRequest
import gryonixnexusd.v1.ServiceAction
import gryonixnexusd.v1.ServiceOperationPhase
import gryonixnexusd.v1.UninstallEvent
import gryonixnexusd.v1.UpdateEvent
import gryonixnexusd.v1.UpdateOutcome
import gryonixnexusd.v1.WatchJobRequest

/** The long operations: install, remove, backup, restore, update */
object DemoAgentJobs {
    private val PROGRESS = ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS
    private val COMPLETED = ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED

    fun steps(path: String, request: ByteArray, machine: DemoAgentMachine): List<DemoAgentStep>? = when (path) {
        "/gryonixnexusd.v1.Install/InstallService" ->
            install(InstallServiceRequest.ADAPTER.decode(request).service_id, machine)
        "/gryonixnexusd.v1.Uninstall/RemoveService" ->
            remove(RemoveServiceRequest.ADAPTER.decode(request).service_id, machine)
        "/gryonixnexusd.v1.Backup/RunBackup" -> backup(RunBackupRequest.ADAPTER.decode(request).service_id, machine)
        "/gryonixnexusd.v1.Update/RunUpdate" -> update(RunUpdateRequest.ADAPTER.decode(request).service_id, machine)
        "/gryonixnexusd.v1.Restore/RunRestore" -> restore(RunRestoreRequest.ADAPTER.decode(request).service_id)
        "/gryonixnexusd.v1.Models/PullModel" -> pull(PullModelRequest.ADAPTER.decode(request).name, machine)
        else -> watchOrContainers(path, request, machine)
    }

    private fun name(id: String) = ServiceRegistry.service(ServiceID(id))?.displayName ?: id

    private fun install(id: String, machine: DemoAgentMachine): List<DemoAgentStep> {
        DemoFleetState.install(id, machine)
        return DemoAgentState.progressLines(name(id), "Installing").map {
            InstallServiceEvent(phase = PROGRESS, service_id = id, text = it, stream = "stdout").demoStep(delay = 420)
        } + InstallServiceEvent(phase = COMPLETED, service_id = id).demoStep()
    }

    private fun remove(id: String, machine: DemoAgentMachine): List<DemoAgentStep> {
        DemoFleetState.remove(id, machine)
        return DemoAgentState.progressLines(name(id), "Removing").map {
            UninstallEvent(phase = PROGRESS, service_id = id, text = it, stream = "stdout").demoStep()
        } + UninstallEvent(phase = COMPLETED, service_id = id).demoStep()
    }

    private fun backup(id: String, machine: DemoAgentMachine): List<DemoAgentStep> {
        val made = DemoFleetState.addArchive(id, machine)
        val lines = listOf("==> Backing up $id", "Stopping the containers", "Packing the data directory",
            "Starting the containers").map {
            BackupEvent(phase = PROGRESS, service_id = id, text = it, stream = "stdout").demoStep(delay = 420)
        }
        val archive = BackupArchive(
            name = made.name, path = "/opt/backups/$id/${made.name}",
            size_bytes = made.bytes, modified_at = System.currentTimeMillis(),
        )
        return lines + BackupEvent(phase = COMPLETED, service_id = id, archive = archive).demoStep()
    }

    private fun update(id: String, machine: DemoAgentMachine): List<DemoAgentStep> {
        DemoFleetState.markUpdated(id, machine)
        return DemoAgentState.progressLines(id, "Updating").map {
            UpdateEvent(phase = PROGRESS, service_id = id, text = it, stream = "stdout").demoStep(delay = 420)
        } + UpdateEvent(phase = COMPLETED, service_id = id, outcome = UpdateOutcome.UPDATE_OUTCOME_UPDATED).demoStep()
    }

    private fun restore(id: String): List<DemoAgentStep> =
        listOf("==> Restoring $id", "Unpacking the archive", "Starting the containers").map {
            RestoreEvent(phase = PROGRESS, service_id = id, text = it, stream = "stdout").demoStep(delay = 420)
        } + RestoreEvent(phase = COMPLETED, service_id = id).demoStep()

    private fun pull(name: String, machine: DemoAgentMachine): List<DemoAgentStep> {
        DemoAgentState.memory(machine) { if (name !in it.models) it.models.add(name) }
        return (1..4).map { part ->
            ModelPullEvent(
                phase = PROGRESS, text = "pulling manifest",
                total_bytes = 2_400_000_000, completed_bytes = 600_000_000L * part,
            ).demoStep(delay = 500)
        } + ModelPullEvent(phase = COMPLETED).demoStep()
    }

    /** Start, stop or restart one container group */
    private fun controlGroup(asked: ControlContainerGroupRequest, machine: DemoAgentMachine): List<DemoAgentStep> {
        DemoAgentState.memory(machine) {
            if (asked.action == ServiceAction.SERVICE_ACTION_STOP) it.stoppedGroups.add(asked.key)
            else it.stoppedGroups.remove(asked.key)
        }
        val group = DemoAgentContainers.inventory(machine).groups.firstOrNull { it.key == asked.key }
        return listOf(
            ContainerOperationEvent(phase = COMPLETED, key = asked.key, action = asked.action, group = group)
                .demoStep(delay = 400),
        )
    }

    private fun watchOrContainers(path: String, request: ByteArray, machine: DemoAgentMachine): List<DemoAgentStep>? =
        when (path) {
            "/gryonixnexusd.v1.Install/WatchInstall" ->
                listOf(InstallServiceEvent(phase = COMPLETED).demoStep(delay = 400))
            "/gryonixnexusd.v1.Jobs/WatchJob" -> {
                val asked = WatchJobRequest.ADAPTER.decode(request)
                if (DemoInstallPlans.owns(asked.job_id)) DemoInstallPlans.log(asked.job_id, asked.from_sequence)
                else listOf(JobEvent(phase = JobPhase.JOB_PHASE_COMPLETED).demoStep(delay = 400))
            }
            "/gryonixnexusd.v1.Containers/ControlContainerGroup" ->
                controlGroup(ControlContainerGroupRequest.ADAPTER.decode(request), machine)
            "/gryonixnexusd.v1.Containers/ContainerGroupLogs" -> emptyList()
            "/gryonixnexusd.v1.Containers/RunContainerGroupBackup" ->
                listOf(ContainerBackupEvent(phase = COMPLETED).demoStep(delay = 400))
            "/gryonixnexusd.v1.Containers/RemoveContainerGroup" -> {
                val key = RemoveContainerGroupRequest.ADAPTER.decode(request).key
                DemoAgentState.memory(machine) { it.removedGroups.add(key) }
                listOf(ContainerRemovalEvent(phase = COMPLETED).demoStep(delay = 400))
            }
            "/gryonixnexusd.v1.Containers/UpdateContainerGroup" ->
                listOf(ContainerUpdateEvent(phase = COMPLETED).demoStep(delay = 400))
            else -> null
        }
}
