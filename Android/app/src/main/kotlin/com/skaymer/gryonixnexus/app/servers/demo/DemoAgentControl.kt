package com.skaymer.gryonixnexus.app.servers.demo

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import gryonixnexusd.v1.AgentHealth
import gryonixnexusd.v1.AgentModule
import gryonixnexusd.v1.Container
import gryonixnexusd.v1.DeviceList
import gryonixnexusd.v1.DiscoverResult
import gryonixnexusd.v1.DynamicDNSState
import gryonixnexusd.v1.Host
import gryonixnexusd.v1.LockdownMode
import gryonixnexusd.v1.LockdownState
import gryonixnexusd.v1.MetricsHistoryRequest
import gryonixnexusd.v1.PairRequest
import gryonixnexusd.v1.PairResponse
import gryonixnexusd.v1.RevokeRequest
import gryonixnexusd.v1.RevokeResponse
import gryonixnexusd.v1.SerialDevice
import gryonixnexusd.v1.SerialDeviceList
import gryonixnexusd.v1.Service
import gryonixnexusd.v1.ServiceStatus
import gryonixnexusd.v1.ServiceStatusRequest
import gryonixnexusd.v1.ServiceStatusResponse
import gryonixnexusd.v1.SessionPolicy
import gryonixnexusd.v1.SetDynamicDNSRequest
import gryonixnexusd.v1.SetLockdownRequest
import gryonixnexusd.v1.SetSessionPolicyRequest
import gryonixnexusd.v1.State
import gryonixnexusd.v1.Device
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/** Host state, panel guard, devices and DNS */
object DemoAgentControl {
    fun answer(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Control/GetState" -> state(machine).demoPayload()
        "/gryonixnexusd.v1.Control/Discover" -> DiscoverResult(services = state(machine).services).demoPayload()
        "/gryonixnexusd.v1.Control/MetricsHistory" -> {
            val asked = MetricsHistoryRequest.ADAPTER.decode(request)
            DemoAgentMaintenance.history(asked.bucket, asked.limit, machine).demoPayload()
        }
        "/gryonixnexusd.v1.Control/ListSerialDevices" -> serialDevices().demoPayload()
        "/gryonixnexusd.v1.Control/GetSystemSettings", "/gryonixnexusd.v1.Control/SetTimeZone",
        "/gryonixnexusd.v1.Control/SetHostName", "/gryonixnexusd.v1.Control/SetTimeSync",
        -> DemoSystemSettings.answer(path, request, machine)
        "/gryonixnexusd.v1.Control/ServiceStatus" -> {
            val asked = ServiceStatusRequest.ADAPTER.decode(request)
            ServiceStatusResponse(service = service(asked.service_id, machine), installed = true).demoPayload()
        }
        else -> lockdownOrPairing(path, request, machine)
    }

    private fun state(machine: DemoAgentMachine): State = State(
        agent_version = DemoAgentOffer.installedVersion,
        host = host(machine),
        discovered_at = System.currentTimeMillis(),
        services = DemoAgentState.present(machine).map { service(it, machine) },
        agent_health = agentHealth(),
    )

    private fun agentHealth(): AgentHealth = AgentHealth(
        memory_bytes = 21_500_000,
        peak_memory_bytes = 34_800_000,
        open_channels = 3,
        started_at = System.currentTimeMillis() - 5 * 86_400_000L,
        modules = listOf(
            AgentModule(name = "gryonixnexusd-metrics", version = DemoAgentOffer.installedVersion, size_bytes = 4_200_000, running = true),
            AgentModule(name = "gryonixnexusd-xray", version = DemoAgentOffer.installedVersion, size_bytes = 18_600_000, running = true),
        ),
    )

    private fun host(machine: DemoAgentMachine): Host {
        val domain = machine.deployment.domain
        return Host(
            hostname = machine.deployment.name,
            os_id = "debian",
            os_pretty_name = "Debian GNU/Linux 13 (trixie)",
            arch = "aarch64",
            topology = if (machine.deployment.hasRelayIngress) "relay" else "single",
            served_hostnames = if (domain.isEmpty()) emptyList() else listOf(domain),
            domains = if (domain.isEmpty()) emptyList() else listOf(domain),
        )
    }

    fun service(id: String, machine: DemoAgentMachine): Service {
        val running = DemoAgentState.isRunning(id, machine)
        return Service(
            id = id,
            display_name = ServiceRegistry.service(ServiceID(id))?.displayName ?: id,
            status = if (running) ServiceStatus.SERVICE_STATUS_RUNNING else ServiceStatus.SERVICE_STATUS_STOPPED,
            version = "1.0.0",
            containers = listOf(
                Container(
                    name = "$id-app-1",
                    image = "$id:latest",
                    state = if (running) "running" else "exited",
                    health = if (running) "healthy" else "",
                ),
            ),
        )
    }

