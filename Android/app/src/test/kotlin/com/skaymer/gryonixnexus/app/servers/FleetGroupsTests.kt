package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.ServerGroups
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

class FleetGroupsTests {
    @BeforeEach
    fun licensed() {
        LicenseGate.unlocked = true
    }

    @AfterEach
    fun locked() {
        LicenseGate.unlocked = false
    }

    private fun server(id: String, tags: List<String> = emptyList()) = Deployment(
        id = id,
        name = id,
        topology = Topology.SINGLE_HOST,
        domain = "$id.test",
        entry = HostEndpoint(host = "203.0.113.1", user = "root"),
        tags = tags,
    )

    private fun fleet(vararg servers: Deployment): Pair<FleetRepository, InMemoryDeploymentStore> {
        val store = InMemoryDeploymentStore(servers.toList())
        val repository = FleetRepository(store, InMemorySettingsStore(), eraser())
        repository.reload()
        return repository to store
    }

    @Test
    fun `a server joins and leaves a group, and the file says so`() {
        val (repository, store) = fleet(server("alpha"))

        repository.setGroupMember("alpha", "prod", true)
        assertEquals(listOf("prod"), store.load().single().tags)

        repository.setGroupMember("alpha", "prod", false)
        assertEquals(emptyList<String>(), store.load().single().tags)
    }

    @Test
    fun `membership is the servers named and nobody else`() {
        val (repository, store) = fleet(
            server("alpha", listOf("prod", "lab")),
            server("beta"),
        )

        repository.setGroupMembership("prod", setOf("beta"))

        val saved = store.load().associateBy { it.id }
        assertEquals(listOf("lab"), saved.getValue("alpha").tags)
        assertEquals(listOf("prod"), saved.getValue("beta").tags)
    }

    /** A rename is every carrier rewritten */
    @Test
    fun `renaming rewrites the carriers and leaves everyone else alone`() {
        val (repository, store) = fleet(
            server("alpha", listOf("prod")),
            server("beta", listOf("lab")),
        )

        repository.renameGroup("prod", "live")

        val saved = store.load().associateBy { it.id }
        assertEquals(listOf("live"), saved.getValue("alpha").tags)
        assertEquals(listOf("lab"), saved.getValue("beta").tags)
        assertEquals(listOf("lab", "live"), ServerGroups.known(repository.deployments.value))
    }

    @Test
    fun `deleting a group takes the label off and keeps the machines`() {
        val (repository, store) = fleet(
            server("alpha", listOf("prod")),
            server("beta", listOf("prod")),
        )

        repository.deleteGroup("prod")

        assertEquals(listOf("alpha", "beta"), store.load().map { it.id })
        assertTrue(store.load().all { it.tags.isEmpty() })
        assertEquals(emptyList<String>(), ServerGroups.known(repository.deployments.value))
    }

    @Test
    fun `the last member leaving takes the group off the strip`() {
        val (repository, _) = fleet(
            server("alpha", listOf("prod")),
            server("beta", listOf("prod", "lab")),
        )

        repository.setGroupMember("alpha", "prod", false)
        assertEquals(listOf("lab", "prod"), ServerGroups.known(repository.deployments.value))

        repository.setGroupMember("beta", "prod", false)
        assertEquals(listOf("lab"), ServerGroups.known(repository.deployments.value))
    }

    @Test
    fun `a group edit during a demo run never reaches the store`() {
        val store = InMemoryDeploymentStore(listOf(server("alpha")))
        val settings = InMemorySettingsStore()
        settings.setString(DemoDeployments.COUNT_KEY, "2")
        val repository = FleetRepository(store, settings, eraser())
        repository.reload()

        val target = repository.deployments.value.first()
        repository.setGroupMember(target.id, "shed", true)

        assertTrue(
            ServerGroups.known(repository.deployments.value).contains("shed"),
            "the edit did not reach the screen either"
        )
        assertEquals(listOf("alpha"), store.load().map { it.id })
        assertEquals(emptyList<String>(), store.load().single().tags)
    }
}
