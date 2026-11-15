package com.skaymer.gryonixnexus.app.servers.demo

import com.skaymer.gryonixnexus.app.servers.DemoHostMetrics
import com.skaymer.gryonixnexus.app.servers.DemoMachineProfile
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

/** Answers the shell commands a demo machine receives */
object DemoFleetCommands {
    /** Answers a command, applying whatever it changes first */
    fun respond(command: String, host: SSHHostID, machine: DemoAgentMachine): String =
        DemoFleetState.with(machine) { state ->
            val live = machine.containers.filter { it !in state.removed }
            changes(command, state, machine, live) ?: reads(command, state, machine, host, live)
        }

    private fun changes(
        command: String,
        state: DemoFleetState.Machine,
        machine: DemoAgentMachine,
        live: List<String>,
    ): String? {
        val lockdownOnly = CommandCatalog.AdminLockdown.only(emptyList())
        return when {
            CommandCatalog.Uninstall.SCRIPT_PATH in command -> uninstall(command, state, machine)
            CommandCatalog.Restore.SCRIPT_PATH in command -> CommandCatalog.Restore.DONE_MARKER
            command == CommandCatalog.AdminLockdown.STATUS -> state.lockdown
            command == CommandCatalog.AdminLockdown.ON -> "".also { state.lockdown = "on" }
            command == CommandCatalog.AdminLockdown.OFF -> "".also { state.lockdown = "off" }
            command.startsWith(lockdownOnly) -> "".also {
                val hosts = command.drop(lockdownOnly.length).trim()
                state.lockdown = if (hosts.isEmpty()) "off" else "only $hosts"
            }
            CommandCatalog.Backups.CONTROL_SCRIPT_PATH in command -> DemoFleetWrappers.backup(command, state, live)
            CommandCatalog.Updates.CONTROL_SCRIPT_PATH in command -> DemoFleetWrappers.update(command, state, live)
            CommandCatalog.DockerMailserver.MAILBOX_SCRIPT_PATH in command -> DemoFleetWrappers.mailbox(command, state)
            else -> power(command, state, machine.containers)
        }
    }

    private fun uninstall(command: String, state: DemoFleetState.Machine, machine: DemoAgentMachine): String {
        val target = argument(CommandCatalog.Uninstall.SCRIPT_PATH, command)
        when {
            target == null -> state.removed.addAll(machine.containers)
            target == CommandCatalog.Uninstall.VPN_TARGET -> state.removed.addAll(machine.containers.filter(::isVPN))
            else -> state.removed.add(target)
        }
        return CommandCatalog.Uninstall.DONE_MARKER
    }

    private fun power(command: String, state: DemoFleetState.Machine, containers: List<String>): String? {
        val stop = when {
            " restart" in command || " start" in command -> false
            " stop" in command -> true
            else -> return null
        }
        val service = containers.firstOrNull { it in command } ?: return null
        if (stop) state.stopped.add(service) else state.stopped.remove(service)
        return ""
    }

    private fun reads(
        command: String,
        state: DemoFleetState.Machine,
        machine: DemoAgentMachine,
        host: SSHHostID,
        live: List<String>,
    ): String = when {
        CommandCatalog.Updates.READ_SCHEDULE in command -> state.updateSchedule
        "autobackup.conf" in command -> state.backupSchedule
        "ls -lht" in command -> DemoFleetWrappers.listing(command, state, live)
        "docker compose" in command && " ps" in command -> composeTable(project(command), live, state.stopped)
        "docker ps" in command -> dockerTable(live, state.stopped)
        "docker logs" in command || "logs --tail" in command -> LOG
        "install-report" in command -> INSTALL_REPORT
        else -> hostProbe(command, DemoHostMetrics.profile(machine.id, host), host).orEmpty()
    }

    // The machine itself

    private fun hostProbe(command: String, profile: DemoMachineProfile, host: SSHHostID): String? = when {
        CommandCatalog.GENERAL_PROBE_SEPARATOR in command ->
            listOf(FORWARDING, PING, PING).joinToString("\n${CommandCatalog.GENERAL_PROBE_SEPARATOR}\n")
        "@@STAT@@" in command -> null
        CommandCatalog.IP_FORWARDING_CHECK in command -> FORWARDING
        command.startsWith("ping ") -> PING
        CommandCatalog.WG_SHOW in command -> wgShow(host)
        CommandCatalog.MEMORY in command -> free(profile)
        CommandCatalog.DISK in command -> df(profile)
        else -> null
    }

    private const val FORWARDING = "net.ipv4.ip_forward = 1"

