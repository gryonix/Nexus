package com.skaymer.gryonixnexus.app.servers.demo

import com.skaymer.gryonixnexus.catalog.ServiceAPIGroups
import com.skaymer.gryonixnexus.catalog.ServiceID
import gryonixnexusd.v1.AppModuleSet
import gryonixnexusd.v1.ServiceNameSet
import gryonixnexusd.v1.SetServiceNameRequest
import gryonixnexusd.v1.AudioOutput
import gryonixnexusd.v1.DockerNetwork
import gryonixnexusd.v1.DockerRemovalResult
import gryonixnexusd.v1.GetLocalRootCAResponse
import gryonixnexusd.v1.LocalAlias
import gryonixnexusd.v1.LocalAliasesState
import gryonixnexusd.v1.ListAudioOutputsResponse
import gryonixnexusd.v1.McpAccessState
import gryonixnexusd.v1.NetworkInventory
import gryonixnexusd.v1.OdioCallRequest
import gryonixnexusd.v1.OdioCallResponse
import gryonixnexusd.v1.OpenAPISite
import gryonixnexusd.v1.OpenAPIState
import gryonixnexusd.v1.PortProbe
import gryonixnexusd.v1.ProbePublicPortsRequest
import gryonixnexusd.v1.ProbePublicPortsResponse
import gryonixnexusd.v1.RemoveNetworkRequest
import gryonixnexusd.v1.SetHomeOnlyPortsRequest
import gryonixnexusd.v1.SetHomeOnlyPortsResponse
import gryonixnexusd.v1.SetLocalAliasRequest
import gryonixnexusd.v1.SetMcpAccessRequest
import gryonixnexusd.v1.SetOpenAPIRequest
import gryonixnexusd.v1.SetAmneziaKernelRequest
import gryonixnexusd.v1.VpnInterfaceFacts
import gryonixnexusd.v1.VpnSpeedFacts

/** Modules, MCP, home-only sites, networks, audio and the API switch */
object DemoAgentGaps {
    fun answer(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? =
        exposure(path, request, machine)
            ?: networks(path, request, machine)
            ?: audio(path, request)
            ?: vpnOrAPI(path, request, machine)
            ?: DemoAgentLeftovers.answer(path, request, machine)

    private fun exposure(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? =
        DemoAgentState.memory(machine) { stored ->
            when (path) {
                "/gryonixnexusd.v1.AppModules/GetAppModules" -> AppModuleSet(on = stored.appModules).demoPayload()
                "/gryonixnexusd.v1.AppModules/SetAppModules" -> {
                    stored.appModules = AppModuleSet.ADAPTER.decode(request).on
                    AppModuleSet(on = stored.appModules).demoPayload()
                }
                "/gryonixnexusd.v1.ServiceNames/GetServiceNames" -> ServiceNameSet(names = stored.serviceNames.toMap()).demoPayload()
                "/gryonixnexusd.v1.ServiceNames/SetServiceName" -> {
                    val asked = SetServiceNameRequest.ADAPTER.decode(request)
                    if (asked.name.isEmpty()) stored.serviceNames.remove(asked.service_id) else stored.serviceNames[asked.service_id] = asked.name
                    ServiceNameSet(names = stored.serviceNames.toMap()).demoPayload()
                }
                "/gryonixnexusd.v1.McpAccess/GetMcpAccess" -> mcp(stored.mcpOn).demoPayload()
                "/gryonixnexusd.v1.McpAccess/SetMcpAccess" -> {
                    stored.mcpOn = SetMcpAccessRequest.ADAPTER.decode(request).enabled
                    mcp(stored.mcpOn).demoPayload()
                }
                "/gryonixnexusd.v1.Exposure/GetLocalAliases" -> aliases(stored.localAliases).demoPayload()
                "/gryonixnexusd.v1.Exposure/SetLocalAlias" -> {
                    val asked = SetLocalAliasRequest.ADAPTER.decode(request)
                    stored.localAliases.remove(asked.host)
                    if (asked.on) stored.localAliases.add(asked.host)
                    aliases(stored.localAliases).demoPayload()
                }
                "/gryonixnexusd.v1.Exposure/SetHomeOnlyPorts" -> {
                    stored.homeOnlyPorts = SetHomeOnlyPortsRequest.ADAPTER.decode(request).ports
                    SetHomeOnlyPortsResponse(ports = stored.homeOnlyPorts).demoPayload()
                }
                "/gryonixnexusd.v1.Exposure/ProbePublicPorts" -> {
                    val closed = stored.homeOnlyPorts.map { it.port }.toSet()
                    ProbePublicPortsResponse(
                        ports = ProbePublicPortsRequest.ADAPTER.decode(request).ports
                            .map { PortProbe(port = it, open_ = it !in closed) },
                    ).demoPayload()
                }
                "/gryonixnexusd.v1.Exposure/GetLocalRootCA" -> GetLocalRootCAResponse(pem = DEMO_ROOT_PEM).demoPayload()
                else -> null
            }
        }

    private fun mcp(on: Boolean) = McpAccessState(
        enabled = on,
        users = if (on) listOf("server-user") else emptyList(),
        command = if (on) "gryonixnexusd mcp" else "",
    )

    private fun aliases(hosts: List<String>) = LocalAliasesState(
        aliases = hosts.map { LocalAlias(host = it, alias = "${it.substringBefore('.')}.local") },
    )

    private const val DEMO_ROOT_PEM = "-----BEGIN CERTIFICATE-----\nZGVtbw==\n-----END CERTIFICATE-----\n"

    // Docker networks

    private fun networks(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Containers/ListNetworks" -> networkList(machine).demoPayload()
        "/gryonixnexusd.v1.Containers/RemoveNetwork" -> {
            val name = RemoveNetworkRequest.ADAPTER.decode(request).name
            val network = networkList(machine).networks.firstOrNull { it.name == name }
            val removable = network != null && !network.builtin && !network.in_use
            if (removable) DemoAgentState.memory(machine) { it.removedNetworks.add(name) }
            DockerRemovalResult(removed = removable, message = if (removable) "" else "network $name is in use")
                .demoPayload()
        }
        else -> null
    }

    private fun networkList(machine: DemoAgentMachine): NetworkInventory {
        val removed = DemoAgentState.memory(machine) { it.removedNetworks.toSet() }
        val fixed = listOf("bridge", "host", "none").map { network(it, builtin = true, containers = 0) } +
            network("demo_unused", builtin = false, containers = 0)
        val managed = machine.containers.take(6).mapIndexed { index, id ->
            network("${id}_default", builtin = false, containers = 2)
                .copy(managed = true, subnet = "172.${20 + index}.0.0/16")
        }
        return NetworkInventory(networks = (fixed + managed).filter { it.name !in removed })
    }

    private fun network(name: String, builtin: Boolean, containers: Int) = DockerNetwork(
        id = name.toByteArray().joinToString("") { "%02x".format(it) }.take(12),
        name = name,
        driver = if (name == "host" || name == "none") name else "bridge",
        scope = "local",
        containers = containers,
        in_use = containers > 0,
        builtin = builtin,
    )

    // The audio hub

    private fun audio(path: String, request: ByteArray): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Audio/ListAudioOutputs" -> ListAudioOutputsResponse(
            outputs = listOf(AudioOutput(device = "hw:CARD=Headphones,DEV=0", title = "bcm2835 Headphones", mixers = listOf("PCM"))),
        ).demoPayload()
        "/gryonixnexusd.v1.Audio/OdioCall" -> {
            val asked = OdioCallRequest.ADAPTER.decode(request)
            OdioCallResponse(status = 200, body = if (asked.method == "GET" || asked.path == "/gryonixnexus/settings") odioBody(asked.path) else "{}").demoPayload()
        }
        else -> null
    }

