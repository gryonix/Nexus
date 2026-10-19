package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.agentcontrol.VPNClientDevice
import com.skaymer.gryonixnexus.agentcontrol.VPNClientProtocols
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** The server device a tunnel uses; no client means own */
data class TunnelChoice(
    val serverId: String,
    val clientId: String = "",
    val clientName: String = "",
)

/** What the configuration picker offers and marks */
object TunnelChoices {
    /** The protocols of one server this phone can carry */
    fun protocols(server: Deployment, canCarry: (ServiceID) -> Boolean): List<ServiceID> =
        VPNClientProtocols.installed(server.services).filter(canCarry)

    /** The other devices of a protocol, without this phone's own */
    fun others(devices: List<VPNClientDevice>, ownId: String?): List<VPNClientDevice> =
        devices.filter { it.id != ownId }

    fun isOwnInUse(
        profile: LastTunnel.Profile?,
        serverId: String,
        protocol: ServiceID,
        ownId: String?,
    ): Boolean = profile != null &&
        sameProtocol(profile, serverId, protocol) &&
        (profile.clientId.isEmpty() || profile.clientId == ownId)

    fun isInUse(
        profile: LastTunnel.Profile?,
        serverId: String,
        protocol: ServiceID,
        deviceId: String,
    ): Boolean = profile != null &&
        sameProtocol(profile, serverId, protocol) &&
        profile.clientId == deviceId

    /** The configuration name the card shows */
    fun configurationName(profile: LastTunnel.Profile): String =
        profile.clientName.ifEmpty { profile.device }

    /** The current protocol when offered, else the first one */
    fun landingProtocol(available: List<ServiceID>, current: ServiceID): ServiceID? =
        if (current in available) current else available.firstOrNull()

    /** The device in use; this phone's own when unpicked */
    fun clientId(profile: LastTunnel.Profile, ownId: String?): String? =
        profile.clientId.ifEmpty { ownId }

    /** The DNS a stored tunnel names, kept across a switch */
    fun carriedDNS(profile: LastTunnel.Profile?): List<String> {
        val text = profile?.configuration ?: return emptyList()
        val line = text.lines().map { it.trim() }.firstOrNull {
            it.startsWith("dns=") || it.replace(" ", "").startsWith("DNS=")
        } ?: return emptyList()
        return line.substringAfter('=').split(',').map { it.trim() }.filter { it.isNotEmpty() }
    }

    /** That device's DNS as its server lists it */
    fun dns(devices: List<VPNClientDevice>, clientId: String?): List<String>? =
        devices.firstOrNull { it.id == clientId }?.dns

    /** The `host:port` the tunnel dials, when the text names one */
    fun endpoint(profile: LastTunnel.Profile): String? =
        EndpointPins.endpoint(profile.protocol, profile.configuration)

    private fun sameProtocol(profile: LastTunnel.Profile, serverId: String, protocol: ServiceID) =
        profile.serverId.isNotEmpty() && profile.serverId == serverId && profile.protocol == protocol
}
