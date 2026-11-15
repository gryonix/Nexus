package com.skaymer.gryonixnexus.servercontrol

import kotlin.time.Duration.Companion.seconds

/** The server's own packages: last run, log and start-up switches */
data class SystemUpdateStatus(
    val isRunning: Boolean = false,
    /** Exit code of the last run, null before any */
    val exitCode: Int? = null,
    /** Seconds since 1970 when the last run ended */
    val finished: Long? = null,
    val needsRestart: Boolean = false,
    val systemAtStart: Boolean = false,
    val appsAtStart: Boolean = false,
    val systemAtStop: Boolean = false,
    val appsAtStop: Boolean = false,
    /** The updater on the host knows the shutdown switches */
    val offersAtStop: Boolean = false,
    /** All swap the machine has */
    val swapBytes: Long = 0,
    /** The part that is the app's own swap file */
    val swapFileBytes: Long = 0,
    /** The system's own timer; null when the updater predates it */
    val schedule: CommandCatalog.Backups.Schedule? = null,
    /** The host's reboot timer; null when the updater predates it */
    val rebootSchedule: RebootSchedule? = null,
    val log: List<String> = emptyList(),
) {
    companion object {
        /** Reads `gryonixnexus-system-ctl.sh status` */
        fun parse(output: String): SystemUpdateStatus? {
            val marker = output.indexOf("log:")
            if (marker < 0) return null
            val fields = output.substring(0, marker).lines().mapNotNull { line ->
                val equals = line.indexOf('=')
                if (equals < 0) null else line.substring(0, equals) to line.substring(equals + 1)
            }.toMap()
            val log = output.substring(marker + "log:".length).lines()
                .filter { it.isNotEmpty() && !it.startsWith(SystemUpdate.EXIT_MARKER) }
            return SystemUpdateStatus(
                isRunning = fields["state"] == "running",
                exitCode = fields["exit"]?.toIntOrNull(),
                finished = fields["finished"]?.toLongOrNull()?.takeIf { it > 0 },
                needsRestart = fields["reboot"] == "yes",
                systemAtStart = fields["system"] == "on",
                appsAtStart = fields["apps"] == "on",
                systemAtStop = fields["system_stop"] == "on",
                appsAtStop = fields["apps_stop"] == "on",
                offersAtStop = "system_stop" in fields || "apps_stop" in fields,
                swapBytes = fields["swap"]?.toLongOrNull() ?: 0,
                swapFileBytes = fields["swapfile"]?.toLongOrNull() ?: 0,
                schedule = fields["schedule"]?.let { CommandCatalog.Backups.Schedule.fromWrapperArgument(it) },
                rebootSchedule = fields["reboot_schedule"]?.let { RebootSchedule.fromWrapperArgument(it) },
                log = log,
            )
        }
    }
}

/** When the host restarts by itself */
sealed class RebootSchedule {
    abstract val wrapperArgument: String

    /** Hour and minute of the restart, 04:00 when off */
    fun timeOfDay(): Pair<Int, Int> = when (this) {
        Off -> 4 to 0
        is Daily -> hour to minute
        is Weekly -> hour to minute
    }

    fun at(hour: Int, minute: Int): RebootSchedule = when (this) {
        Off -> Off
        is Daily -> copy(hour = hour, minute = minute)
        is Weekly -> copy(hour = hour, minute = minute)
    }

    object Off : RebootSchedule() {
        override val wrapperArgument = "off"
    }

    data class Daily(val hour: Int, val minute: Int) : RebootSchedule() {
        override val wrapperArgument get() = "daily@${clock(hour, minute)}"
    }

    /** Weekday 1 is Monday, 7 is Sunday */
    data class Weekly(val weekday: Int, val hour: Int, val minute: Int) : RebootSchedule() {
        override val wrapperArgument get() = "weekly:$weekday@${clock(hour, minute)}"
    }

    companion object {
        fun fromWrapperArgument(value: String): RebootSchedule? {
            if (value == "off") return Off
            val head = value.substringBefore('@')
            val time = value.substringAfter('@', "").split(":").mapNotNull { it.toIntOrNull() }
            if (time.size != 2 || time[0] !in 0..23 || time[1] !in 0..59) return null
            if (head == "daily") return Daily(time[0], time[1])
            val day = head.removePrefix("weekly:").toIntOrNull()
            return if (head.startsWith("weekly:") && day != null && day in 1..7) Weekly(day, time[0], time[1]) else null
        }

        private fun clock(hour: Int, minute: Int) =
            String.format(java.util.Locale.ROOT, "%02d:%02d", hour.coerceIn(0, 23), minute.coerceIn(0, 59))
    }
}

