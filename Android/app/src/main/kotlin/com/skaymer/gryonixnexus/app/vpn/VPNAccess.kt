package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.agentcontrol.VPNClientProtocols
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.Deployment

object VPNAccess {
    enum class PanelReason {
        NO_AGENT,

        BY_CHOICE,

        /** Both, on different servers in the same list */
        MIXED,
    }

    fun manageable(deployments: List<Deployment>): List<Deployment> =
        deployments.filter {
            VPNClientProtocols.installed(it.services).isNotEmpty() &&
                it.usesAgent &&
                it.serviceSettings.vpnClientAccess.allowsAppManagement
        }

    fun panelOnly(deployments: List<Deployment>): List<Deployment> {
        val managed = manageable(deployments).map { it.id }.toSet()
        return withVPN(deployments).filter { it.id !in managed }
    }

    fun withVPN(deployments: List<Deployment>): List<Deployment> =
        deployments.filter { VPNClientProtocols.installed(it.services).isNotEmpty() }

    fun panelReason(panelOnly: List<Deployment>): PanelReason {
        if (panelOnly.isEmpty()) return PanelReason.NO_AGENT
        val byChoice = panelOnly.count {
            it.usesAgent && !it.serviceSettings.vpnClientAccess.allowsAppManagement
        }
        return when (byChoice) {
            panelOnly.size -> PanelReason.BY_CHOICE
            0 -> PanelReason.NO_AGENT
            else -> PanelReason.MIXED
        }
    }

    fun protocol(preferred: ServiceID?, deployment: Deployment): ServiceID {
        val installed = VPNClientProtocols.installed(deployment.services)
        return preferred?.takeIf { it in installed }
            ?: installed.firstOrNull()
            ?: ServiceID.WIREGUARD_VPN
    }
}
