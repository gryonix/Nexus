package com.skaymer.gryonixnexus.app.servers.demo

import com.skaymer.gryonixnexus.app.servers.BackupDrivesDemo
import com.skaymer.gryonixnexus.app.servers.DemoHostMetrics
import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import gryonixnexusd.v1.AgentUpdateStatus
import gryonixnexusd.v1.AllBackups
import gryonixnexusd.v1.BackupArchive
import gryonixnexusd.v1.BackupDestinationTest
import gryonixnexusd.v1.BackupDriveMode
import gryonixnexusd.v1.BackupDriveStatus
import gryonixnexusd.v1.BackupDrives
import gryonixnexusd.v1.BackupEstimate
import gryonixnexusd.v1.BackupList
import gryonixnexusd.v1.BackupSchedulePolicy
import gryonixnexusd.v1.CancelJobRequest
import gryonixnexusd.v1.DeleteBackupRequest
import gryonixnexusd.v1.DeleteVaultEntryRequest
import gryonixnexusd.v1.Job
import gryonixnexusd.v1.JobList
import gryonixnexusd.v1.JobOutcome
import gryonixnexusd.v1.ListBackupsRequest
import gryonixnexusd.v1.MetricsHistoryPoint
import gryonixnexusd.v1.MetricsHistoryResponse
import gryonixnexusd.v1.PutVaultEntriesRequest
import gryonixnexusd.v1.ServiceUpdateStatus
import gryonixnexusd.v1.SetBackupPartsRequest
import gryonixnexusd.v1.SetBackupScheduleRequest
import gryonixnexusd.v1.SetUpdateScheduleRequest
import gryonixnexusd.v1.UpdateAvailability
import gryonixnexusd.v1.UpdateCheckResult
import gryonixnexusd.v1.UpdatePolicy
import gryonixnexusd.v1.VaultSnapshot
import kotlin.math.cos
import kotlin.math.sin

/** Backups, updates, the agent's own update and the job list */
object DemoAgentMaintenance {
    fun answer(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Backup/ListBackups" ->
            backupList(ListBackupsRequest.ADAPTER.decode(request).service_id, machine).demoPayload()
        "/gryonixnexusd.v1.Backup/ListAllBackups" -> allBackups(machine).demoPayload()
        "/gryonixnexusd.v1.Backup/EstimateBackup" ->
            BackupEstimate(data_bytes = 14_400_000, free_bytes = 41_000_000_000).demoPayload()
        "/gryonixnexusd.v1.Backup/DeleteBackup" -> {
            val asked = DeleteBackupRequest.ADAPTER.decode(request)
            DemoFleetState.deleteArchive(asked.path.substringAfterLast('/'), machine)
            backupList(asked.service_id, machine).demoPayload()
        }
        "/gryonixnexusd.v1.Backup/TestBackupDestination" -> BackupDestinationTest(ok = true).demoPayload()
        else -> schedules(path, request, machine)
    }

    private fun allBackups(machine: DemoAgentMachine): AllBackups {
        val ids = machine.installed.mapNotNull { AgentServiceMapping.agentID(it.id) }.distinct()
        return AllBackups(lists = ids.map { backupList(it, machine) })
    }

    private fun backupList(service: String, machine: DemoAgentMachine) = BackupList(
        service_id = service,
        directory = "/opt/backups/$service",
        archives = DemoFleetState.archives(service, machine).map { archive ->
            BackupArchive(
                name = archive.name,
                path = "/opt/backups/$service/${archive.name}",
                size_bytes = archive.bytes,
                modified_at = archive.madeMillis,
            )
        },
    )

    // Schedules

    private fun schedules(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Backup/GetBackupSchedule" -> backupPolicy(machine).demoPayload()
        "/gryonixnexusd.v1.Backup/SetBackupSchedule" -> {
            val asked = SetBackupScheduleRequest.ADAPTER.decode(request)
            DemoFleetState.setBackupSchedule(asked.schedule, machine)
            backupPolicy(machine, asked.services, asked.retention).demoPayload()
        }
        "/gryonixnexusd.v1.Backup/SetBackupDestination", "/gryonixnexusd.v1.Backup/SetBackupDrives" ->
            backupPolicy(machine).demoPayload()
        "/gryonixnexusd.v1.Backup/SetBackupParts" ->
            backupPolicy(machine).copy(parts = SetBackupPartsRequest.ADAPTER.decode(request).parts).demoPayload()
        "/gryonixnexusd.v1.Update/GetUpdatePolicy" -> updatePolicy(machine).demoPayload()
        "/gryonixnexusd.v1.Update/SetUpdateSchedule" -> {
            val asked = SetUpdateScheduleRequest.ADAPTER.decode(request)
            DemoFleetState.setUpdateSchedule(asked.schedule, machine)
            updatePolicy(machine, asked.services).demoPayload()
        }
        "/gryonixnexusd.v1.Update/CheckUpdates" -> updateCheck(machine).demoPayload()
        else -> agentUpdateOrJobs(path, request, machine)
    }

    private fun backupPolicy(machine: DemoAgentMachine, services: List<String>? = null, retention: Int = 3) =
        BackupSchedulePolicy(
            schedule = DemoFleetState.backupSchedule(machine),
            retention = retention,
            services = services ?: machine.containers,
            destination_public_key = "ssh-ed25519 DEMO+BACKUP+DESTINATION+KEY",
            drives = demoDrives(),
        )

