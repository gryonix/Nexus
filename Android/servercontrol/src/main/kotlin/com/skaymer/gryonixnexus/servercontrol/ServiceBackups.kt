package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.ManagedService

interface ServiceBackupManaging {
    /** What is in this service's backup directory, newest first */
    suspend fun listBackups(service: ManagedService): List<BackupEntry>

    suspend fun estimate(service: ManagedService): BackupEstimate?

    /** Runs one backup */
    suspend fun backup(
        service: ManagedService,
        encrypt: Boolean?,
        passphrase: String?,
        onChunk: (String) -> Unit = {},
    ): BackupOutcome

    /** Deletes one backup */
    suspend fun deleteBackup(service: ManagedService, path: String)
}

/** Which implementation a deployment's backups go through */
object BackupRouting {
    fun route(
        usesAgent: Boolean,
        agentTransportAvailable: Boolean,
        kind: ServiceOperations.BackupKind,
    ): ServiceControlRoute {
        if (kind != ServiceOperations.BackupKind.WRAPPER) return ServiceControlRoute.SSH
        return ServiceControlRouting.route(usesAgent, agentTransportAvailable)
    }
}

/** The SSH implementation: the existing catalog-derived commands, unchanged */
class SSHServiceBackups(
    private val runner: SSHCommandRunner,
    private val deployment: Deployment,
    private val language: AppLanguage = AppLanguage.EN,
) : ServiceBackupManaging {
    private fun operations(service: ManagedService) =
        ServiceOperations(runner, deployment, service, language)

    override suspend fun listBackups(service: ManagedService): List<BackupEntry> =
        operations(service).listBackups()

    override suspend fun estimate(service: ManagedService): BackupEstimate? =
        operations(service).estimateBackup()

    override suspend fun backup(
        service: ManagedService,
        encrypt: Boolean?,
        passphrase: String?,
        onChunk: (String) -> Unit,
    ): BackupOutcome = operations(service).backup(encrypt, passphrase, onChunk)

    override suspend fun deleteBackup(service: ManagedService, path: String) =
        operations(service).deleteBackup(path)
}
