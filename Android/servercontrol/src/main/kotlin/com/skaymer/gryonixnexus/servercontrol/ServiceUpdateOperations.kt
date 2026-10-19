package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceCommand
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceUpdateStatus
import java.time.Instant
import java.time.format.DateTimeParseException

data class AutoUpdateSettings(
    val schedule: CommandCatalog.Backups.Schedule = CommandCatalog.Backups.Schedule.Off,
    /** Services the timer updates, by [ServiceID] raw value */
    val services: Set<String> = emptySet(),
) {
    val isOn: Boolean get() = schedule != CommandCatalog.Backups.Schedule.Off
}

data class ServiceUpdateReport(val service: ServiceID, val status: ServiceUpdateStatus)

data class ServiceUpdateRunRecord(val service: ServiceID, val outcome: Outcome) {
    sealed class Outcome {
        data object Updated : Outcome()
        data class RolledBack(val reason: String) : Outcome()
        data class Failed(val reason: String) : Outcome()
    }
}

data class ServiceUpdateRunLog(
    val lastRun: Instant?,
    val records: List<ServiceUpdateRunRecord>,
) {
    val isEmpty: Boolean get() = lastRun == null && records.isEmpty()
}

interface ServiceUpdateManaging {
    suspend fun check(): List<ServiceUpdateReport>

    /** Applies one service's update, streaming output as it arrives */
    suspend fun run(service: ServiceID, onChunk: (String) -> Unit = {}): ServiceUpdateRunRecord

    /** The stored schedule, or "off" when unset or unreadable */
    suspend fun loadSchedule(): AutoUpdateSettings

    /** What the last scheduled (or manual) run left behind */
    suspend fun loadStatus(): ServiceUpdateRunLog

    /** Writes a new schedule */
    suspend fun save(settings: AutoUpdateSettings)
}

/** Which implementation a deployment's UPDATES go through */
object ServiceUpdateRouting {
    fun route(usesAgent: Boolean, agentTransportAvailable: Boolean): ServiceControlRoute =
        ServiceControlRouting.route(usesAgent, agentTransportAvailable)
}