/** What the agent accepts as a machine's host name */
object HostNameRules {
    fun isValid(name: String): Boolean =
        name.length in 1..63 && !name.startsWith("-") && !name.endsWith("-") &&
            name.all { it in 'a'..'z' || it in '0'..'9' || it == '-' }
}

/** Commands for the updater the agent puts on each host */
object SystemUpdate {
    const val SCRIPT_PATH = "/opt/gryonixnexus-system-ctl.sh"
    internal const val EXIT_MARKER = "GRYONIXNEXUS_SYSTEM_EXIT:"

    /** What updates when the machine starts */
    enum class Part(val raw: String) { SYSTEM("system"), APPS("apps") }

    const val STATUS_COMMAND = "sudo -n $SCRIPT_PATH status"
    const val START_COMMAND = "sudo -n $SCRIPT_PATH start"

    fun atStartCommand(part: Part, on: Boolean): String =
        "sudo -n $SCRIPT_PATH at-start ${part.raw} ${if (on) "on" else "off"}"

    fun atStopCommand(part: Part, on: Boolean): String =
        "sudo -n $SCRIPT_PATH at-stop ${part.raw} ${if (on) "on" else "off"}"

    fun scheduleCommand(schedule: CommandCatalog.Backups.Schedule): String =
        "sudo -n $SCRIPT_PATH schedule ${schedule.wrapperArgument}"

    fun rebootScheduleCommand(schedule: RebootSchedule): String =
        "sudo -n $SCRIPT_PATH reboot-schedule ${schedule.wrapperArgument}"

    /** A swap file of `sizeGB`, or none when null */
    fun swapCommand(sizeGB: Int?): String = "sudo -n $SCRIPT_PATH swap ${sizeGB?.toString() ?: "off"}"

    /** Whether the host lacks the updater or its grant */
    fun isMissing(result: ExecResult): Boolean =
        ServerControlError.stderrAsksForASudoPassword(result.stderr) ||
            result.stderr.contains("command not found") ||
            result.stderr.contains("No such file") ||
            DENIED_BY_SUDO.any { result.stderr.contains(it) }

    /** sudo's ways of saying the grant is not there */
    private val DENIED_BY_SUDO = listOf(
        "I'm afraid I can't do that", "is not allowed to execute", "is not in the sudoers file",
    )
}

/** The agent on this host predates the updater */
class SystemUpdaterMissing : Exception("the system updater is missing")

/** Runs the updater on one host */
class SystemUpdateOperations(private val runner: SSHCommandRunner) {
    suspend fun status(host: SSHHostID): SystemUpdateStatus = parsed(SystemUpdate.STATUS_COMMAND, host)

    suspend fun start(host: SSHHostID): SystemUpdateStatus = parsed(SystemUpdate.START_COMMAND, host)

    suspend fun setAtStart(part: SystemUpdate.Part, on: Boolean, host: SSHHostID): SystemUpdateStatus =
        parsed(SystemUpdate.atStartCommand(part, on), host)

    suspend fun setAtStop(part: SystemUpdate.Part, on: Boolean, host: SSHHostID): SystemUpdateStatus =
        parsed(SystemUpdate.atStopCommand(part, on), host)

    suspend fun setSchedule(schedule: CommandCatalog.Backups.Schedule, host: SSHHostID): SystemUpdateStatus =
        parsed(SystemUpdate.scheduleCommand(schedule), host)

    suspend fun setRebootSchedule(schedule: RebootSchedule, host: SSHHostID): SystemUpdateStatus =
        parsed(SystemUpdate.rebootScheduleCommand(schedule), host)

    suspend fun setSwap(sizeGB: Int?, host: SSHHostID): SystemUpdateStatus =
        parsed(SystemUpdate.swapCommand(sizeGB), host)

    private suspend fun parsed(command: String, host: SSHHostID): SystemUpdateStatus {
        val result = runner.run(command, host, 60.seconds)
        if (!result.succeeded && SystemUpdate.isMissing(result)) throw SystemUpdaterMissing()
        if (!result.succeeded) throw ServerControlError.commandFailure(command, result.exitCode, result.stderr)
        return SystemUpdateStatus.parse(result.stdout)
            ?: throw ServerControlError.ParseFailure(command, "no status")
    }
}
