package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.core.DistributionProfileID
import com.skaymer.gryonixnexus.core.Domain
import com.skaymer.gryonixnexus.core.NetworkAddress
import com.skaymer.gryonixnexus.core.ServerNode
import com.skaymer.gryonixnexus.core.ServerRole
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

object GoldenFixture {
    @Serializable
    data class GoldenServer(
        val role: String,
        val publicAddress: String? = null,
        val vpnAddress: String? = null,
        val distribution: String
    )

    @Serializable
    data class GoldenAccess(val sshUser: String, val createUser: Boolean, val appPublicKey: String)

    @Serializable
    data class GoldenArtifact(
        val fileName: String,
        val kind: String,
        val sha256: String,
        val bytes: Int
    )

    @Serializable
    data class GoldenVariant(
        val name: String,
        val domain: String,
        val additionalDomains: List<String>,
        val hostname: String,
        val topology: String,
        val scope: String,
        val servers: List<GoldenServer>,
        val access: GoldenAccess? = null,
        val services: List<String>,
        val settings: ServiceSettings,
        val language: String,
        val artifacts: List<GoldenArtifact>,
        val serviceScripts: List<GoldenArtifact> = emptyList(),
        val warnings: List<String>,
        val notes: List<String>
    )

    /** One artifact of one run, with its full text */
    @Serializable
    data class Sample(val variant: String, val fileName: String, val contents: String)

    private val json = Json { ignoreUnknownKeys = true }

    private fun resource(name: String): String =
        checkNotNull(GoldenFixture::class.java.getResourceAsStream(name)) {
            "$name is missing — run Tools/dump-recipe-golden.sh"
        }.bufferedReader().readText()

    val variants: List<GoldenVariant> by lazy {
        json.decodeFromString<List<GoldenVariant>>(resource("/swift-recipe-golden.json"))
    }

    val samples: List<Sample> by lazy {
        json.decodeFromString<List<Sample>>(resource("/swift-recipe-samples.json"))
    }

    private fun address(value: String?): NetworkAddress? = value?.let { NetworkAddress.parse(it) }

    fun input(variant: GoldenVariant): MailRecipeInput = MailRecipeInput(
        domain = Domain.of(variant.domain),
        additionalDomains = variant.additionalDomains.map { Domain.of(it) },
        hostname = variant.hostname,
        topology = checkNotNull(Topology.from(variant.topology)),
        scope = checkNotNull(DeploymentScope.from(variant.scope)),
        servers = variant.servers.map {
            ServerNode(
                role = checkNotNull(ServerRole.from(it.role)),
                publicAddress = address(it.publicAddress),
                vpnAddress = address(it.vpnAddress),
                distribution = checkNotNull(DistributionProfileID.from(it.distribution))
            )
        },
        dashboardAccess = variant.access?.let {
            DashboardAccessInput(sshUser = it.sshUser, createUser = it.createUser,
                                 appPublicKey = it.appPublicKey)
        },
        services = variant.services.map { ServiceID(it) }.toSet(),
        serviceSettings = variant.settings,
        language = checkNotNull(AppLanguage.from(variant.language))
    )

    fun context(variant: GoldenVariant): MailContext = MailContext(input(variant))
}
