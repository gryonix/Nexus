package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceCommand

/** The unattended backup schedule as it exists on the server */
data class AutoBackupSettings(
    val schedule: CommandCatalog.Backups.Schedule = CommandCatalog.Backups.Schedule.Off,
    /** How many backups of each service to keep */
    val retention: Int = 7,
    /** Services the timer backs up, by `ServiceID` raw value */
    val services: Set<String> = emptySet(),
) {
    val isOn: Boolean get() = schedule != CommandCatalog.Backups.Schedule.Off
}

interface AutoBackupManaging {
    /** The stored schedule, or "off" when unset or unreadable */
    suspend fun load(): AutoBackupSettings

    /** Writes a new schedule */
    suspend fun save(settings: AutoBackupSettings, passphrase: String? = null)

    suspend fun loadDestination(): BackupDestinationState

    /** [secret] null or empty means "keep whatever is stored" */
    suspend fun saveDestination(settings: BackupDestinationSettings, secret: String? = null)

    suspend fun testDestination(): BackupDestinationTestResult

    /** USB drive settings and state from the services machine */
    suspend fun loadDrives(): BackupDrivesState

    suspend fun saveDrives(settings: BackupDriveSettings)
}

/** Which implementation a deployment's BACKUP SCHEDULE goes through */
object AutoBackupRouting {
    fun route(usesAgent: Boolean, agentTransportAvailable: Boolean): ServiceControlRoute =
        ServiceControlRouting.route(usesAgent, agentTransportAvailable)
}

