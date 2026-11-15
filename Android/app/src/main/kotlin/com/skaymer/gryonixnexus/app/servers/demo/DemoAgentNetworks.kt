package com.skaymer.gryonixnexus.app.servers.demo

import com.skaymer.gryonixnexus.catalog.ServiceID
import gryonixnexusd.v1.AddVpnClientRequest
import gryonixnexusd.v1.CreateMeshAuthKeyRequest
import gryonixnexusd.v1.CreateMeshUserRequest
import gryonixnexusd.v1.DeleteMeshNodeRequest
import gryonixnexusd.v1.DeleteVpnClientRequest
import gryonixnexusd.v1.ExportVpnStateRequest
import gryonixnexusd.v1.GetVpnClientConfigRequest
import gryonixnexusd.v1.ImportVpnStateRequest
import gryonixnexusd.v1.ImportVpnStateResponse
import gryonixnexusd.v1.ListVpnClientsRequest
import gryonixnexusd.v1.MeshAuthKey
import gryonixnexusd.v1.MeshName
import gryonixnexusd.v1.MeshNameList
import gryonixnexusd.v1.MeshNode
import gryonixnexusd.v1.MeshNodeList
import gryonixnexusd.v1.MeshUser
import gryonixnexusd.v1.MeshUserList
import gryonixnexusd.v1.PublishMeshNamesRequest
import gryonixnexusd.v1.SetVpnClientDnsRequest
import gryonixnexusd.v1.VpnClient
import gryonixnexusd.v1.VpnClientList
import gryonixnexusd.v1.VpnDns
import gryonixnexusd.v1.VpnDnsPriority
import gryonixnexusd.v1.VpnState
import okio.ByteString.Companion.encodeUtf8

/** Mesh network and VPN clients */
object DemoAgentNetworks {
    fun answer(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Mesh/ListMeshUsers" -> meshUsers(machine).demoPayload()
        "/gryonixnexusd.v1.Mesh/CreateMeshUser" -> {
            val asked = CreateMeshUserRequest.ADAPTER.decode(request)
            DemoAgentState.memory(machine) { it.meshUsers.add("${it.meshUsers.size + 1}" to asked.name) }
            meshUsers(machine).demoPayload()
        }
        "/gryonixnexusd.v1.Mesh/CreateMeshAuthKey" -> {
            val asked = CreateMeshAuthKeyRequest.ADAPTER.decode(request)
            MeshAuthKey(
                key = "demo-server-placeholder-not-a-key",
                reusable = asked.reusable,
                expires_at = System.currentTimeMillis() + asked.expiration_hours * 3_600_000L,
            ).demoPayload()
        }
        "/gryonixnexusd.v1.Mesh/ListMeshNodes" -> meshNodes(machine).demoPayload()
        "/gryonixnexusd.v1.Mesh/DeleteMeshNode" -> {
            val asked = DeleteMeshNodeRequest.ADAPTER.decode(request)
            if (asked.node_id != "1") {
                DemoAgentState.memory(machine) { stored -> stored.meshNodes.removeAll { it.id == asked.node_id } }
            }
            meshNodes(machine).demoPayload()
        }
        "/gryonixnexusd.v1.Mesh/PublishMeshNames" -> {
            val asked = PublishMeshNamesRequest.ADAPTER.decode(request)
            val names = asked.names.mapIndexed { index, name -> name to "100.64.0.${index + 1}" }
            DemoAgentState.memory(machine) { it.meshNames = names }
            MeshNameList(records = names.map { MeshName(name = it.first, address = it.second) }).demoPayload()
        }
        else -> vpn(path, request, machine)
    }

    private fun meshUsers(machine: DemoAgentMachine) = DemoAgentState.memory(machine) { stored ->
        MeshUserList(users = stored.meshUsers.map { MeshUser(id = it.first, name = it.second) })
    }

    private fun meshNodes(machine: DemoAgentMachine) = DemoAgentState.memory(machine) { stored ->
        MeshNodeList(
            nodes = stored.meshNodes.map {
                MeshNode(
                    id = it.id, name = it.name, addresses = listOf(it.address), user = it.user,
                    online = it.online, last_seen = it.lastSeenMillis,
                )
            },
        )
    }

    // VPN clients and DNS