    /** One fictional USB drive, plugged in and half full */
    private fun demoDrives() = BackupDrives(
        mode = BackupDriveMode.BACKUP_DRIVE_MODE_BOTH,
        encrypt = true,
        uuids = listOf(BackupDrivesDemo.UUID),
        passphrase_stored = true,
        last_copy_at = System.currentTimeMillis() / 1000 - 3 * 3600,
        last_copy_ok = true,
        drives = listOf(
            BackupDriveStatus(
                uuid = BackupDrivesDemo.UUID,
                mounted = true,
                size_bytes = 61_530_439_680,
                free_bytes = 29_000_000_000,
                mount_point = "/srv/gryonix-backup/usb1",
            ),
        ),
    )

    private fun updatePolicy(machine: DemoAgentMachine, services: List<String>? = null) = UpdatePolicy(
        schedule = DemoFleetState.updateSchedule(machine),
        services = services ?: machine.containers,
    )

    private fun updateCheck(machine: DemoAgentMachine): UpdateCheckResult {
        val waiting = DemoFleetState.updatable(machine)
        return UpdateCheckResult(
            services = machine.containers.map { id ->
                ServiceUpdateStatus(
                    service_id = id,
                    availability = if (id in waiting) UpdateAvailability.UPDATE_AVAILABILITY_AVAILABLE
                    else UpdateAvailability.UPDATE_AVAILABILITY_CURRENT,
                    moved_images = if (id in waiting) listOf("$id:latest") else emptyList(),
                )
            },
        )
    }

    // The agent, its jobs and the shared vault

    private fun agentUpdateOrJobs(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? =
        when (path) {
            "/gryonixnexusd.v1.AgentUpdate/GetAgentUpdateStatus" -> AgentUpdateStatus(
                installed_version = DemoAgentOffer.installedVersion,
                update_available = DemoAgentOffer.publishedVersion != null,
                available_version = DemoAgentOffer.publishedVersion.orEmpty(),
                auto_update = DemoAgentState.memory(machine) { it.agentAutoUpdate },
            ).demoPayload()
            "/gryonixnexusd.v1.Jobs/ListJobs" -> DemoAgentState.memory(machine) { JobList(jobs = it.jobs.toList()) }
                .demoPayload()
            "/gryonixnexusd.v1.Jobs/CancelJob" -> {
                val asked = CancelJobRequest.ADAPTER.decode(request)
                DemoAgentState.memory(machine) { stored -> stored.jobs.removeAll { it.job_id == asked.job_id } }
                Job(job_id = asked.job_id, outcome = JobOutcome.JOB_OUTCOME_CANCELLED).demoPayload()
            }
            else -> vault(path, request, machine)
        }

    private fun vault(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Vault/GetVault" -> snapshot(machine).demoPayload()
        "/gryonixnexusd.v1.Vault/PutVaultEntries" -> {
            val asked = PutVaultEntriesRequest.ADAPTER.decode(request)
            DemoAgentState.memory(machine) { stored -> asked.entries.forEach { stored.vault[it.id] = it } }
            snapshot(machine).demoPayload()
        }
        "/gryonixnexusd.v1.Vault/DeleteVaultEntry" -> {
            val asked = DeleteVaultEntryRequest.ADAPTER.decode(request)
            DemoAgentState.memory(machine) { it.vault.remove(asked.id) }
            snapshot(machine).demoPayload()
        }
        else -> null
    }

    private fun snapshot(machine: DemoAgentMachine) = DemoAgentState.memory(machine) {
        VaultSnapshot(revision = it.vault.size.toLong(), entries = it.vault.values.toList())
    }

    /** Metrics the collector kept */
    fun history(bucket: String, limit: Int, machine: DemoAgentMachine): MetricsHistoryResponse {
        val profile = DemoHostMetrics.profile(machine.id, SSHHostID.VPS)
        val count = if (limit == 0) 120 else minOf(limit, 720)
        val step = seconds(bucket)
        val now = System.currentTimeMillis()
        return MetricsHistoryResponse(
            bucket = bucket,
            points = (count - 1 downTo 0).map { index ->
                val i = index.toDouble()
                MetricsHistoryPoint(
                    at = now - (i * step * 1000).toLong(),
                    cpu_percent = 18 + 12 * sin(i / 9),
                    mem_total_bytes = profile.memTotalBytes,
                    mem_used_bytes = (profile.memTotalBytes * profile.memUsedFraction).toLong(),
                    disk_total_bytes = profile.diskTotalBytes,
                    disk_used_bytes = (profile.diskTotalBytes * profile.diskUsedFraction).toLong(),
                    net_received_per_second = 120_000 + 40_000 * cos(i / 7),
                    net_sent_per_second = 60_000 + 20_000 * sin(i / 5),
                    load1 = 0.6 + 0.3 * sin(i / 11),
                )
            },
        )
    }

    private fun seconds(bucket: String): Double = when (bucket) {
        "10s" -> 10.0
        "1m" -> 60.0
        "10m" -> 600.0
        "1h" -> 3_600.0
        "1d" -> 86_400.0
        "1w" -> 604_800.0
        else -> 60.0
    }
}