class AutoBackupOperations(
    private val runner: SSHCommandRunner,
    private val deployment: Deployment,
) : AutoBackupManaging {
    private val hosts: List<SSHHostID> get() = deployment.workerHosts

    override suspend fun load(): AutoBackupSettings {
        val found = mutableListOf<AutoBackupSettings>()
        for (host in hosts) {
            val result = runner.run(
                CommandCatalog.Backups.READ_SCHEDULE,
                host,
                deployment.timeouts.duration(ServiceCommand.TimeoutClass.QUICK),
            )
            found += parse(result.stdout)
        }
        return merged(found)
    }

    /** Writes the schedule */
    override suspend fun save(settings: AutoBackupSettings, passphrase: String?) {
        for (host in hosts) save(settings, passphrase, host)
    }

    /** One machine's copy */
    private suspend fun save(
        settings: AutoBackupSettings,
        passphrase: String?,
        host: SSHHostID,
    ) {
        if (!passphrase.isNullOrEmpty()) {
            val result = runner.run(
                CommandCatalog.Backups.SET_PASSPHRASE,
                passphrase,
                host,
                deployment.timeouts.duration(ServiceCommand.TimeoutClass.QUICK),
            )
            if (!result.succeeded) {
                throw ServerControlError.commandFailure("set backup passphrase", result.exitCode, "")
            }
        }
        val command = CommandCatalog.Backups.setSchedule(
            settings.schedule,
            settings.retention,
            settings.services.sorted(),
        )
        val result = runner.run(
            command,
            host,
            deployment.timeouts.duration(ServiceCommand.TimeoutClass.QUICK),
        )
        if (!result.succeeded) {
            throw ServerControlError.commandFailure(command, result.exitCode, result.stderr)
        }
        if (!result.stdout.contains(CommandCatalog.Backups.CONTROL_DONE_MARKER)) {
            throw ServerControlError.commandFailure(command, null, OutputTail.tail(result.stdout))
        }
    }

    override suspend fun loadDestination(): BackupDestinationState {
        val host = hosts.firstOrNull() ?: return BackupDestinationState()
        val result = runner.run(
            CommandCatalog.Backups.SHOW_DESTINATION,
            host,
            deployment.timeouts.duration(ServiceCommand.TimeoutClass.QUICK),
        )
        if (!result.succeeded) return BackupDestinationState()
        return BackupDestinationParsing.parse(result.stdout)
    }

    override suspend fun saveDestination(settings: BackupDestinationSettings, secret: String?) {
        for (host in hosts) saveDestination(settings, secret, host)
    }

    private suspend fun saveDestination(
        settings: BackupDestinationSettings,
        secret: String?,
        host: SSHHostID,
    ) {
        val command = CommandCatalog.Backups.setDestination(
            kind = settings.kind.wire,
            host = settings.host.trim(),
            port = settings.port,
            user = settings.user.trim(),
            path = settings.path.trim(),
            bucket = settings.bucket.trim(),
            keep = settings.keep,
        )
        val timeout = deployment.timeouts.duration(ServiceCommand.TimeoutClass.QUICK)
        val result = if (!secret.isNullOrEmpty()) {
            runner.run(command, secret, host, timeout)
        } else {
            runner.run(command, host, timeout)
        }
        if (!result.succeeded) {
            if (result.stderr.contains(UNSUPPORTED_ACTION)) {
                throw ServerControlError.NotConfigured(
                    "this server's backup wrapper is older than backup destinations — " +
                        "run Repair server on it, then set the destination again",
                )
            }
            throw ServerControlError.commandFailure(
                "set backup destination",
                result.exitCode,
                result.stderr,
            )
        }
    }

    override suspend fun testDestination(): BackupDestinationTestResult {
        val host = hosts.firstOrNull() ?: return BackupDestinationTestResult(false)
        val result = runner.run(
            CommandCatalog.Backups.TEST_DESTINATION,
            host,
            deployment.timeouts.duration(ServiceCommand.TimeoutClass.LONG),
        )
        if (result.stderr.contains(UNSUPPORTED_ACTION)) {
            return BackupDestinationTestResult(
                succeeded = false,
                detail = "this server's backup wrapper is older than backup destinations — " +
                    "run Repair server on it first",
            )
        }
        return BackupDestinationParsing.parseTest(result.stdout, result.stderr)
    }

    override suspend fun loadDrives(): BackupDrivesState {
        val host = hosts.firstOrNull() ?: return BackupDrivesState(supported = false)
        val result = runner.run(
            CommandCatalog.Backups.SHOW_DRIVES,
            host,
            deployment.timeouts.duration(ServiceCommand.TimeoutClass.QUICK),
        )
        if (!result.succeeded) {
            if (result.stderr.contains(UNSUPPORTED_ACTION)) return BackupDrivesState(supported = false)
            throw ServerControlError.commandFailure("show backup drives", result.exitCode, result.stderr)
        }
        return BackupDrivesParsing.parse(result.stdout)
    }

    override suspend fun saveDrives(settings: BackupDriveSettings) {
        val host = hosts.firstOrNull() ?: return
        val command = CommandCatalog.Backups.setDrives(settings.mode.wire, settings.encrypt, settings.uuids)
        val result = runner.run(command, host, deployment.timeouts.duration(ServiceCommand.TimeoutClass.QUICK))
        if (result.succeeded) return
        if (result.stderr.contains(UNSUPPORTED_ACTION)) {
            throw ServerControlError.NotConfigured(
                "this server's backup wrapper is older than USB drives — run Repair server on it first",
            )
        }
        throw ServerControlError.commandFailure("set backup drives", result.exitCode, result.stderr)
    }

    companion object {
        internal const val UNSUPPORTED_ACTION = "unsupported action:"

        /** One answer out of one per machine */
        internal fun merged(settings: List<AutoBackupSettings>): AutoBackupSettings =
            AutoBackupSettings(
                schedule = settings.firstOrNull { it.schedule != CommandCatalog.Backups.Schedule.Off }
                    ?.schedule ?: CommandCatalog.Backups.Schedule.Off,
                retention = settings.map { it.retention }.maxOrNull()
                    ?: AutoBackupSettings().retention,
                services = settings.fold(emptySet()) { acc, one -> acc + one.services },
            )

        /** Parses the wrapper's shell-style config */
        fun parse(output: String): AutoBackupSettings {
            var schedule = CommandCatalog.Backups.Schedule.Off as CommandCatalog.Backups.Schedule
            var retention = AutoBackupSettings().retention
            var services: Set<String> = emptySet()
            for (line in output.split("\n")) {
                val parts = line.split("=", limit = 2)
                if (parts.size != 2) continue
                val value = parts[1].trim('\'', '"', ' ')
                when (parts[0].trim()) {
                    "SCHEDULE" -> schedule = CommandCatalog.Backups.Schedule.fromWrapperArgument(value)
                    "RETENTION" -> value.toIntOrNull()?.let { if (it >= 1) retention = it }
                    "SERVICES" -> services = value.split(" ").filter { it.isNotEmpty() }.toSet()
                }
            }
            return AutoBackupSettings(schedule, retention, services)
        }
    }
}