    private fun odioBody(path: String): String = when (path) {
        "/gryonixnexus/settings" ->
            """{"spotify.name":"Home server","spotify.bitrate":"320","spotify.normalise":"false","spotify.volume":"100","airplay.name":"Home server"}"""
        "/audio/server" -> """{"volume":0.42,"muted":false}"""
        "/audio/outputs" -> """[{"name":"alsa_output.headphones","description":"Headphones","volume":0.42,"default":true}]"""
        "/players" -> """[{"bus_name":"org.mpris.MediaPlayer2.mpd","identity":"Music Player Daemon","playback_status":"Playing","metadata":{"xesam:title":"Demo track","xesam:artist":"gryonix"},"capabilities":{"can_go_next":true,"can_go_previous":true}}]"""
        "/services" -> """[{"name":"mpd.service","scope":"user","description":"Music Player Daemon","running":true},{"name":"shairport-sync.service","scope":"user","description":"AirPlay","running":true}]"""
        "/bluetooth" -> """{"powered":true,"pairing_active":false}"""
        else -> "{}"
    }

    // VPN speed facts and open app APIs

    private fun vpnOrAPI(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Vpn/GetVpnSpeedFacts" -> speedFacts(kernel = false).demoPayload()
        "/gryonixnexusd.v1.Vpn/SetAmneziaKernel" ->
            speedFacts(SetAmneziaKernelRequest.ADAPTER.decode(request).enabled).demoPayload()
        "/gryonixnexusd.v1.Lockdown/GetOpenAPI" -> openAPI(machine).demoPayload()
        "/gryonixnexusd.v1.Lockdown/SetOpenAPI" -> {
            val asked = SetOpenAPIRequest.ADAPTER.decode(request)
            DemoAgentState.memory(machine) { it.openAPI[asked.service_id] = asked.paths }
            openAPI(machine).demoPayload()
        }
        else -> null
    }

    private fun speedFacts(kernel: Boolean) = VpnSpeedFacts(
        interfaces = listOf(
            VpnInterfaceFacts(protocol = "wireguard", interface_ = "wgpanel", mtu = 1280, kernel = true),
            VpnInterfaceFacts(protocol = "amneziawg", interface_ = "wg0", mtu = 1280, kernel = kernel),
        ),
        cpu_cores = 2,
        load = 0.4,
        client_mtu = 1280,
        amnezia_kernel_status = if (kernel) "on" else "off",
        amnezia_kernel_possible = true,
    )

    private fun openAPI(machine: DemoAgentMachine): OpenAPIState {
        val chosen = DemoAgentState.memory(machine) { it.openAPI.toMap() }
        val sites = machine.deployment.services.sortedBy { it.rawValue }
            .filter { ServiceAPIGroups.groups(it).isNotEmpty() }
            .map { id -> OpenAPISite(service_id = id.rawValue, paths = chosen[id.rawValue] ?: defaultPaths(id), editable = true) }
        return OpenAPIState(sites = sites)
    }

    private fun defaultPaths(id: ServiceID): List<String> =
        if (id in setOf(ServiceID.VAULTWARDEN, ServiceID.MAILCOW, ServiceID.N8N)) {
            ServiceAPIGroups.groups(id).flatMap { it.paths }
        } else {
            emptyList()
        }
}