    private val PING = """
        PING demo (203.0.113.20) 56(84) bytes of data.
        64 bytes from 203.0.113.20: icmp_seq=1 ttl=64 time=0.41 ms

        --- demo ping statistics ---
        1 packets transmitted, 1 received, 0% packet loss, time 0ms
        rtt min/avg/max/mdev = 0.410/0.410/0.410/0.000 ms
    """.trimIndent()

    private fun wgShow(host: SSHHostID): String {
        val home = host == SSHHostID.HOME
        return """
            interface: wg0
              public key: DEMO+SERVER+PLACEHOLDER+PUBLIC+KEY+0=
              private key: (hidden)
              listening port: 51820

            peer: DEMO+SERVER+PLACEHOLDER+PEER+KEY+00=
              endpoint: ${if (home) "203.0.113.20:51820" else "198.51.100.7:51820"}
              allowed ips: ${if (home) "10.8.0.1/32" else "10.8.0.2/32"}
              latest handshake: 42 seconds ago
              transfer: 1.21 GiB received, 3.45 GiB sent
              persistent keepalive: every 25 seconds
        """.trimIndent()
    }

    private fun df(profile: DemoMachineProfile): String {
        val size = profile.diskTotalBytes
        val used = (size * profile.diskUsedFraction).toLong()
        val percent = (profile.diskUsedFraction * 100).roundToInt()
        return "Mounted on 1B-blocks Used Use%\n/ $size $used $percent%\n/boot 536870912 96000000 18%"
    }

    private fun free(profile: DemoMachineProfile): String {
        val total = profile.memTotalBytes
        val used = (total * profile.memUsedFraction).toLong()
        val free = total - used
        val swapTotal = total / 4
        val swapUsed = total / 40
        return "               total        used        free      shared  buff/cache   available\n" +
            "Mem: $total $used $free 0 ${total / 8} $free\nSwap: $swapTotal $swapUsed ${swapTotal - swapUsed}"
    }

    // Reading a command

    /** The word after a token, unquoted */
    fun argument(token: String, command: String): String? {
        val start = command.indexOf("$token ").takeIf { it >= 0 } ?: return null
        val rest = command.substring(start + token.length + 1).trim()
        if (rest.isEmpty()) return null
        val word = rest.takeWhile { !it.isWhitespace() }.trim('\'', '"')
        return word.takeUnless { it.startsWith("-") }
    }

    private fun isVPN(id: String): Boolean =
        ServiceRegistry.service(ServiceID(id))?.category.let { it == ServiceCategory.VPN || it == ServiceCategory.IMPLICIT }

    fun stamp(): String = SimpleDateFormat("yyyy-MM-dd-HHmm", Locale.US).format(Date())

    // Canned reads

    private fun composeTable(project: String, containers: List<String>, stopped: Set<String>): String {
        val rows = containers.take(3).mapIndexed { index, name ->
            pad("$project-$name-1", 34) + pad("$name:latest", 26) + pad(status(name, stopped, index), 26) +
                "0.0.0.0:443->443/tcp"
        }
        return (listOf(pad("NAME", 34) + pad("IMAGE", 26) + pad("STATUS", 26) + "PORTS") + rows).joinToString("\n")
    }

    private fun dockerTable(containers: List<String>, stopped: Set<String>): String {
        val rows = containers.mapIndexed { index, name ->
            pad("%012x".format(index + 0xd30000), 14) + pad("$name:latest", 26) +
                pad(status(name, stopped, index), 26) + name
        }
        return (listOf(pad("CONTAINER ID", 14) + pad("IMAGE", 26) + pad("STATUS", 26) + "NAMES") + rows)
            .joinToString("\n")
    }

    private fun status(name: String, stopped: Set<String>, index: Int) =
        if (name in stopped) "Exited (0) 4 seconds ago" else "Up ${3 + index} days (healthy)"

    private fun pad(text: String, width: Int) = if (text.length >= width) "$text " else text.padEnd(width)

    private fun project(command: String): String {
        val start = command.indexOf("-p ").takeIf { it >= 0 } ?: return "gryonixnexus"
        return command.substring(start + 3).takeWhile { !it.isWhitespace() }
    }

    private val LOG = """
        2026-08-16T21:04:11.118Z Listening on 0.0.0.0:8080
        2026-08-16T21:04:11.402Z Database migrations are up to date
        2026-08-16T21:07:52.771Z GET /api/health 200 3ms
        2026-08-16T21:19:03.244Z Certificate for gryonix.com renewed, expires in 89 days
        2026-08-16T21:41:38.902Z GET /api/health 200 2ms
    """.trimIndent()

    val INSTALL_REPORT = """
        GRYONIXNEXUS_REPORT
        Domain: gryonix.com
        Services: mail, passwords, files, photos, VPN, DNS filter
        Admin user: admin@gryonix.com
        This is the demo server. Its report is an example of what a real
        installation writes on the machine it installed.
    """.trimIndent()
}
