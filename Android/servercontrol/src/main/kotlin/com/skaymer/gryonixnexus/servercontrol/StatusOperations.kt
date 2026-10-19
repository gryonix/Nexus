package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.core.WakeOnLAN
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

sealed class AdminLockdownState {
    data object Off : AdminLockdownState()
    data object All : AdminLockdownState()
    data class Only(val hosts: Set<String>) : AdminLockdownState()

    /** Whether the given vhost is currently guarded */
    fun guards(host: String): Boolean = when (this) {
        is Off -> false
        is All -> true
        is Only -> hosts.contains(host)
    }

    val isActive: Boolean get() = this != Off
}

/** One-shot status probes and simple restarts */
class StatusOperations(
    private val runner: SSHCommandRunner,
    private val config: DashboardConfig,
) {
    suspend fun macAddress(host: SSHHostID): String? =
        WakeOnLAN.normalised(
            runSucceeding(CommandCatalog.DEFAULT_ROUTE_MAC_ADDRESS, host, config.quickTimeout).trim(),
        )

    /** The MAC and broadcast address Wake on LAN needs */
    suspend fun wakeInfo(host: SSHHostID): WakeOnLAN.Read? =
        WakeOnLAN.parseRead(runSucceeding(WakeOnLAN.READ_COMMAND, host, config.quickTimeout))

    suspend fun sendWakeOnLAN(mac: String, broadcast: String, from: SSHHostID) {
        val command = WakeOnLAN.command(mac, broadcast)
            ?: throw IllegalArgumentException("not a MAC address and a broadcast address")
        runSucceeding(command, from, config.quickTimeout)
    }

    suspend fun ipForwarding(host: SSHHostID): Boolean =
        SysctlParser.parseIPForwarding(
            runSucceeding(CommandCatalog.IP_FORWARDING_CHECK, host, config.quickTimeout),
        )

    /** Pings the VPS public address from the VPS itself */
    suspend fun pingVPS(): PingResult {
        val result = runner.run(
            CommandCatalog.pingSelf(config.vpsHost),
            SSHHostID.VPS,
            config.quickTimeout,
        )
        return PingParser.parse(result.stdout)
    }

    /** The three VPS-side General probes in a single round-trip */
    suspend fun generalVPSStatus(): GeneralVPSStatus {
        val result = runner.run(
            CommandCatalog.generalProbe(config.vpsHost, config.homeWGAddress),
            SSHHostID.VPS,
            config.quickTimeout,
        )
        val parts = result.stdout.split(CommandCatalog.GENERAL_PROBE_SEPARATOR)
        if (parts.size != 3) {
            throw ServerControlError.ParseFailure("general probe", "expected three sections")
        }
        return GeneralVPSStatus(
            forwarding = SysctlParser.parseIPForwarding(parts[0]),
            selfPing = PingParser.parse(parts[1]),
            tunnelPing = PingParser.parse(parts[2]),
        )
    }

    suspend fun pingTunnel(): PingResult {
        val result = runner.run(
            CommandCatalog.pingTunnel(config.homeWGAddress),
            SSHHostID.VPS,
            config.quickTimeout,
        )
        return PingParser.parse(result.stdout)
    }

    suspend fun wgStatus(host: SSHHostID): WGStatus =
        WGShowParser.parse(runSucceeding(CommandCatalog.WG_SHOW, host, config.quickTimeout))

    suspend fun disk(host: SSHHostID): List<DiskMount> =
        DFParser.parse(runSucceeding(CommandCatalog.DISK, host, config.quickTimeout))

    suspend fun memory(host: SSHHostID): MemoryUsage =
        FreeParser.parse(runSucceeding(CommandCatalog.MEMORY, host, config.quickTimeout))

    /** Whether admin panels are currently VPN-only */
    suspend fun adminLockdownStatus(host: SSHHostID): AdminLockdownState =
        parseLockdownAnswer(
            runSucceeding(CommandCatalog.AdminLockdown.STATUS, host, config.quickTimeout),
        )

    suspend fun setAdminLockdown(enabled: Boolean, host: SSHHostID): AdminLockdownState {
        val command =
            if (enabled) CommandCatalog.AdminLockdown.ON else CommandCatalog.AdminLockdown.OFF
        return parseLockdownAnswer(runSucceeding(command, host, config.restartTimeout))
    }

    /** Guards only the given vhosts */
    suspend fun setAdminLockdown(hosts: List<String>, host: SSHHostID): AdminLockdownState {
        if (hosts.isEmpty()) return setAdminLockdown(false, host)
        val invalid = hosts.filterNot { CommandCatalog.AdminLockdown.isValidHost(it) }
        if (invalid.isNotEmpty()) {
            throw ServerControlError.CommandFailed(
                "lockdown",
                null,
                "These names cannot be guarded: ${invalid.joinToString(", ")}. Nothing was changed.",
            )
        }
        return parseLockdownAnswer(
            runSucceeding(CommandCatalog.AdminLockdown.only(hosts), host, config.restartTimeout),
        )
    }

    suspend fun controlContainer(
        action: CommandCatalog.Containers.Action,
        name: String,
        host: SSHHostID,
    ) {
        runSucceeding(CommandCatalog.Containers.control(action, name), host, config.restartTimeout)
    }

    suspend fun restartSSHD(host: SSHHostID) {
        runSucceeding(CommandCatalog.RESTART_SSHD, host, config.restartTimeout)
    }

    /** Restarts sshd on both machines in parallel */
    suspend fun restartSSHDBoth() = coroutineScope {
        val vps = async { restartSSHD(SSHHostID.VPS) }
        val home = async { restartSSHD(SSHHostID.HOME) }
        vps.await()
        home.await()
    }

    /** Reboots a host */
    suspend fun reboot(host: SSHHostID) {
        runner.fireAndForget(CommandCatalog.REBOOT_HOST, host)
    }

    suspend fun powerOff(host: SSHHostID) {
        runner.run("true", host, 15.seconds)
        val result = try {
            runner.run(CommandCatalog.POWER_OFF_HOST, host, 20.seconds)
        } catch (cancelled: kotlin.coroutines.cancellation.CancellationException) {
            throw cancelled
        } catch (dropped: Exception) {
            return
        }
        if (result.exitCode != 0) {
            throw ServerControlError.commandFailure(CommandCatalog.POWER_OFF_HOST, result.exitCode, result.stderr)
        }
    }

    /** Plain awaited WireGuard restart — only safe on the VPS */
    suspend fun restartWireGuardVPS() {
        runSucceeding(
            CommandCatalog.restartWireGuard(config.wgInterface),
            SSHHostID.VPS,
            config.restartTimeout,
        )
    }

    private suspend fun runSucceeding(
        command: String,
        host: SSHHostID,
        timeout: Duration,
    ): String {
        val result = runner.run(command, host, timeout)
        if (!result.succeeded) {
            throw ServerControlError.commandFailure(command, result.exitCode, result.stderr)
        }
        return result.stdout
    }

    companion object {
        internal fun parseLockdownAnswer(output: String): AdminLockdownState {
            val last = output.split("\n").lastOrNull { it.isNotEmpty() }?.trim() ?: ""
            if (last == "on") return AdminLockdownState.All
            if (last.startsWith("only ")) {
                val hosts = last.removePrefix("only ")
                    .split(" ")
                    .filter { it.isNotEmpty() && CommandCatalog.AdminLockdown.isValidHost(it) }
                return if (hosts.isEmpty()) AdminLockdownState.Off else AdminLockdownState.Only(hosts.toSet())
            }
            return AdminLockdownState.Off
        }
    }
}