/** Reads update status and drives the update wrapper */
class ServiceUpdateOperations(
    private val runner: SSHCommandRunner,
    private val deployment: Deployment,
) : ServiceUpdateManaging {
    private val hosts: List<SSHHostID> get() = deployment.workerHosts

    override suspend fun check(): List<ServiceUpdateReport> {
        val outputs = mutableListOf<String>()
        for (host in hosts) {
            val result = runner.run(
                CommandCatalog.Updates.check(null),
                host,
                deployment.timeouts.duration(ServiceCommand.TimeoutClass.LONG),
            )
            outputs += result.stdout
        }
        return parseCheck(outputs.joinToString("\n"))
    }

    override suspend fun run(service: ServiceID, onChunk: (String) -> Unit): ServiceUpdateRunRecord {
        val command = CommandCatalog.Updates.run(service.rawValue)
        val host = deployment.hostRunning(service)
        val id = DetachedJobs.jobID(
            DetachedJobs.Kind.UPDATE, service.rawValue, System.currentTimeMillis() / 1000)
        runner.run(
            DetachedJobs.startCommand(command, id), host,
            deployment.timeouts.duration(ServiceCommand.TimeoutClass.QUICK),
        )
        val followed = DetachedJobs.follow(
            runner, host, id, deployment.timeouts.duration(ServiceCommand.TimeoutClass.LONG),
            onChunk = onChunk,
        )
        if (followed.exitCode == null) {
            throw ServerControlError.commandFailure(id, null, OutputTail.tail(followed.output))
        }
        val output = ANSIStripper.strip(followed.output)
        return parseStatus(output).records.firstOrNull()
            ?: throw ServerControlError.commandFailure(command, null, OutputTail.tail(output))
    }

    override suspend fun loadSchedule(): AutoUpdateSettings {
        val found = mutableListOf<AutoUpdateSettings>()
        for (host in hosts) {
            val result = runner.run(
                CommandCatalog.Updates.READ_SCHEDULE,
                host,
                deployment.timeouts.duration(ServiceCommand.TimeoutClass.QUICK),
            )
            found += parseSchedule(result.stdout)
        }
        return merged(found)
    }

    /** What the last scheduled run did */
    override suspend fun loadStatus(): ServiceUpdateRunLog {
        val logs = mutableListOf<ServiceUpdateRunLog>()
        for (host in hosts) {
            val result = runner.run(
                CommandCatalog.Updates.READ_STATUS,
                host,
                deployment.timeouts.duration(ServiceCommand.TimeoutClass.QUICK),
            )
            logs += parseStatus(result.stdout)
        }
        return ServiceUpdateRunLog(
            lastRun = logs.mapNotNull { it.lastRun }.maxOrNull(),
            records = logs.flatMap { it.records },
        )
    }

    override suspend fun save(settings: AutoUpdateSettings) {
        for (host in hosts) save(settings, host)
    }

    private suspend fun save(settings: AutoUpdateSettings, host: SSHHostID) {
        val command = CommandCatalog.Updates.setSchedule(
            settings.schedule,
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
        if (!result.stdout.contains(CommandCatalog.Updates.DONE_MARKER)) {
            throw ServerControlError.commandFailure(command, null, OutputTail.tail(result.stdout))
        }
    }

    companion object {
        /** One answer out of one per machine */
        internal fun merged(settings: List<AutoUpdateSettings>): AutoUpdateSettings =
            AutoUpdateSettings(
                schedule = settings.firstOrNull { it.schedule != CommandCatalog.Backups.Schedule.Off }
                    ?.schedule ?: CommandCatalog.Backups.Schedule.Off,
                services = settings.fold(emptySet()) { acc, one -> acc + one.services },
            )

        /** Parses the wrapper's markers */
        fun parseCheck(output: String): List<ServiceUpdateReport> {
            val available = mutableMapOf<ServiceID, MutableList<String>>()
            val settled = mutableMapOf<ServiceID, ServiceUpdateStatus>()
            val order = mutableListOf<ServiceID>()

            fun note(id: ServiceID) {
                if (id !in order) order += id
            }

            for (rawLine in output.split("\n")) {
                val fields = rawLine.split(" ").filter { it.isNotEmpty() }
                if (fields.size < 2) continue
                val id = ServiceID(fields[1])
                when (fields[0]) {
                    CommandCatalog.Updates.AVAILABLE_MARKER -> {
                        if (fields.size < 3) continue
                        note(id)
                        available.getOrPut(id) { mutableListOf() } += fields[2]
                    }
                    CommandCatalog.Updates.CURRENT_MARKER -> {
                        note(id)
                        settled[id] = ServiceUpdateStatus.Current
                    }
                    CommandCatalog.Updates.UNKNOWN_MARKER -> {
                        note(id)
                        settled[id] = ServiceUpdateStatus.Unknown
                    }
                }
            }

            return order.map { id ->
                val images = available[id]
                if (images != null) {
                    ServiceUpdateReport(id, ServiceUpdateStatus.Available(images))
                } else {
                    ServiceUpdateReport(id, settled[id] ?: ServiceUpdateStatus.Unknown)
                }
            }
        }

        /** `KEY=value` lines, the same shape the backup schedule uses */
        fun parseSchedule(text: String): AutoUpdateSettings {
            var schedule = CommandCatalog.Backups.Schedule.Off as CommandCatalog.Backups.Schedule
            var services: Set<String> = emptySet()
            for (rawLine in text.split("\n")) {
                val line = rawLine.trim()
                val separator = line.indexOf('=')
                if (separator < 0) continue
                val key = line.substring(0, separator)
                val value = line.substring(separator + 1).trim('"', '\'')
                when (key) {
                    "SCHEDULE" -> schedule = CommandCatalog.Backups.Schedule.fromWrapperArgument(value)
                    "SERVICES" -> services = value.split(" ").filter { it.isNotEmpty() }.toSet()
                }
            }
            return AutoUpdateSettings(schedule, services)
        }

        /** Parses the status file's marker lines only, in file order */
        fun parseStatus(text: String): ServiceUpdateRunLog {
            var lastRun: Instant? = null
            val records = mutableListOf<ServiceUpdateRunRecord>()

            for (rawLine in text.split("\n")) {
                val fields = rawLine.split(" ").filter { it.isNotEmpty() }
                val marker = fields.firstOrNull() ?: continue
                when (marker) {
                    "last-run" -> {
                        if (fields.size < 2) continue
                        lastRun = try {
                            Instant.parse(fields[1])
                        } catch (_: DateTimeParseException) {
                            lastRun
                        }
                    }
                    CommandCatalog.Updates.UPDATED_MARKER -> {
                        if (fields.size < 2) continue
                        records += ServiceUpdateRunRecord(
                            ServiceID(fields[1]),
                            ServiceUpdateRunRecord.Outcome.Updated,
                        )
                    }
                    CommandCatalog.Updates.ROLLED_BACK_MARKER -> {
                        if (fields.size < 2) continue
                        records += ServiceUpdateRunRecord(
                            ServiceID(fields[1]),
                            ServiceUpdateRunRecord.Outcome.RolledBack(
                                fields.drop(2).joinToString(" "),
                            ),
                        )
                    }
                    CommandCatalog.Updates.FAILED_MARKER -> {
                        if (fields.size < 2) continue
                        records += ServiceUpdateRunRecord(
                            ServiceID(fields[1]),
                            ServiceUpdateRunRecord.Outcome.Failed(fields.drop(2).joinToString(" ")),
                        )
                    }
                }
            }

            return ServiceUpdateRunLog(lastRun, records)
        }
    }
}
