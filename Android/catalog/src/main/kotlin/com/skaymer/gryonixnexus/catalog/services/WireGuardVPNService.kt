package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.FirewallPort
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.PrivilegedCommand
import com.skaymer.gryonixnexus.catalog.ServiceActions
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceCommand
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.ComposeFile
import com.skaymer.gryonixnexus.catalog.WebIngress

/** WireGuard VPN for the user's client devices */
class WireGuardVPNService : ManagedService {
    override val id = ServiceID.WIREGUARD_VPN
    override val displayName = "WireGuard"
    override val systemImage = "network.badge.shield.half.filled"
    override val category = ServiceCategory.VPN

    override val runtime = ServiceRuntime.Docker(VPNPanelService.COMPOSE_PROJECT)

    /** The WireGuard server + client management run in the unified panel */
    override fun composeFile(context: ServiceContext): ComposeFile? = null

    override fun setupSteps(context: ServiceContext): List<String> = emptyList()

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = listOf(
        FirewallPort(context.settings.wireguardVPNPort, FirewallPort.Proto.UDP,
                     comment = "WireGuard VPN")
    )

    /** The unified panel owns vpn.<domain> and the A record */
    override fun webIngress(context: ServiceContext): WebIngress? = null

    override fun dnsHostnames(context: ServiceContext): List<String> = emptyList()

    override fun reportSteps(context: ServiceContext): List<String> = emptyList()

    override fun actions(context: ServiceContext) = ServiceActions(
        statusProbe = StatusProbe.Container(
            name = VPNPanelService.CONTAINER_NAME,
            list = PrivilegedCommand("/usr/bin/docker", "ps -a")
        ),
        restart = ServiceCommand(
            PrivilegedCommand("/usr/bin/docker", "restart ${VPNPanelService.CONTAINER_NAME}"),
            ServiceCommand.TimeoutClass.RESTART
        )
    )

    override fun updateSpec(context: ServiceContext): UpdateSpec =
        UpdateSpec.builtOnServer(emptyList())

    /** Lives entirely inside the panel — removing the panel removes it */
    override fun uninstallSpec(context: ServiceContext) = UninstallSpec()
}
