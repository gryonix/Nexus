package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.core.Domain
import com.skaymer.gryonixnexus.core.DistributionProfileID
import com.skaymer.gryonixnexus.core.NetworkAddress
import com.skaymer.gryonixnexus.core.ServerNode
import com.skaymer.gryonixnexus.core.ServerRole
import com.skaymer.gryonixnexus.recipe.DashboardAccessInput
import com.skaymer.gryonixnexus.recipe.MailRecipeInput

data class ConfiguratorForm(
    val topology: Topology = Topology.SINGLE_HOST,
    val domain: String = "",
    val additionalDomains: List<String> = emptyList(),
    /** Empty means the default `relay.<domain>`, never an empty name */
    val reverseDNSHostname: String = "",
    val scope: DeploymentScope = DeploymentScope.PUBLIC_INTERNET,
    /** Scenario A — the server; B — the VPS relay */
    val publicIP: String = "",
    val vpsVPNIP: String = "10.8.0.1",
    val homeVPNIP: String = "10.8.0.2",
    /** The local server as this device reaches it */
    val homeNetworkAddress: String = "",
    val distribution: DistributionProfileID = DistributionProfileID.DEBIAN,
    /** Scenario B only */
    val homeDistribution: DistributionProfileID = DistributionProfileID.DEBIAN,
    val services: Set<ServiceID> = emptySet(),
    /** The per-service answers this form has been given */
    val serviceSettings: ServiceSettings = ServiceSettings(),
    val includeDashboardAccess: Boolean = false,
    val dashboardSSHUser: String = DashboardAccessInput.DEFAULT_USER,
    val useExistingUser: Boolean = false
) {
    companion object
    val isLocalOnly: Boolean get() = scope == DeploymentScope.LOCAL_ONLY

    /** The recipe input this form describes */
    fun toInput(
        language: AppLanguage = AppLanguage.EN,
        /** This device's `authorized_keys` line */
        appPublicKey: String? = null
    ): MailRecipeInput {
        val domainModel = makeDomain(domain)
        return MailRecipeInput(
            domain = domainModel,
            additionalDomains = additionalDomains
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .map { makeDomain(it) },
            hostname = "mail.${domainModel.name}",
            reverseDNSHostname = reverseDNSHostname.trim().ifEmpty { null },
            topology = topology,
            scope = scope,
            servers = serverNodes(),
            dashboardAccess = dashboardAccess(appPublicKey),
            services = services,
            serviceSettings = serviceSettings,
            language = language
        )
    }

    private fun dashboardAccess(appPublicKey: String?): DashboardAccessInput? {
        if (!includeDashboardAccess) return null
        val key = appPublicKey?.takeIf { it.isNotBlank() } ?: return null
        return DashboardAccessInput(
            sshUser = dashboardSSHUser.trim().lowercase(),
            createUser = !useExistingUser,
            appPublicKey = key
        )
    }

    /** The machines of this form */
    fun serverNodes(): List<ServerNode> = when (topology) {
        Topology.SINGLE_HOST -> listOf(
            ServerNode(
                role = ServerRole.SINGLE_HOST,
                publicAddress = makeAddress(publicIP),
                distribution = distribution
            )
        )
        Topology.VPS_RELAY_WITH_HOME_BACKEND -> listOf(
            ServerNode(
                role = ServerRole.VPS_RELAY,
                publicAddress = NetworkAddress.parse(publicIP),
                vpnAddress = NetworkAddress.parse(vpsVPNIP),
                distribution = distribution
            ),
            ServerNode(
                role = ServerRole.HOME_BACKEND,
                vpnAddress = NetworkAddress.parse(homeVPNIP),
                distribution = homeDistribution
            )
        )
    }

    private fun makeDomain(raw: String): Domain =
        if (isLocalOnly) Domain.localOnly(raw) else Domain.of(raw)

    private fun makeAddress(raw: String): NetworkAddress =
        if (isLocalOnly) NetworkAddress.localOnly(raw) else NetworkAddress.parse(raw)
}

/** The form that describes a server ALREADY in the fleet */
fun ConfiguratorForm.Companion.of(deployment: Deployment): ConfiguratorForm {
    val nodes = deployment.nodes
    return ConfiguratorForm(
        topology = deployment.topology,
        domain = deployment.domain,
        additionalDomains = deployment.additionalDomains,
        scope = deployment.scope,
        publicIP = deployment.entry.host,
        distribution = profile(nodes.firstOrNull()?.distribution),
        homeDistribution = profile(
            nodes.firstOrNull { it.legacySlot == DeploymentNode.LegacySlot.HOME }?.distribution
        ),
        services = deployment.services,
        serviceSettings = deployment.serviceSettings,
        includeDashboardAccess = true,
        dashboardSSHUser = deployment.entry.user,
        // The account exists by definition: this server has been installed.
        useExistingUser = true,
    )
}

private fun profile(stored: String?): DistributionProfileID =
    stored?.let { DistributionProfileID.from(it) } ?: DistributionProfileID.DEBIAN
