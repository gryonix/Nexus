package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceID
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import org.junit.jupiter.api.Test

class DeploymentDerivedTest {
    private val json = Json { ignoreUnknownKeys = true }

    private fun resource(name: String): String =
        checkNotNull(javaClass.getResourceAsStream(name)) {
            "$name is missing — run Tools/dump-deployment-golden.sh"
        }.bufferedReader().readText()

    private val fleet: List<Deployment> by lazy {
        DeploymentListCodec.decode(resource("/swift-deployments-golden.json"))
    }

    private val derived: List<JsonObject> by lazy {
        (json.parseToJsonElement(resource("/swift-deployment-derived.json")) as JsonArray)
            .map { it.jsonObject }
    }

    private fun JsonObject.string(key: String): String = this[key]!!.jsonPrimitive.content

    private fun JsonObject.list(key: String): List<String> =
        this[key]!!.jsonArray.map { it.jsonPrimitive.content }

    private fun hostName(host: SSHHostID): String = when (val kind = host.kind) {
        is SSHHostID.Kind.Slot -> "slot:" + kind.slot.name.lowercase()
        is SSHHostID.Kind.Node -> "node:" + kind.id
    }

    private fun capabilityText(node: DeploymentNode): String = buildList {
        if (node.capabilities.contains(NodeCapability.INGRESS)) add("ingress")
        if (node.capabilities.contains(NodeCapability.WORKER)) add("worker")
        if (node.servesOwnTraffic) add("servesOwnTraffic")
    }.joinToString("+")

    @TestFactory
    fun `every deployment derives what Swift derives`(): List<DynamicTest> {
        assertEquals(derived.size, fleet.size, "the two goldens describe different fleets")
        return fleet.indices.map { index ->
            val deployment = fleet[index]
            val want = derived[index]
            DynamicTest.dynamicTest(deployment.name) {
                assertEquals(want.string("id"), deployment.id, "the fixtures are out of order")
                assertShape(want, deployment)
                assertNodes(want, deployment)
                assertHosts(want, deployment)
            }
        }
    }

    private fun assertShape(want: JsonObject, deployment: Deployment) {
        assertEquals(
            want["isMultiHost"]!!.jsonPrimitive.content.toBoolean(),
            deployment.isMultiHost,
            "isMultiHost",
        )
        assertEquals(
            want["hasRelayIngress"]!!.jsonPrimitive.content.toBoolean(),
            deployment.hasRelayIngress,
            "hasRelayIngress",
        )
        assertEquals(
            want["hasHomeHost"]!!.jsonPrimitive.content.toBoolean(),
            deployment.hasHomeHost,
            "hasHomeHost",
        )
    }

    private fun assertNodes(want: JsonObject, deployment: Deployment) {
        val nodes = deployment.derivedNodes
        assertEquals(want.list("derivedNodeIDs"), nodes.map { it.id }, "derived node ids")
        assertEquals(
            want.list("derivedNodeSlots"),
            nodes.map { it.legacySlot?.name?.lowercase() ?: "" },
            "derived node slots",
        )
        assertEquals(
            want.list("derivedNodeCapabilities"),
            nodes.map(::capabilityText),
            "derived node capabilities",
        )
        assertEquals(
            want.list("derivedNodeRoutedThrough"),
            nodes.map { it.routedThrough ?: "" },
            "derived node parents",
        )
        assertEquals(
            want.list("derivedNodeEndpoints"),
            nodes.map { "${it.endpoint.user}@${it.endpoint.host}:${it.endpoint.port}" },
            "derived node endpoints",
        )
    }

    private fun assertHosts(want: JsonObject, deployment: Deployment) {
        assertEquals(
            want.list("teardownOrder"),
            deployment.teardownOrder.map { it.id },
            "teardown order — the one ordering that cannot be retried",
        )
        assertEquals(
            want.string("servicesHost"),
            hostName(deployment.servicesHost),
            "services host",
        )
        assertEquals(
            want.list("workerHosts"),
            deployment.workerHosts.map(::hostName),
            "worker hosts",
        )
        assertEquals(
            want["servicesNodeID"]?.jsonPrimitive?.content,
            deployment.servicesNode?.id,
            "services node",
        )
        assertEquals(
            want["ingressNodeID"]?.jsonPrimitive?.content,
            deployment.ingressNode?.id,
            "ingress node",
        )

        val wantHosts = want["hostRunning"]!!.jsonObject
        for ((service, host) in wantHosts) {
            assertEquals(
                host.jsonPrimitive.content,
                hostName(deployment.hostRunning(ServiceID(service))),
                "host running $service",
            )
        }
    }

    @Test
    fun `the two slots of one deployment never share an id`() {
        val deployment = "6D3E0000-DE40-4000-8000-000000000002"
        val vps = DeploymentNode.nodeID(deployment, DeploymentNode.LegacySlot.VPS)
        val home = DeploymentNode.nodeID(deployment, DeploymentNode.LegacySlot.HOME)
        assertEquals("6D3E0000-DE40-4000-8000-000000000003", vps)
        assertEquals("6D3E0000-DE40-4000-8000-000000000000", home)
    }
}
