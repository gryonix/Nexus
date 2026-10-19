package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.agentcontrol.AgentVPNClientOperations
import com.skaymer.gryonixnexus.agentcontrol.VPNClientConfiguration
import com.skaymer.gryonixnexus.agentcontrol.VPNClientDevice
import com.skaymer.gryonixnexus.agentcontrol.VPNDNSDefaults
import com.skaymer.gryonixnexus.agentcontrol.VPNDNSPriority
import com.skaymer.gryonixnexus.catalog.ServiceID

/** What the VPN screens ask of a server */
interface VPNClientManaging {
    suspend fun list(protocol: ServiceID): List<VPNClientDevice>
    suspend fun add(protocol: ServiceID, named: String, dns: List<String> = emptyList()): List<VPNClientDevice>
    suspend fun setDNS(protocol: ServiceID, clientID: String, dns: List<String>): List<VPNClientDevice> = list(protocol)
    suspend fun defaultDNS(): VPNDNSDefaults = VPNDNSDefaults()
    suspend fun setDefaultDNS(dns: List<String>): VPNDNSDefaults = VPNDNSDefaults(dns)
    suspend fun dnsPriority(): VPNDNSPriority = VPNDNSPriority()
    suspend fun setDNSPriority(resolvers: List<String>): VPNDNSPriority = VPNDNSPriority(resolvers)
    suspend fun remove(protocol: ServiceID, clientID: String): List<VPNClientDevice>
    suspend fun configuration(protocol: ServiceID, clientID: String): VPNClientConfiguration
}

/** The real one, wrapped rather than made to conform */
class AgentVPNClients(private val operations: AgentVPNClientOperations) : VPNClientManaging {
    override suspend fun list(protocol: ServiceID) = operations.list(protocol)
    override suspend fun add(protocol: ServiceID, named: String, dns: List<String>) = operations.add(protocol, named, dns)
    override suspend fun setDNS(protocol: ServiceID, clientID: String, dns: List<String>) =
        operations.setDNS(protocol, clientID, dns)
    override suspend fun defaultDNS() = operations.defaultDNS()
    override suspend fun setDefaultDNS(dns: List<String>) = operations.setDefaultDNS(dns)
    override suspend fun dnsPriority() = operations.dnsPriority()
    override suspend fun setDNSPriority(resolvers: List<String>) = operations.setDNSPriority(resolvers)
    override suspend fun remove(protocol: ServiceID, clientID: String) =
        operations.remove(protocol, clientID)
    override suspend fun configuration(protocol: ServiceID, clientID: String) =
        operations.configuration(protocol, clientID)
}