    private fun serialDevices() = SerialDeviceList(
        directory_present = true,
        devices = listOf(
            SerialDevice(
                path = "/dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus-if00-port0",
                target = "/dev/ttyUSB0",
                label = "ITead Sonoff Zigbee 3.0 USB Dongle Plus",
            ),
        ),
    )

    // Panel guard and dynamic DNS

    private fun lockdownOrPairing(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? =
        when (path) {
            "/gryonixnexusd.v1.Lockdown/GetLockdown" -> lockdown(machine).demoPayload()
            "/gryonixnexusd.v1.Lockdown/SetLockdown" -> {
                val asked = SetLockdownRequest.ADAPTER.decode(request)
                val stored = when (asked.mode) {
                    LockdownMode.LOCKDOWN_MODE_ALL -> "on"
                    LockdownMode.LOCKDOWN_MODE_ONLY ->
                        if (asked.hosts.isEmpty()) "off" else "only ${asked.hosts.joinToString(" ")}"
                    else -> "off"
                }
                DemoFleetState.setLockdown(stored, machine)
                lockdown(machine).demoPayload()
            }
            "/gryonixnexusd.v1.Dns/GetDynamicDNS" -> dynamicDNS(machine).demoPayload()
            "/gryonixnexusd.v1.Dns/SetDynamicDNS" -> {
                val asked = SetDynamicDNSRequest.ADAPTER.decode(request)
                DemoAgentState.memory(machine) {
                    it.dynamicDNSEnabled = asked.names.isNotEmpty()
                    it.dynamicDNSNames = asked.names
                }
                dynamicDNS(machine).demoPayload()
            }
            else -> pairing(path, request, machine)
        }

    private fun lockdown(machine: DemoAgentMachine): LockdownState {
        val stored = DemoFleetState.lockdown(machine)
        return when {
            stored == "on" -> LockdownState(mode = LockdownMode.LOCKDOWN_MODE_ALL)
            stored.startsWith("only ") ->
                LockdownState(mode = LockdownMode.LOCKDOWN_MODE_ONLY, hosts = stored.drop(5).split(" "))
            else -> LockdownState(mode = LockdownMode.LOCKDOWN_MODE_OFF)
        }
    }

    private fun dynamicDNS(machine: DemoAgentMachine): DynamicDNSState = DemoAgentState.memory(machine) { stored ->
        val domain = machine.deployment.domain
        DynamicDNSState(
            enabled = stored.dynamicDNSEnabled,
            zone = domain,
            names = stored.dynamicDNSNames,
            has_token = stored.dynamicDNSEnabled,
            recent = if (stored.dynamicDNSEnabled) listOf("${stamp()} updated $domain -> 203.0.113.10") else emptyList(),
        )
    }

    // Paired devices and the session policy

    private fun pairing(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Pairing/ListDevices" ->
            DemoAgentState.memory(machine) { DeviceList(devices = it.devices.toList()) }.demoPayload()
        "/gryonixnexusd.v1.Pairing/Pair" -> PairResponse(device = pair(request, machine)).demoPayload()
        "/gryonixnexusd.v1.Pairing/Revoke" -> {
            val asked = RevokeRequest.ADAPTER.decode(request)
            DemoAgentState.memory(machine) { stored -> stored.devices.removeAll { it.id == asked.device_id } }
            RevokeResponse(revoked = true).demoPayload()
        }
        "/gryonixnexusd.v1.Pairing/GetSessionPolicy" -> sessionPolicy(machine).demoPayload()
        "/gryonixnexusd.v1.Pairing/SetSessionPolicy" -> {
            val asked = SetSessionPolicyRequest.ADAPTER.decode(request)
            DemoAgentState.memory(machine) { it.autoLogoutMonths = asked.auto_logout_months }
            sessionPolicy(machine).demoPayload()
        }
        else -> null
    }

    private fun pair(request: ByteArray, machine: DemoAgentMachine): Device {
        val asked = PairRequest.ADAPTER.decode(request)
        val device = Device(
            id = UUID.randomUUID().toString(),
            label = asked.label,
            public_key = asked.device_public_key,
            device_uid = asked.device_uid,
            scopes = listOf("read"),
            paired_at = System.currentTimeMillis(),
        )
        DemoAgentState.memory(machine) { it.devices.add(device) }
        return device
    }

    private fun sessionPolicy(machine: DemoAgentMachine): SessionPolicy = DemoAgentState.memory(machine) {
        SessionPolicy(auto_logout_months = it.autoLogoutMonths, device_count = it.devices.size)
    }

    fun stamp(): String = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(Date())
}
