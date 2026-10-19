package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class AgentServiceMappingTest {
    @Test
    fun `the registry is what we are checking against, and it is populated`() {
        assertTrue(
            ServiceRegistry.all.size > 20,
            "expected the ported catalog to hold most of the services, found ${ServiceRegistry.all.size}",
        )
    }

    @Test
    fun `every service in the registry has an agent id`() {
        val missing = ServiceRegistry.all
            .map { it.id }
            .filter { AgentServiceMapping.agentID(it) == null }
        assertEquals(
            emptyList(), missing,
            "these are installable but the agent map has no id for them — the agent would " +
                "answer 'unknown service' while the dashboard draws agent buttons on their cards",
        )
    }

    @Test
    fun `an agent id maps back to the service it came from`() {
        for (service in ServiceRegistry.all) {
            val agentID = AgentServiceMapping.agentID(service.id) ?: continue
            val back = AgentServiceMapping.serviceIDs(listOf(agentID))
            if (agentID == "vpn") {
                assertEquals(setOf(ServiceID.VPN_PANEL), back, "${service.id.rawValue} folds into the aggregate")
            } else {
                assertEquals(setOf(service.id), back, "${service.id.rawValue} must round-trip exactly")
            }
        }
    }

    @Test
    fun `psono and passbolt are on both sides of the contract`() {
        assertEquals("passbolt", AgentServiceMapping.agentID(ServiceID.PASSBOLT))
        assertEquals(setOf(ServiceID.PASSBOLT), AgentServiceMapping.serviceIDs(listOf("passbolt")))
        assertEquals("psono", AgentServiceMapping.agentID(ServiceID.PSONO))
        assertEquals(setOf(ServiceID.PSONO), AgentServiceMapping.serviceIDs(listOf("psono")))
    }

    @Test
    fun `an unknown id is dropped rather than invented`() {
        assertTrue(AgentServiceMapping.serviceIDs(listOf("portainer", "wordpress")).isEmpty())
        assertNull(AgentServiceMapping.agentID(ServiceID("portainer")))
    }

    @Test
    fun `a report of known and unknown ids keeps the known ones`() {
        val ids = AgentServiceMapping.serviceIDs(listOf("mailcow", "portainer", "vaultwarden"))
        assertEquals(setOf(ServiceID.MAILCOW, ServiceID.VAULTWARDEN), ids)
    }

    @Test
    fun `the aggregate vpn id is the panel`() {
        assertNotNull(AgentServiceMapping.serviceID("vpn"))
        assertEquals(setOf(ServiceID.VPN_PANEL), AgentServiceMapping.serviceIDs(listOf("vpn")))
    }
}