    private fun vpn(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Vpn/ListVpnClients" ->
            clients(ListVpnClientsRequest.ADAPTER.decode(request).protocol, machine).demoPayload()
        "/gryonixnexusd.v1.Vpn/AddVpnClient" -> {
            val asked = AddVpnClientRequest.ADAPTER.decode(request)
            addClient(asked.name, asked.protocol, asked.dns, machine)
            clients(asked.protocol, machine).demoPayload()
        }
        "/gryonixnexusd.v1.Vpn/SetVpnClientDns" -> {
            val asked = SetVpnClientDnsRequest.ADAPTER.decode(request)
            DemoAgentState.memory(machine) { stored ->
                stored.vpnClients[asked.protocol]?.firstOrNull { it.id == asked.client_id }?.dns = asked.dns
            }
            clients(asked.protocol, machine).demoPayload()
        }
        "/gryonixnexusd.v1.Vpn/GetVpnDns" -> vpnDNS(machine).demoPayload()
        "/gryonixnexusd.v1.Vpn/SetVpnDns" -> {
            val asked = VpnDns.ADAPTER.decode(request)
            DemoAgentState.memory(machine) { it.vpnDefaultDNS = asked.dns }
            vpnDNS(machine).demoPayload()
        }
        "/gryonixnexusd.v1.Vpn/DeleteVpnClient" -> {
            val asked = DeleteVpnClientRequest.ADAPTER.decode(request)
            DemoAgentState.memory(machine) { stored ->
                stored.vpnClients[asked.protocol]?.removeAll { it.id == asked.client_id }
            }
            clients(asked.protocol, machine).demoPayload()
        }
        "/gryonixnexusd.v1.Vpn/GetVpnClientConfig" -> {
            val asked = GetVpnClientConfigRequest.ADAPTER.decode(request)
            DemoVPNConfig.make(asked.protocol, asked.client_id).demoPayload()
        }
        else -> vpnMove(path, request, machine) ?: DemoAgentContainers.answer(path, request, machine)
    }

    /** The DNS order and the VPN's packed folders */
    private fun vpnMove(path: String, request: ByteArray, machine: DemoAgentMachine): ByteArray? = when (path) {
        "/gryonixnexusd.v1.Vpn/SetVpnDnsPriority" -> {
            val asked = VpnDnsPriority.ADAPTER.decode(request)
            DemoAgentState.memory(machine) { it.vpnDNSPriority = asked.resolvers }
            priority(machine).demoPayload()
        }
        "/gryonixnexusd.v1.Vpn/GetVpnDnsPriority" -> priority(machine).demoPayload()
        "/gryonixnexusd.v1.Vpn/ExportVpnState" -> VpnState(
            directories = ExportVpnStateRequest.ADAPTER.decode(request).directories,
            archive = "demo".encodeUtf8(),
        ).demoPayload()
        "/gryonixnexusd.v1.Vpn/ImportVpnState" ->
            ImportVpnStateResponse(directories = ImportVpnStateRequest.ADAPTER.decode(request).directories)
                .demoPayload()
        else -> null
    }

    private fun priority(machine: DemoAgentMachine) = DemoAgentState.memory(machine) { stored ->
        VpnDnsPriority(
            resolvers = stored.vpnDNSPriority,
            local_available = true,
            reachable = stored.vpnDNSPriority.map { true },
        )
    }

    private fun clients(id: String, machine: DemoAgentMachine) = DemoAgentState.memory(machine) { stored ->
        VpnClientList(
            clients = stored.vpnClients[id].orEmpty().map {
                VpnClient(id = it.id, name = it.name, detail = it.detail, dns = it.dns)
            },
        )
    }

    private fun addClient(name: String, id: String, dns: List<String>, machine: DemoAgentMachine) {
        DemoAgentState.memory(machine) { stored ->
            val octet = stored.nextOctet[id] ?: (stored.vpnClients[id].orEmpty().size + 2)
            stored.nextOctet[id] = octet + 1
            val made = DemoAgentState.device(name, ServiceID(id), octet)
            made.dns = dns.ifEmpty { stored.vpnDefaultDNS }
            stored.vpnClients.getOrPut(id) { mutableListOf() }.add(made)
        }
    }

    /** The default DNS, and the demo's own resolver */
    private fun vpnDNS(machine: DemoAgentMachine) = VpnDns(
        dns = DemoAgentState.memory(machine) { it.vpnDefaultDNS },
        local_address = "10.53.0.53",
        local_services = listOf(ServiceID.ADGUARD_HOME, ServiceID.PIHOLE)
            .filter { it in machine.deployment.services }.map { it.rawValue },
    )
}
