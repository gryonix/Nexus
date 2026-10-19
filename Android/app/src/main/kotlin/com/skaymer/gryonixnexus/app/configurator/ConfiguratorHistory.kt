package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.core.DistributionProfileID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

@Serializable
data class ConfiguratorHistoryEntry(
    val id: String,
    val savedAt: Long,
    val topology: String = Topology.SINGLE_HOST.wireValue,
    val scope: String = DeploymentScope.PUBLIC_INTERNET.wireValue,
    val domain: String = "",
    val additionalDomains: List<String> = emptyList(),
    val reverseDNSHostname: String = "",
    val publicIP: String = "",
    val vpsVPNIP: String = "",
    val homeVPNIP: String = "",
    val distribution: String = DistributionProfileID.DEBIAN.wireValue,
    val homeDistribution: String = DistributionProfileID.DEBIAN.wireValue,
    val services: List<String> = emptyList(),
    val includeDashboardAccess: Boolean = false,
    val dashboardSSHUser: String = "",
    val useExistingUser: Boolean = false,
    val serviceSettings: ServiceSettings = ServiceSettings(),
) {
    /** The form this entry describes */
    fun toForm(): ConfiguratorForm = ConfiguratorForm(
        topology = Topology.from(topology) ?: Topology.SINGLE_HOST,
        domain = domain,
        additionalDomains = additionalDomains,
        reverseDNSHostname = reverseDNSHostname,
        scope = DeploymentScope.from(scope) ?: DeploymentScope.PUBLIC_INTERNET,
        publicIP = publicIP,
        vpsVPNIP = vpsVPNIP.ifEmpty { ConfiguratorForm().vpsVPNIP },
        homeVPNIP = homeVPNIP.ifEmpty { ConfiguratorForm().homeVPNIP },
        distribution = DistributionProfileID.from(distribution) ?: DistributionProfileID.DEBIAN,
        homeDistribution = DistributionProfileID.from(homeDistribution)
            ?: DistributionProfileID.DEBIAN,
        services = services.map(::ServiceID).toSet(),
        includeDashboardAccess = includeDashboardAccess,
        dashboardSSHUser = dashboardSSHUser.ifEmpty { ConfiguratorForm().dashboardSSHUser },
        useExistingUser = useExistingUser,
        serviceSettings = serviceSettings,
    )

    companion object {
        fun of(form: ConfiguratorForm, id: String, savedAt: Long) = ConfiguratorHistoryEntry(
            id = id,
            savedAt = savedAt,
            topology = form.topology.wireValue,
            scope = form.scope.wireValue,
            domain = form.domain,
            additionalDomains = form.additionalDomains,
            reverseDNSHostname = form.reverseDNSHostname,
            publicIP = form.publicIP,
            vpsVPNIP = form.vpsVPNIP,
            homeVPNIP = form.homeVPNIP,
            distribution = form.distribution.wireValue,
            homeDistribution = form.homeDistribution.wireValue,
            services = form.services.map { it.rawValue }.sorted(),
            includeDashboardAccess = form.includeDashboardAccess,
            dashboardSSHUser = form.dashboardSSHUser,
            useExistingUser = form.useExistingUser,
            serviceSettings = form.serviceSettings,
        )
    }
}

/** Every configuration this device generated, newest first */
class ConfiguratorHistory(
    private val file: File,
    private val clock: () -> Long = { System.currentTimeMillis() },
    private val newID: () -> String = { java.util.UUID.randomUUID().toString() },
) {
    fun entries(): List<ConfiguratorHistoryEntry> {
        if (!file.exists()) return emptyList()
        return runCatching {
            json.decodeFromString<List<ConfiguratorHistoryEntry>>(file.readText())
        }.getOrDefault(emptyList())
    }

    /** Records one generated configuration */
    fun append(form: ConfiguratorForm) {
        val entry = ConfiguratorHistoryEntry.of(form, id = newID(), savedAt = clock())
        write(listOf(entry) + entries().take(LIMIT - 1))
    }

    fun delete(ids: Set<String>) {
        if (ids.isEmpty()) return
        write(entries().filterNot { it.id in ids })
    }

    fun clear() = write(emptyList())

    private fun write(entries: List<ConfiguratorHistoryEntry>) {
        runCatching {
            file.parentFile?.mkdirs()
            file.writeText(json.encodeToString(entries))
        }
    }

    private companion object {
        /** The same twenty the iPhone keeps */
        const val LIMIT = 20

        val json = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
        }
    }
}
