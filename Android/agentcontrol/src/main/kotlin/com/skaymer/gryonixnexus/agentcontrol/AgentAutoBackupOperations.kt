package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.servercontrol.AutoBackupManaging
import com.skaymer.gryonixnexus.servercontrol.AutoBackupSettings
import com.skaymer.gryonixnexus.servercontrol.BackupDestinationSettings
import com.skaymer.gryonixnexus.servercontrol.BackupDestinationState
import com.skaymer.gryonixnexus.servercontrol.BackupDestinationTestResult
import com.skaymer.gryonixnexus.servercontrol.BackupDriveSettings
import com.skaymer.gryonixnexus.servercontrol.BackupDriveStatus
import com.skaymer.gryonixnexus.servercontrol.BackupDrivesState
import gryonixnexusd.v1.BackupDriveMode
import gryonixnexusd.v1.BackupDrives
import gryonixnexusd.v1.BackupSchedulePolicy
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog

class AgentAutoBackupOperations(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) : AutoBackupManaging {
    override suspend fun load(): AutoBackupSettings {
        val policy = mapping { client.getBackupSchedule() }
        return AutoBackupSettings(
            schedule = CommandCatalog.Backups.Schedule.fromWrapperArgument(policy.schedule),
            retention = if (policy.retention > 0) policy.retention else AutoBackupSettings().retention,
            services = policy.services.toSet(),
        )
    }

    /** Writes a new schedule */
    override suspend fun save(settings: AutoBackupSettings, passphrase: String?) {
        mapping {
            client.setBackupSchedule(
                settings.schedule.wrapperArgument,
                settings.retention,
                settings.services.sorted(),
                passphrase.orEmpty(),
            )
        }
    }

    // ── Destination ──────────────────────────────────────────────────────

    override suspend fun loadDestination(): BackupDestinationState =
        destination(mapping { client.getBackupSchedule() })

    override suspend fun saveDestination(settings: BackupDestinationSettings, secret: String?) {
        mapping {
            client.setBackupDestination(
                gryonixnexusd.v1.BackupDestination(
                    kind = when (settings.kind) {
                        BackupDestinationSettings.Kind.SSH ->
                            gryonixnexusd.v1.BackupDestinationKind.BACKUP_DESTINATION_KIND_SSH
                        BackupDestinationSettings.Kind.S3 ->
                            gryonixnexusd.v1.BackupDestinationKind.BACKUP_DESTINATION_KIND_S3
                        BackupDestinationSettings.Kind.NONE ->
                            gryonixnexusd.v1.BackupDestinationKind.BACKUP_DESTINATION_KIND_NONE
                    },
                    host = settings.host.trim(),
                    port = maxOf(settings.port, 0),
                    user = settings.user.trim(),
                    path = settings.path.trim(),
                    bucket = settings.bucket.trim(),
                    keep = maxOf(settings.keep, 0),
                ),
                secret.orEmpty(),
            )
        }
    }

    override suspend fun testDestination(): BackupDestinationTestResult {
        val answer = mapping { client.testBackupDestination() }
        return BackupDestinationTestResult(answer.ok, answer.detail)
    }

    // ── USB drives ───────────────────────────────────────────────────────

    override suspend fun loadDrives(): BackupDrivesState = drives(mapping { client.getBackupSchedule() })

    override suspend fun saveDrives(settings: BackupDriveSettings) {
        val mode = when (settings.mode) {
            BackupDriveSettings.Mode.BOTH -> BackupDriveMode.BACKUP_DRIVE_MODE_BOTH
            BackupDriveSettings.Mode.LOCAL -> BackupDriveMode.BACKUP_DRIVE_MODE_LOCAL
            BackupDriveSettings.Mode.DRIVE -> BackupDriveMode.BACKUP_DRIVE_MODE_DRIVE
        }
        mapping { client.setBackupDrives(BackupDrives(mode = mode, encrypt = settings.encrypt, uuids = settings.uuids)) }
    }

    /** The policy's drive half; an older agent sends none */
    internal fun drives(policy: BackupSchedulePolicy): BackupDrivesState {
        val wire = policy.drives ?: return BackupDrivesState(supported = false)
        val mode = when (wire.mode) {
            BackupDriveMode.BACKUP_DRIVE_MODE_LOCAL -> BackupDriveSettings.Mode.LOCAL
            BackupDriveMode.BACKUP_DRIVE_MODE_DRIVE -> BackupDriveSettings.Mode.DRIVE
            else -> BackupDriveSettings.Mode.BOTH
        }
        return BackupDrivesState(
            settings = BackupDriveSettings(mode, wire.encrypt, wire.uuids),
            statuses = wire.drives.map {
                BackupDriveStatus(it.uuid, it.mounted, it.size_bytes, it.free_bytes, it.mount_point)
            },
            lastCopyAt = wire.last_copy_at,
            lastCopySucceeded = wire.last_copy_ok,
            lastError = wire.last_copy_error,
            hasPassphrase = wire.passphrase_stored,
        )
    }

    /** The policy's destination half as the app's own type */
    private fun destination(policy: BackupSchedulePolicy): BackupDestinationState {
        val wire = policy.destination
        val settings = if (wire == null) {
            BackupDestinationSettings()
        } else {
            BackupDestinationSettings(
                kind = when (wire.kind) {
                    gryonixnexusd.v1.BackupDestinationKind.BACKUP_DESTINATION_KIND_SSH ->
                        BackupDestinationSettings.Kind.SSH
                    gryonixnexusd.v1.BackupDestinationKind.BACKUP_DESTINATION_KIND_S3 ->
                        BackupDestinationSettings.Kind.S3
                    else -> BackupDestinationSettings.Kind.NONE
                },
                host = wire.host,
                port = if (wire.port > 0) wire.port else 22,
                user = wire.user,
                path = wire.path,
                bucket = wire.bucket,
                keep = wire.keep,
            )
        }
        return BackupDestinationState(
            settings = settings,
            publicKey = policy.destination_public_key,
            lastShipmentAt = policy.last_shipment_at.takeIf { it > 0 },
            lastShipmentSucceeded = policy.last_shipment_ok,
            lastError = policy.last_shipment_error,
        )
    }

    private suspend fun <T> mapping(body: suspend () -> T): T =
        agentFailure("backup schedule") { gate.gated(body) }
}
