package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.BackupSpec
import com.skaymer.gryonixnexus.catalog.BackupWrapperSpec
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.RestoreSpec
import com.skaymer.gryonixnexus.catalog.ServiceActions
import com.skaymer.gryonixnexus.catalog.ServiceCommand
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.time.Duration
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/** Progress of the encrypted vaultwarden backup */
sealed class VWBackupEvent {
    data object StoppingContainer : VWBackupEvent()
    data object Archiving : VWBackupEvent()
    data object Encrypting : VWBackupEvent()
    data object StartingContainer : VWBackupEvent()
    data object Rotating : VWBackupEvent()

    /** Human-readable size of the resulting .gpg file */
    data class Completed(val sizeText: String) : VWBackupEvent()
}

class ServiceOperations(
    private val runner: SSHCommandRunner,
    private val deployment: Deployment,
    private val service: ManagedService,
    private val language: AppLanguage = AppLanguage.EN,
    /** Injected for deterministic archive names in tests */
    private val now: () -> Instant = { Instant.now() },
) {
    private val context: ServiceContext get() = deployment.serviceContext

    /** The machine THIS service runs on */
    private val host: SSHHostID get() = deployment.hostRunning(service.id)

    private val actions: ServiceActions get() = service.actions(context)

    private fun timeout(timeoutClass: ServiceCommand.TimeoutClass): Duration =
        deployment.timeouts.duration(timeoutClass)

    // ---------------------------------------------------------------- Status

    /** One row per container */
    suspend fun status(): List<ContainerStatus> {
        val probe = actions.statusProbe
        return when (probe) {
            is StatusProbe.ComposeProject -> {
                val output = runSucceeding(probe.list.command, timeout(ServiceCommand.TimeoutClass.QUICK))
                DockerComposePSParser.parse(output)
            }

            is StatusProbe.Container -> {
                val output = runSucceeding(probe.list.command, timeout(ServiceCommand.TimeoutClass.QUICK))
                val all = DockerPSParser.parse(output)
                DockerPSParser.find(probe.name, all)?.let { listOf(it) }
                    ?: listOf(ContainerStatus(probe.name, "not running"))
            }
        }
    }

    // ---------------------------------------------------------- Power/update

    val canRestart: Boolean get() = actions.restart != null
    val canStart: Boolean get() = actions.start != null
    val canStop: Boolean get() = actions.stop != null

    /** Can the dashboard update this service? */
    val canUpdate: Boolean
        get() = service.updateSpec(context).flavour == UpdateSpec.Flavour.COMPOSE_PULL

    /** Destructive: the UI confirms first */
    suspend fun restart() {
        val restart = actions.restart
            ?: throw ServerControlError.NotConfigured(
                L10nOperations.restartNotSupported(language, service.displayName),
            )
        runSucceeding(restart.command, timeout(restart.timeoutClass))
    }

    /** Brings every container of the service back up */
    suspend fun start() {
        val start = actions.start
            ?: throw ServerControlError.NotConfigured(
                L10nOperations.startNotSupported(language, service.displayName),
            )
        runSucceeding(start.command, timeout(start.timeoutClass))
    }

    /** Destructive: the service goes offline until it is started again */
    suspend fun stop() {
        val stop = actions.stop
            ?: throw ServerControlError.NotConfigured(
                L10nOperations.stopNotSupported(language, service.displayName),
            )
        runSucceeding(stop.command, timeout(stop.timeoutClass))
    }

    // ------------------------------------------------------------------ Logs

    val canReadLogs: Boolean get() = actions.logs != null

    /** The tail of this service's container log, as lines */
    suspend fun logs(): List<String> {
        val logs = actions.logs
            ?: throw ServerControlError.NotConfigured(
                L10nOperations.logsNotSupported(language, service.displayName),
            )
        val result = runner.run(logs.command, host, timeout(logs.timeoutClass))
        val combined = listOf(result.stdout, result.stderr)
            .filter { it.isNotEmpty() }
            .joinToString("\n")
        return ANSIStripper.strip(combined)
            .split("\n")
            .dropWhile { it.isBlank() }
            .dropLastWhile { it.isBlank() }
    }

    // ------------------------------------------------------------- Uninstall

    /** The wrapper's `case` label for this service */
    val uninstallTarget: String
        get() {
            if (service.id in ServiceID.VPN_PROTOCOLS || service.id == ServiceID.VPN_PANEL) {
                return CommandCatalog.Uninstall.VPN_TARGET
            }
            if (service.id == ServiceID.TAILSCALE_NODE) return ServiceID.HEADSCALE.rawValue
            return service.id.rawValue
        }

    suspend fun uninstall(purge: PurgeOptions, onChunk: (String) -> Unit = {}): String {
        val command = CommandCatalog.Uninstall.run(uninstallTarget, purge)
        val output = ANSIStripper.strip(
            runDetached(command, DetachedJobs.Kind.UNINSTALL, uninstallTarget,
                timeout(ServiceCommand.TimeoutClass.LONG), onChunk = onChunk),
        )
        if (!output.contains(CommandCatalog.Uninstall.DONE_MARKER)) {
            throw ServerControlError.commandFailure(command, null, OutputTail.tail(output))
        }
        return OutputTail.tail(output.replace(CommandCatalog.Uninstall.DONE_MARKER, ""))
    }

    // --------------------------------------------------------------- Backups

    enum class BackupKind {
        NONE,

        /** One-shot wrapper on the server; no client input needed */
        WRAPPER,

        /** Needs a user passphrase; runs the stop-tar-encrypt-start flow */
        ENCRYPTED,
    }

    val backupKind: BackupKind
        get() = when (actions.backup) {
            null -> BackupKind.NONE
            is BackupSpec.WrapperScript -> BackupKind.WRAPPER
            is BackupSpec.EncryptedVolume -> BackupKind.ENCRYPTED
        }

    private val backupListDir: String? get() = actions.backup?.listDirectory

    val backupWrapperSpec: BackupWrapperSpec? get() = actions.backup?.wrapper

    val backupEncryptsByDefault: Boolean get() = actions.backup?.encryptsByDefault ?: false

    suspend fun listBackups(): List<BackupEntry> {
        val dir = backupListDir ?: return emptyList()
        val command = when (actions.backup) {
            is BackupSpec.EncryptedVolume -> CommandCatalog.Backups.listVaultwarden(dir)
            else -> CommandCatalog.Backups.listMailcow(dir)
        }
        val result = runner.run(command, host, timeout(ServiceCommand.TimeoutClass.QUICK))
        return BackupListParser.parse(result.stdout)
            .filter { it.displayName != CommandCatalog.Restore.STAGING_DIRECTORY_NAME }
    }

    suspend fun latestShareableBackupPath(): String? {
        val dir = backupListDir ?: return null
        val result = runner.run(
            CommandCatalog.Backups.latestShareableFile(dir),
            host,
            timeout(ServiceCommand.TimeoutClass.QUICK),
        )
        return result.stdout.trim().ifEmpty { null }
    }

    /** Deletes one backup through the root-owned wrapper */
    suspend fun deleteBackup(path: String) {
        val dir = backupListDir
            ?: throw ServerControlError.NotConfigured(
                L10nOperations.backupKindNotSupported(language, service.displayName),
            )
        if (!CommandCatalog.Restore.isValidArchivePath(path, dir)) {
            throw ServerControlError.NotConfigured(L10nOperations.restoreBadPath(language, path))
        }
        val output = runSucceeding(
            CommandCatalog.Backups.delete(path),
            timeout(ServiceCommand.TimeoutClass.QUICK),
        )
        if (!output.contains(CommandCatalog.Backups.CONTROL_DONE_MARKER)) {
            throw ServerControlError.commandFailure("delete backup", null, OutputTail.tail(output))
        }
    }

    /** Absolute path of a listed backup */
    fun backupPath(entry: BackupEntry): String? {
        val dir = backupListDir ?: return null
        return if (entry.name.startsWith("/")) entry.name else "$dir/${entry.name}"
    }

    suspend fun estimateBackup(): BackupEstimate? {
        val spec = backupWrapperSpec ?: return null
        val result = runner.run(
            CommandCatalog.Backups.estimate(spec.wrapperTarget),
            host,
            timeout(ServiceCommand.TimeoutClass.QUICK),
        )
        if (!result.succeeded) {
            throw ServerControlError.commandFailure("estimate backup", result.exitCode, result.stderr)
        }
        return BackupEstimate.parse(result.stdout)
    }

    suspend fun backup(
        encrypt: Boolean? = null,
        passphrase: String? = null,
        onChunk: (String) -> Unit = {},
    ): BackupOutcome {
        val spec = backupWrapperSpec ?: return encryptedVolumeBackup(passphrase, onChunk)
        val encrypting = encrypt ?: spec.encryptsByDefault
        val secret = if (encrypting && !passphrase.isNullOrEmpty()) passphrase else null
        return wrapperBackup(spec.wrapperTarget, spec.backupDir, encrypting, secret, spec.run.timeoutClass, onChunk)
    }

    /** A typed password encrypts here; without one, the stored key */
    private suspend fun encryptedVolumeBackup(passphrase: String?, onChunk: (String) -> Unit): BackupOutcome {
        val spec = actions.backup as? BackupSpec.EncryptedVolume
        val target = actions.restore?.wrapperTarget
        if (spec == null || target == null) {
            throw ServerControlError.NotConfigured(L10nOperations.backupKindNotSupported(language, service.displayName))
        }
        if (passphrase.isNullOrEmpty()) {
            return wrapperBackup(target, spec.backupDir, true, null, ServiceCommand.TimeoutClass.LONG, onChunk)
        }
        var size = ""
        encryptedBackup(passphrase).collect { if (it is VWBackupEvent.Completed) size = it.sizeText }
        return BackupOutcome(sizeBytes = null, path = null, log = size)
    }

    private suspend fun wrapperBackup(
        target: String,
        backupDir: String,
        encrypting: Boolean,
        secret: String?,
        timeoutClass: ServiceCommand.TimeoutClass,
        onChunk: (String) -> Unit,
    ): BackupOutcome {
        runner.run(CommandCatalog.Backups.makeDir(backupDir), host, timeout(ServiceCommand.TimeoutClass.QUICK))
        val command = CommandCatalog.Backups.run(target, encrypting)
        val output = ANSIStripper.strip(
            runDetached(command, DetachedJobs.Kind.BACKUP, target, timeout(timeoutClass), secret, onChunk),
        )
        if (!output.contains(CommandCatalog.Backups.CONTROL_DONE_MARKER)) {
            throw ServerControlError.commandFailure("backup $target", null, OutputTail.tail(output))
        }
        val log = OutputTail.tail(output.replace(CommandCatalog.Backups.CONTROL_DONE_MARKER, ""))
        BackupOutcome.parse(output, log)?.let { return it }
        val size = runner.run(
            CommandCatalog.Backups.latestEntrySize(backupDir),
            host,
            timeout(ServiceCommand.TimeoutClass.QUICK),
        )
        return BackupOutcome(sizeBytes = null, path = null, log = size.stdout.trim())
    }

    /** Wrapper-script backup with the spec's own encryption default */
    suspend fun runWrapperBackup(): String = backup().log

    fun encryptedBackup(passphrase: String): Flow<VWBackupEvent> = flow {
        performEncryptedBackup(passphrase) { emit(it) }
    }

    private suspend fun performEncryptedBackup(
        passphrase: String,
        yield: suspend (VWBackupEvent) -> Unit,
    ) {
        val spec = actions.backup as? BackupSpec.EncryptedVolume
            ?: throw ServerControlError.NotConfigured(
                L10nOperations.encryptedBackupNotSupported(language, service.displayName),
            )
        val stagingPath = BackupSpec.stagingArchivePath(spec.backupDir, spec.container)
        val gpgPath = "${spec.backupDir}/${spec.container}-${timestamp(now())}.tar.gz.gpg"

        runner.run(
            CommandCatalog.Backups.makeDir(spec.backupDir),
            host,
            timeout(ServiceCommand.TimeoutClass.QUICK),
        )

        yield(VWBackupEvent.StoppingContainer)
        step("stop container", spec.stopStart.stop.command, timeout(ServiceCommand.TimeoutClass.RESTART))

        try {
            yield(VWBackupEvent.Archiving)
            step(
                "archive data",
                CommandCatalog.Vaultwarden.archive(spec.dataPath, stagingPath),
                timeout(ServiceCommand.TimeoutClass.LONG),
            )
            step(
                "chown archive",
                CommandCatalog.Vaultwarden.chownArchive(deployment.entry.user, stagingPath),
                timeout(ServiceCommand.TimeoutClass.QUICK),
            )

            yield(VWBackupEvent.Encrypting)
            val encrypted = runner.run(
                CommandCatalog.Vaultwarden.encrypt(stagingPath, gpgPath),
                passphrase,
                host,
                timeout(ServiceCommand.TimeoutClass.LONG),
            )
            check(encrypted, "encrypt archive", "encrypt archive", sensitive = true)
            step(
                "remove plain archive",
                CommandCatalog.Vaultwarden.removePlainArchive(stagingPath),
                timeout(ServiceCommand.TimeoutClass.QUICK),
            )
        } catch (error: Throwable) {
            runCatching {
                runner.run(
                    CommandCatalog.Vaultwarden.removePlainArchive(stagingPath),
                    host,
                    timeout(ServiceCommand.TimeoutClass.QUICK),
                )
            }
            yield(VWBackupEvent.StartingContainer)
            runCatching {
                runner.run(
                    spec.stopStart.start.command,
                    host,
                    timeout(ServiceCommand.TimeoutClass.RESTART),
                )
            }
            throw error
        }

        yield(VWBackupEvent.StartingContainer)
        step("start container", spec.stopStart.start.command, timeout(ServiceCommand.TimeoutClass.RESTART))

        val size = runner.run(
            CommandCatalog.Vaultwarden.backupSize(gpgPath),
            host,
            timeout(ServiceCommand.TimeoutClass.QUICK),
        )

        yield(VWBackupEvent.Rotating)
        runner.run(
            CommandCatalog.Vaultwarden.rotate(spec.backupDir, context.settings.backupRetention),
            host,
            timeout(ServiceCommand.TimeoutClass.QUICK),
        )

        yield(VWBackupEvent.Completed(size.stdout.trim()))
    }

    // --------------------------------------------------------------- Restore

    val restoreSpec: RestoreSpec? get() = actions.restore

    /** Backups on the server that can be restored, newest first */
    suspend fun listRestorableBackups(): List<BackupEntry> {
        if (actions.restore == null) return emptyList()
        return listBackups()
    }

    suspend fun uploadBackup(
        data: ByteArray,
        fileName: String,
        browser: RemoteFileBrowser,
        maxBytes: Long = UPLOAD_LIMIT_BYTES,
    ): String {
        val restore = actions.restore
            ?: throw ServerControlError.NotConfigured(
                L10nOperations.restoreNotSupported(language, service.displayName),
            )
        if (data.size > maxBytes) {
            throw ServerControlError.FileTooLarge(fileName, data.size.toLong(), maxBytes)
        }
        val safeName = sanitizedUploadName(fileName)
        val directory = CommandCatalog.Restore.stagingDirectory(restore.backupDir)
        runner.run(
            CommandCatalog.Backups.makeDir(directory),
            host,
            timeout(ServiceCommand.TimeoutClass.QUICK),
        )
        val path = "$directory/$safeName"
        browser.uploadFile(data, path, host)
        return path
    }

    /** Restores this service from [archivePath] on the server */
    suspend fun restore(
        archivePath: String,
        passphrase: String? = null,
        onChunk: (String) -> Unit = {},
    ): String {
        val restore = actions.restore
            ?: throw ServerControlError.NotConfigured(
                L10nOperations.restoreNotSupported(language, service.displayName),
            )
        if (!CommandCatalog.Restore.isValidArchivePath(archivePath, restore.backupDir)) {
            throw ServerControlError.NotConfigured(
                L10nOperations.restoreBadPath(language, archivePath),
            )
        }
        val target = restore.wrapperTarget
        if (!CommandCatalog.Restore.isValidTarget(target)) {
            throw ServerControlError.NotConfigured(
                L10nOperations.restoreNotSupported(language, service.displayName),
            )
        }
        val command = CommandCatalog.Restore.run(target, archivePath)
        var restoreSecret: String? = null
        if (restore.needsPassphrase(archivePath)) {
            if (passphrase.isNullOrEmpty()) {
                throw ServerControlError.NotConfigured(
                    L10nOperations.restoreNeedsPassphrase(language, service.displayName),
                )
            }
            restoreSecret = passphrase
        }

        val output = ANSIStripper.strip(
            runDetached(command, DetachedJobs.Kind.RESTORE, restore.wrapperTarget,
                timeout(ServiceCommand.TimeoutClass.LONG), restoreSecret, onChunk),
        )
        if (!output.contains(CommandCatalog.Restore.DONE_MARKER)) {
            throw ServerControlError.commandFailure(
                "restore $target",
                null,
                OutputTail.tail(output),
            )
        }
        return OutputTail.tail(output.replace(CommandCatalog.Restore.DONE_MARKER, ""))
    }

    // --------------------------------------------------------------- Helpers

    private suspend fun runSucceeding(command: String, timeout: Duration): String {
        val result = runner.run(command, host, timeout)
        if (!result.succeeded) {
            throw ServerControlError.commandFailure(command, result.exitCode, result.stderr)
        }
        return result.stdout
    }

    private suspend fun runDetached(
        command: String,
        kind: DetachedJobs.Kind,
        subject: String,
        timeout: Duration,
        secret: String? = null,
        onChunk: (String) -> Unit,
    ): String {
        val id = DetachedJobs.jobID(kind, subject, System.currentTimeMillis() / 1000)
        val quick = timeout(ServiceCommand.TimeoutClass.QUICK)
        if (secret == null) {
            runner.run(DetachedJobs.startCommand(command, id), host, quick)
        } else {
            runner.run(DetachedJobs.startCommandWithSecret(command, id), secret, host, quick)
        }
        val followed = DetachedJobs.follow(runner, host, id, timeout, onChunk = onChunk)
        val code = followed.exitCode ?: throw ServerControlError.commandFailure(
            id, null, OutputTail.tail(followed.output))
        if (code != 0) {
            throw ServerControlError.commandFailure(id, code, OutputTail.tail(followed.output))
        }
        return followed.output
    }

    private suspend fun collectStream(
        command: String,
        timeout: Duration,
        onChunk: (String) -> Unit,
    ): String {
        val accumulated = StringBuilder()
        runner.stream(command, host, timeout).collect { chunk ->
            accumulated.append(chunk.text)
            onChunk(chunk.text)
        }
        return accumulated.toString()
    }

    private suspend fun step(
        label: String,
        command: String,
        timeout: Duration,
        sensitive: Boolean = false,
    ) {
        check(runner.run(command, host, timeout), label, command, sensitive)
    }

    private fun check(result: ExecResult, label: String, command: String, sensitive: Boolean) {
        if (result.succeeded) return
        if (ServerControlError.stderrAsksForASudoPassword(result.stderr)) {
            throw ServerControlError.SudoPasswordRequired(if (sensitive) label else command)
        }
        throw ServerControlError.CommandFailed(
            if (sensitive) label else command,
            result.exitCode,
            if (sensitive) "" else result.stderr,
        )
    }

    companion object {
        const val UPLOAD_LIMIT_BYTES = 512L * 1_048_576

        private val TIMESTAMP: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss", Locale.ROOT).withZone(ZoneOffset.UTC)

        internal fun timestamp(instant: Instant): String = TIMESTAMP.format(instant)

        internal fun sanitizedUploadName(name: String): String {
            val base = name.split("/").lastOrNull()?.takeIf { it.isNotEmpty() } ?: name
            val allowed = base.filter { it.code < 128 && (it.isLetter() || it.isDigit() || it in "._-") }
            val cleaned = allowed.replace("..", ".")
            return cleaned.ifEmpty { "upload.tar.gz" }
        }
    }
}
