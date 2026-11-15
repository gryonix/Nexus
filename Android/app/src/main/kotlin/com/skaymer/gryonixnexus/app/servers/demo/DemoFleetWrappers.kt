package com.skaymer.gryonixnexus.app.servers.demo

import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.random.Random

/** The backup, update and mailbox wrappers on a demo machine */
internal object DemoFleetWrappers {
    fun backup(command: String, state: DemoFleetState.Machine, live: List<String>): String {
        val done = CommandCatalog.Backups.CONTROL_DONE_MARKER
        DemoFleetCommands.argument("estimate", command)?.let { service ->
            val data = (state.archives[service]?.firstOrNull()?.bytes ?: 3_000_000L) * 3
            return "${CommandCatalog.Backups.ESTIMATE_MARKER} $data 41000000000\n$done"
        }
        if (" delete " in command) {
            val name = DemoFleetCommands.argument("delete", command).orEmpty().substringAfterLast('/')
            state.archives.values.forEach { list -> list.removeAll { it.name == name } }
            return done
        }
        if ("set-schedule" in command) {
            state.backupSchedule = DemoFleetCommands.argument("set-schedule", command) ?: "daily"
            return done
        }
        if ("set-passphrase" in command) return done
        val service = (DemoFleetCommands.argument("run", command) ?: DemoFleetCommands.argument("backup", command))
            ?.takeIf { it in live } ?: return done
        val name = "$service-${DemoFleetCommands.stamp()}.tar.gz"
        val bytes = 4_900_000L + Random.nextLong(400_000)
        state.archives.getOrPut(service) { mutableListOf() }
            .add(0, DemoFleetState.Archive(name, bytes, System.currentTimeMillis()))
        return "${CommandCatalog.Backups.BACKUP_DONE_MARKER} $bytes /opt/backups/$service/$name\n$done"
    }

    fun update(command: String, state: DemoFleetState.Machine, live: List<String>): String {
        val done = CommandCatalog.Updates.DONE_MARKER
        if (" status" in command) return state.lastUpdateRun.ifEmpty { "No scheduled run yet." }
        if ("set-schedule" in command) {
            state.updateSchedule = DemoFleetCommands.argument("set-schedule", command) ?: "weekly"
            return done
        }
        DemoFleetCommands.argument("run", command)?.let { service ->
            state.updatable.remove(service)
            state.lastUpdateRun = "${CommandCatalog.Updates.UPDATED_MARKER} $service"
            return "${CommandCatalog.Updates.UPDATED_MARKER} $service $service:latest\n$done"
        }
        val asked = DemoFleetCommands.argument("check", command)
        val services = if (asked == null || asked == "--all") live else listOf(asked)
        val lines = services.map { service ->
            if (service in state.updatable) "${CommandCatalog.Updates.AVAILABLE_MARKER} $service $service:latest"
            else "${CommandCatalog.Updates.CURRENT_MARKER} $service"
        }
        return (lines + done).joinToString("\n")
    }

    fun mailbox(command: String, state: DemoFleetState.Machine): String {
        val marker = CommandCatalog.DockerMailserver.MAILBOX_DONE_MARKER
        if (" list" in command) return state.mailboxes.joinToString("\n") { "* $it ( 6.0K / ~ ) [0%]" }
        DemoFleetCommands.argument(" add", command)?.let { address ->
            if (address !in state.mailboxes) state.mailboxes.add(address)
            return "$marker add $address"
        }
        DemoFleetCommands.argument(" del", command)?.let { address ->
            state.mailboxes.remove(address)
            return "$marker del $address"
        }
        DemoFleetCommands.argument(" password", command)?.let { return "$marker password $it" }
        return marker
    }

    /** `ls -lht <dir>` for a backup directory */
    fun listing(command: String, state: DemoFleetState.Machine, live: List<String>): String {
        val service = live.firstOrNull { "/$it" in command }
        val archives = service?.let { state.archives[it] }
            ?: state.archives.values.flatten().sortedByDescending { it.madeMillis }
        if (archives.isEmpty()) return "total 0"
        val format = SimpleDateFormat("MMM d HH:mm", Locale.US)
        val rows = archives.map { "-rw-r--r-- 1 root root ${it.bytes} ${format.format(Date(it.madeMillis))} ${it.name}" }
        return (listOf("total ${archives.size * 8}") + rows).joinToString("\n")
    }
}
