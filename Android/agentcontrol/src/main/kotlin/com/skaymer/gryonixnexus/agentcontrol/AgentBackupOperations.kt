package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import com.skaymer.gryonixnexus.servercontrol.BackupEntry
import com.skaymer.gryonixnexus.servercontrol.BackupEstimate
import com.skaymer.gryonixnexus.servercontrol.BackupListParser
import com.skaymer.gryonixnexus.servercontrol.BackupOutcome
import com.skaymer.gryonixnexus.servercontrol.OutputTail
import com.skaymer.gryonixnexus.servercontrol.ServiceBackupManaging
import gryonixnexusd.v1.BackupArchive
import gryonixnexusd.v1.BackupEncryption
import gryonixnexusd.v1.ServiceOperationPhase
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

class AgentBackupOperations(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
    private val language: AppLanguage = AppLanguage.EN,
) : ServiceBackupManaging {
    override suspend fun listBackups(service: ManagedService): List<BackupEntry> {
        val id = agentID(service)
        val list = mapping { client.listBackups(id) }
        return list.archives.take(BackupListParser.DEFAULT_LIMIT).map { entry(it, language) }
    }

    /** Every service's backups in one call, by agent service id */
    suspend fun listAll(): Map<String, List<BackupEntry>> {
        val all = mapping { client.listAllBackups() }
        return all.lists.associate { list -> list.service_id to list.archives.map { entry(it, language) } }
    }

    override suspend fun estimate(service: ManagedService): BackupEstimate? {
        val id = agentID(service)
        val estimate = mapping { client.estimateBackup(id) }
        return BackupEstimate(
            dataBytes = maxOf(0L, estimate.data_bytes),
            freeBytes = maxOf(0L, estimate.free_bytes),
        )
    }

    override suspend fun backup(
        service: ManagedService,
        encrypt: Boolean?,
        passphrase: String?,
        onChunk: (String) -> Unit,
    ): BackupOutcome {
        val id = agentID(service)
        val encryption = when (encrypt) {
            null -> BackupEncryption.BACKUP_ENCRYPTION_UNSPECIFIED
            true -> BackupEncryption.BACKUP_ENCRYPTION_ENABLED
            false -> BackupEncryption.BACKUP_ENCRYPTION_DISABLED
        }
        val log = StringBuilder()
        var archive: BackupArchive? = null
        var backups: List<BackupEntry> = emptyList()
        var completed = false
        try {
            client.runBackup(id, encryption, passphrase.orEmpty()).collect { event ->
                when (event.phase) {
                    ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS -> {
                        val line = if (event.text.endsWith("\n")) event.text else event.text + "\n"
                        log.append(line)
                        onChunk(line)
                    }

                    ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED -> {
                        completed = true
                        event.archive?.let { archive = it }
                        event.backups?.let { list ->
                            backups = list.archives.map { entry(it, language) }
                        }
                    }

                    else -> Unit
                }
            }
        } catch (error: Throwable) {
            if (!completed) throw error
            throw AgentControlError.BackupFailed(AgentCommandRunner.asAgentError(error), backups)
        }
        val finished = archive
        return BackupOutcome(
            sizeBytes = finished?.let { maxOf(0L, it.size_bytes) },
            path = finished?.path,
            log = OutputTail.tail(log.toString()),
        )
    }

    override suspend fun deleteBackup(service: ManagedService, path: String) {
        val id = agentID(service)
        mapping { client.deleteBackup(id, path) }
    }

    // --------------------------------------------------------------- Helpers

    private fun agentID(service: ManagedService): String =
        AgentServiceMapping.agentID(service.id)
            ?: throw AgentControlError.UnsupportedService(service.displayName)

    private suspend fun <T> mapping(body: suspend () -> T): T =
        agentFailure("backup") { gate.gated(body) }

    companion object {
        internal fun entry(archive: BackupArchive, language: AppLanguage = AppLanguage.EN) =
            BackupEntry(
                name = archive.path,
                sizeText = sizeText(archive.size_bytes, archive.directory),
                dateText = dateText(archive.modified_at, language.locale),
                isDirectory = archive.directory,
                drive = archive.drive.ifEmpty { null },
                sizeBytes = if (archive.directory) null else archive.size_bytes,
                modifiedAtMillis = archive.modified_at.takeIf { it > 0 },
            )

        private fun sizeText(bytes: Long, directory: Boolean): String {
            if (directory) return "—"
            if (bytes < 1000) return "$bytes bytes"
            val units = listOf("kB", "MB", "GB", "TB", "PB")
            var value = bytes.toDouble() / 1000
            var unit = 0
            while (value >= 1000 && unit < units.lastIndex) {
                value /= 1000
                unit += 1
            }
            return String.format(Locale.ROOT, "%.1f %s", value, units[unit])
        }

        private fun dateText(millis: Long, locale: Locale): String {
            if (millis <= 0) return ""
            return DateTimeFormatter
                .ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
                .withLocale(locale)
                .withZone(ZoneId.systemDefault())
                .format(Instant.ofEpochMilli(millis))
        }
    }
}
