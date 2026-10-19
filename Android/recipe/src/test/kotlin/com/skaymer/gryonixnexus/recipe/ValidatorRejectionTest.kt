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
import com.skaymer.gryonixnexus.core.ValidationError
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import org.junit.jupiter.api.fail

/** What the validator REFUSES, and in which words */
class ValidatorRejectionTest {
    @Serializable
    data class Rejection(
        val name: String,
        val domain: String,
        val additionalDomains: List<String>,
        val hostname: String,
        val reverseDNSHostname: String? = null,
        val topology: String,
        val scope: String,
        val servers: List<Map<String, String>>,
        val access: Map<String, String>? = null,
        val services: List<String>,
        val settings: ServiceSettings,
        val language: String,
        val kind: String,
        val message: String
    )

    private val json = Json { ignoreUnknownKeys = true }

    private val rejections: List<Rejection> by lazy {
        val text = checkNotNull(javaClass.getResourceAsStream("/swift-recipe-rejections.json")) {
            "the refusal fixture is missing — run Tools/dump-recipe-golden.sh"
        }.bufferedReader().readText()
        json.decodeFromString<List<Rejection>>(text)
    }

    private fun input(case: Rejection): MailRecipeInput {
        val scope = checkNotNull(DeploymentScope.from(case.scope))
        return MailRecipeInput(
            domain = if (scope == DeploymentScope.LOCAL_ONLY) Domain.localOnly(case.domain)
                     else Domain.of(case.domain),
            additionalDomains = case.additionalDomains.map { Domain.of(it) },
            hostname = case.hostname,
            reverseDNSHostname = case.reverseDNSHostname,
            topology = checkNotNull(Topology.from(case.topology)),
            scope = scope,
            servers = case.servers.map { row ->
                ServerNode(
                    role = checkNotNull(ServerRole.from(row.getValue("role"))),
                    publicAddress = row["publicAddress"]?.let { NetworkAddress.parse(it) },
                    vpnAddress = row["vpnAddress"]?.let { NetworkAddress.parse(it) },
                    distribution = checkNotNull(
                        DistributionProfileID.from(row.getValue("distribution")))
                )
            },
            dashboardAccess = case.access?.let {
                DashboardAccessInput(
                    sshUser = it.getValue("sshUser"),
                    appPublicKey = it.getValue("appPublicKey"),
                    mailcowPath = it.getValue("mailcowPath"),
                    vaultwardenContainer = it.getValue("vaultwardenContainer")
                )
            },
            services = case.services.map { ServiceID(it) }.toSet(),
            serviceSettings = case.settings,
            language = checkNotNull(AppLanguage.from(case.language))
        )
    }

    private fun ValidationError.kind(): String = when (this) {
        is ValidationError.InvalidDomain -> "invalidDomain"
        is ValidationError.InvalidHostname -> "invalidHostname"
        is ValidationError.InvalidAddress -> "invalidAddress"
        is ValidationError.MissingPublicIP -> "missingPublicIP:${role.wireValue}"
        is ValidationError.MissingVPNAddress -> "missingVPNAddress:${role.wireValue}"
        is ValidationError.InconsistentTopology -> "inconsistentTopology"
    }

    @TestFactory
    fun `the same inputs are refused, in the same words`(): List<DynamicTest> {
        assertTrue(rejections.isNotEmpty(), "the refusal fixture is empty")
        return rejections.map { case ->
            DynamicTest.dynamicTest(case.name) {
                var caught: ValidationError? = null
                try {
                    MailInputValidator().validate(input(case))
                } catch (error: ValidationError) {
                    caught = error
                }
                val error = caught ?: fail(
                    "${case.name}: accepted here, refused by Swift with \"${case.message}\"")
                assertEquals(case.kind, error.kind(), "${case.name}: refused for another reason")
                assertEquals(case.message, error.message(input(case).language),
                             "${case.name}: refused in different words")
            }
        }
    }
}
