package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.encodeToJsonElement
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** The stored fleet is a contract between the two apps */
class DeploymentWireTest {
    private fun golden(): String =
        checkNotNull(javaClass.getResourceAsStream("/swift-deployments-golden.json")) {
            "the Swift-dumped fixture is missing — run Tools/dump-deployment-golden.sh"
        }.bufferedReader().readText()

    private fun fleet(): List<Deployment> = DeploymentListCodec.decode(golden())

    @Test
    fun `the fleet Swift wrote decodes here`() {
        val fleet = fleet()
        assertEquals(4, fleet.size, "the golden no longer holds the four fixtures")

        val plain = fleet[0]
        assertEquals("plain", plain.name)
        assertEquals(Topology.SINGLE_HOST, plain.topology)
        assertEquals("example.com", plain.domain)
        assertEquals(2222, plain.entry.port)
        assertEquals("server-user", plain.entry.user)
        assertEquals(DeploymentScope.PUBLIC_INTERNET, plain.scope)
        assertEquals("wg0", plain.wgInterface)
        assertNull(plain.cardSize)
        assertNull(plain.metricsIndicatorStyle)
        assertNull(plain.storedNodes)
        assertEquals(15, plain.timeouts.quickSeconds)

        val full = fleet[1]
        assertEquals("Дом «o'brien»", full.name)
        assertEquals(Topology.VPS_RELAY_WITH_HOME_BACKEND, full.topology)
        assertEquals(listOf("example.org", "пример.рф", ""), full.additionalDomains)
        assertEquals("10.8.0.2", full.homeWGAddress)
        assertEquals("wg1", full.wgInterface)
        assertEquals(
            setOf(ServiceID.MAILCOW, ServiceID.VAULTWARDEN, ServiceID.NEXTCLOUD),
            full.services,
        )
        assertEquals(MetricsIndicatorStyle.RINGS, full.metricsIndicatorStyle)
        assertEquals(ServerCardSize.COMPACT, full.cardSize)
        assertEquals(DeploymentScope.LOCAL_ONLY, full.scope)
        assertEquals(listOf("prod", "почта"), full.tags)
        assertTrue(full.usesAgent && full.usesPasswordAuth)
        assertEquals(900, full.timeouts.longSeconds)
        assertEquals(9, full.serviceSettings.backupRetention)

        assertNotNull(full.storedNodes, "the pair stored no nodes")
        val nodes = full.storedNodes!!
        assertEquals(2, nodes.size)
        val ingress = nodes.first { it.legacySlot == DeploymentNode.LegacySlot.VPS }
        val worker = nodes.first { it.legacySlot == DeploymentNode.LegacySlot.HOME }
        assertEquals(setOf(NodeCapability.INGRESS), ingress.capabilities)
        assertNull(ingress.routedThrough, "a node that is its own ingress routes through nobody")
        assertEquals(ingress.id, worker.routedThrough)
        assertTrue(worker.servesOwnTraffic)
        assertEquals("ubuntu-24.04", ingress.distribution)

        assertEquals(worker.id, full.placement?.get(ServiceID.NEXTCLOUD))
        assertEquals(ingress.id, full.placement?.get(ServiceID.MAILCOW))
        assertNull(full.placement?.get(ServiceID.VAULTWARDEN))

        val adopted = fleet[2]
        assertEquals("", adopted.domain, "a machine added by hand has no domain")
        assertTrue(adopted.services.isEmpty())
        assertTrue(adopted.usesAgent)
    }

    @Test
    fun `re-encoding produces the same objects Swift did`() {
        val ours = DeploymentListCodec.json
            .encodeToJsonElement(fleet()) as JsonArray
        val theirs = Json.parseToJsonElement(golden()) as JsonArray
        assertEquals(theirs.size, ours.size)
        for ((index, theirElement) in theirs.withIndex()) {
            val mine = ours[index] as JsonObject
            val theirObject = theirElement as JsonObject
            assertEquals(
                theirObject.keys.sorted(), mine.keys.sorted(),
                "deployment $index: one app stores a field the other drops",
            )
            for (key in theirObject.keys) {
                if (key == "services") {
                    assertEquals(
                        (theirObject[key] as JsonArray).map { it.toString() }.toSet(),
                        (mine[key] as JsonArray).map { it.toString() }.toSet(),
                        "the installed services differ",
                    )
                    continue
                }
                assertEquals(theirObject[key], mine[key], "deployment $index, field $key")
            }
        }
    }

    /** What an OLDER file looks like: most keys absent */
    @Test
    fun `a deployment written before the newer fields still loads`() {
        val old = """
            [{"id":"6D3E0000-DE40-4000-8000-0000000000FF","name":"old","topology":"singleHost",
              "domain":"example.com","entry":{"host":"203.0.113.10","port":22,"user":"root"},
              "wgInterface":"wg0","services":[],"serviceSettings":{"domain":""},
              "timeouts":{"quickSeconds":15,"restartSeconds":60,
                          "serviceRestartSeconds":120,"longSeconds":600}}]
        """.trimIndent()
        val deployment = DeploymentListCodec.decode(old).single()
        assertEquals(DeploymentScope.PUBLIC_INTERNET, deployment.scope)
        assertTrue(deployment.additionalDomains.isEmpty())
        assertTrue(deployment.tags.isEmpty())
        assertNull(deployment.cardSize)
        assertNull(deployment.placement)
        assertTrue(!deployment.usesAgent && !deployment.usesPasswordAuth)
    }

    @Test
    fun `a field from a newer app is ignored rather than fatal`() {
        val fromTheFuture = golden().replaceFirst("\"domain\" :", "\"addedLater\" : 42,\n \"domain\" :")
        assertEquals(4, DeploymentListCodec.decode(fromTheFuture).size)
    }

    @Test
    fun `a stored pair without nodes derives the same two machines`() {
        val pair = fleet()[1].copy(storedNodes = null, placement = null)
        val nodes = pair.nodes
        assertEquals(2, nodes.size)
        assertEquals(setOf(NodeCapability.INGRESS), nodes[0].capabilities)
        assertEquals(setOf(NodeCapability.WORKER), nodes[1].capabilities)
        assertEquals("10.8.0.2", nodes[1].endpoint.host)
        assertEquals(pair.entry.port, nodes[1].endpoint.port)
        assertTrue(nodes[1].servesOwnTraffic)
        assertEquals(nodes[1].id, pair.nodeRunning(ServiceID.NEXTCLOUD)?.id)

        // A single host is one machine that is both halves.
        val single = fleet()[0]
        assertEquals(1, single.nodes.size)
        assertEquals(
            setOf(NodeCapability.INGRESS, NodeCapability.WORKER),
            single.nodes.single().capabilities,
        )
        assertEquals(single.nodes.single().id, single.nodeRunning(ServiceID.VAULTWARDEN)?.id)
    }

    @Test
    fun `a placement pointing at a machine that is gone still resolves`() {
        val stale = fleet()[1].copy(
            placement = ServicePlacement(mapOf("nextcloud" to "6D3E0000-DE40-4000-8000-0000000000EE")),
        )
        val resolved = stale.nodeRunning(ServiceID.NEXTCLOUD)
        assertNotNull(resolved)
        assertTrue(resolved!!.runsServices, "a service was placed on a node that runs none")
    }
}
