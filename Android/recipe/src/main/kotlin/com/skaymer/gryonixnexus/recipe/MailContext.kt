package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ForwardedPorts
import com.skaymer.gryonixnexus.catalog.MailEngineService
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.catalog.services.HeadscaleService
import com.skaymer.gryonixnexus.core.DistributionProfile
import com.skaymer.gryonixnexus.core.DistributionProfileID
import com.skaymer.gryonixnexus.core.NetworkAddress
import com.skaymer.gryonixnexus.core.makeProfile
import com.skaymer.gryonixnexus.core.ServerRole
import com.skaymer.gryonixnexus.core.ServerNode

class MailContext(val input: MailRecipeInput) {
    // ---------------------------------------------------------- Nodes

    fun server(role: ServerRole): ServerNode? = input.servers.firstOrNull { it.role == role }

    /** The distribution of one node, as a profile */
    fun distributionProfile(role: ServerRole): DistributionProfile =
        (server(role)?.distribution ?: DistributionProfileID.DEBIAN).makeProfile()

    /** The node where mail lives */
    val mailHostRole: ServerRole
        get() = if (input.topology == Topology.SINGLE_HOST) ServerRole.SINGLE_HOST
                else ServerRole.HOME_BACKEND

    val entryRole: ServerRole
        get() = if (input.topology == Topology.SINGLE_HOST) ServerRole.SINGLE_HOST
                else ServerRole.VPS_RELAY

    val mailHost: ServerNode? get() = server(mailHostRole)
    val entryPoint: ServerNode? get() = server(entryRole)

    // ------------------------------------------------- Convenience values

    val domainName: String get() = input.domain.name

    val additionalDomainNames: List<String>
        get() {
            val seen = mutableSetOf(domainName)
            return input.additionalDomains.map { it.name }.filter { seen.add(it) }
        }

    /** Every mail domain: the primary one plus the additional ones */
    val mailDomainNames: List<String> get() = listOf(domainName) + additionalDomainNames

    /** The same web hostname mirrored onto every additional domain */
    fun mirroredHostnames(hostname: String): List<String> {
        if (!hostname.endsWith(".$domainName")) return emptyList()
        val prefix = hostname.dropLast(domainName.length + 1)
        return additionalDomainNames.map { "$prefix.$it" }
    }

    val hostname: String get() = input.hostname

    val ptrHostname: String
        get() {
            val custom = input.reverseDNSHostname?.trim().orEmpty()
            return if (custom.isEmpty()) "relay.$domainName" else custom
        }

    /** Language of all user-visible generated content */
    val language: AppLanguage get() = input.language

    /** Public-internet or LAN-only — see the deployment scope */
    val scope: DeploymentScope get() = input.scope

    /** LAN-only: no DNS-records artifact, Caddy self-signs instead of ACME */
    val isLocalOnly: Boolean get() = scope == DeploymentScope.LOCAL_ONLY

    val usesInternalTLS: Boolean get() = scope.usesInternalTLS

    /** The deployment publishes A records naming its own address */
    val publishesAddressRecords: Boolean get() = scope.publishesAddressRecords

    val forwardedPorts: List<Int>
        get() = ForwardedPorts.tcp(allSelectedServices, serviceContext)

    /** UDP ports declared by the selected services */
    val forwardedUDPPorts: List<Int>
        get() = ForwardedPorts.udp(allSelectedServices, serviceContext)

    /** WireGuard subnet, derived from the VPS's VPN address (e.g */
    val wireGuardSubnet: String?
        get() {
            val address = server(ServerRole.VPS_RELAY)?.vpnAddress
            if (address !is NetworkAddress.IPv4) return null
            return address.value.split(".").dropLast(1).joinToString(".") + ".0/24"
        }

    // ------------------------------------------------------------ Services

    /** Context the services use to describe themselves during generation */
    val serviceContext: ServiceContext
        get() {
            var settings = input.serviceSettings
            if (settings.tailscaleLoginServer.isEmpty() &&
                com.skaymer.gryonixnexus.catalog.ServiceID.HEADSCALE in input.services) {
                settings = settings.copy(
                    tailscaleLoginServer = "http://127.0.0.1:${HeadscaleService.WEB_UI_PORT}"
                )
            }
            return ServiceContext(
                domain = domainName,
                additionalDomains = additionalDomainNames,
                sshUser = "",
                settings = settings,
                language = language,
                installedServices = input.services,
                usesInternalTLS = usesInternalTLS,
            )
        }

    val mailEngine: MailEngineService?
        get() = ServiceRegistry.mailEngines.firstOrNull { it.id in input.services }

    val hasMail: Boolean get() = mailEngine != null

    /** Services beyond the mail engine, in the catalog's stable order */
    val additionalServices: List<ManagedService>
        get() {
            val ids = ServiceRegistry.expanded(
                input.services, scope, input.serviceSettings.modelBackend
            ).toMutableSet()
            mailEngine?.let { ids.remove(it.id) }
            return ServiceRegistry.services(ids)
        }

    val allSelectedServices: List<ManagedService>
        get() {
            val services = additionalServices.toMutableList()
            mailEngine?.let { services.add(0, it) }
            return services
        }

    /** Whether Docker is needed on the mail node */
    val needsDocker: Boolean get() = allSelectedServices.isNotEmpty()

    val webServices: List<ManagedService>
        get() = allSelectedServices.filter { it.webIngress(serviceContext) != null }

    val needsCaddy: Boolean get() = webServices.isNotEmpty()
}
