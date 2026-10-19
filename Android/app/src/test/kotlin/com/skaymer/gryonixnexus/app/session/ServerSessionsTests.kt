package com.skaymer.gryonixnexus.app.session

import com.skaymer.gryonixnexus.app.secrets.DeploymentSecrets
import com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.addingNode
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.test.assertContentEquals
import kotlin.test.assertNotSame
import kotlin.test.assertSame
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

/** How a stored server becomes connection parameters */
class ServerSessionsTests {
    @BeforeEach
    fun licensed() {
        LicenseGate.unlocked = true
    }

    @AfterEach
    fun locked() {
        LicenseGate.unlocked = false
    }

    private val store = InMemorySecretStore()
    private val sessions = ServerSessions(store)

    private fun pair(id: String = "PAIR-1") = Deployment(
        id = id,
        name = "pair",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.10", port = 2200, user = "control"),
        homeWGAddress = "10.8.0.2",
        usesPasswordAuth = true
    )

    private fun single(id: String = "ONE-1", passwordAuth: Boolean = false) = Deployment(
        id = id,
        name = "one",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.20", user = "root"),
        usesPasswordAuth = passwordAuth
    )

    @Test
    fun `the entry endpoint becomes the address and the account`() {
        val settings = sessions.settings(pair())
        assertEquals("203.0.113.10", settings.vpsHost)
        assertEquals(2200, settings.vpsPort)
        assertEquals("control", settings.username)
        assertEquals("10.8.0.2", settings.homeHost)
    }

    /** Two machines, two passwords — the whole reason the map exists */
    @Test
    fun `each machine offers its own password`() {
        val deployment = pair()
        val secrets = DeploymentSecrets(store, deployment.id)
        secrets.setPassword("relay-secret", SSHHostID.VPS)
        secrets.setPassword("home-secret", SSHHostID.HOME)

        val settings = sessions.settings(deployment)
        assertEquals("relay-secret", settings.passwords[SSHHostID.VPS])
        assertEquals("home-secret", settings.passwords[SSHHostID.HOME])
    }

    @Test
    fun `a single host carries no home password`() {
        val deployment = single(passwordAuth = true)
        DeploymentSecrets(store, deployment.id).setPassword("only-one", SSHHostID.VPS)

        val settings = sessions.settings(deployment)
        assertEquals(setOf(SSHHostID.VPS), settings.passwords.keys)
    }

    /** A key deployment offers no passwords at all */
    @Test
    fun `a key deployment offers no password even when one is stored`() {
        val deployment = single(passwordAuth = false)
        DeploymentSecrets(store, deployment.id).setPassword("left-over", SSHHostID.VPS)

        assertTrue(sessions.settings(deployment).passwords.isEmpty())
    }

    @Test
    fun `the identity seed comes from the deployments own account`() {
        val deployment = single()
        val seed = ByteArray(32) { 7 }
        DeploymentSecrets(store, deployment.id).setIdentitySeed(seed)

        assertContentEquals(seed, sessions.settings(deployment).privateKeySeed)
        assertContentEquals(ByteArray(0), sessions.settings(single("OTHER")).privateKeySeed)
    }

    @Test
    fun `pins are carried per machine and absent before the first connection`() {
        val deployment = pair()
        val secrets = DeploymentSecrets(store, deployment.id)
        secrets.setHostKeyPin("ssh-ed25519 RELAY", DeploymentNode.LegacySlot.VPS)

        val settings = sessions.settings(deployment)
        assertEquals("ssh-ed25519 RELAY", settings.pinnedVPSHostKey)
        assertNull(settings.pinnedHomeHostKey)
    }

    // ------------------------------------------------------------- Sessions

    /** One runner per server, kept */
    @Test
    fun `the same server hands back the same runner`() = runTest {
        val deployment = single()
        assertSame(sessions.runner(deployment), sessions.runner(deployment))
    }

    @Test
    fun `a rename keeps the session and a new address replaces it`() = runTest {
        val deployment = single()
        val first = sessions.runner(deployment)
        assertSame(first, sessions.runner(deployment.copy(name = "renamed")))
        assertNotSame(
            first,
            sessions.runner(deployment.copy(entry = HostEndpoint(host = "198.51.100.5", user = "root")))
        )
    }

    @Test
    fun `a second machine added also replaces the session`() = runTest {
        val base = single()
        val entry = base.nodes.single()
        val first = sessions.runner(base)

        val one = base.addingNode(
            DeploymentNode(
                id = "N-9",
                name = "spare",
                endpoint = HostEndpoint(host = "10.9.0.9", user = "root"),
                capabilities = setOf(com.skaymer.gryonixnexus.servercontrol.NodeCapability.WORKER),
                routedThrough = entry.id,
            )
        )
        val second = sessions.runner(one)
        assertNotSame(first, second, "the first machine added must replace the session")

        val two = one.addingNode(
            DeploymentNode(
                id = "N-10",
                name = "spare two",
                endpoint = HostEndpoint(host = "10.9.0.10", user = "root"),
                capabilities = setOf(com.skaymer.gryonixnexus.servercontrol.NodeCapability.WORKER),
                routedThrough = entry.id,
            )
        )
        assertNotSame(
            second,
            sessions.runner(two),
            "the second machine added must replace the session too",
        )
    }

    @Test
    fun `renaming an added machine keeps the session`() = runTest {
        val grown = withThird()
        val first = sessions.runner(grown)
        val renamed = grown.copy(
            storedNodes = grown.nodes.map { node ->
                if (node.id == "N-3") node.copy(name = "the lab") else node
            },
        )
        assertSame(first, sessions.runner(renamed), "a rename must not replace the session")
    }

    @Test
    fun `changing the sign-in mode replaces the session`() = runTest {
        val deployment = single(passwordAuth = false)
        val first = sessions.runner(deployment)
        assertNotSame(first, sessions.runner(deployment.copy(usesPasswordAuth = true)))
    }

    /** Releasing drops the REFERENCE */
    @Test
    fun `releasing a server forgets its runner`() = runTest {
        val deployment = single()
        val first = sessions.runner(deployment)
        sessions.release(deployment.id)
        assertNotSame(first, sessions.runner(deployment))
    }

    @Test
    fun `two servers keep two runners`() = runTest {
        assertNotSame(sessions.runner(single("A")), sessions.runner(single("B")))
    }

    // ------------------------------------------------- Machines beyond two

    private fun withThird(): Deployment {
        val base = single("THREE-1", passwordAuth = true)
        val third = DeploymentNode(
            id = "N-3",
            name = "lab",
            endpoint = HostEndpoint(host = "10.0.0.9", port = 2222, user = "admin"),
            capabilities = setOf(com.skaymer.gryonixnexus.servercontrol.NodeCapability.WORKER),
            routedThrough = base.nodes.first().id,
        )
        return base.addingNode(third)
    }

    @Test
    fun `a third machine has a row in the route table`() {
        val deployment = withThird()
        val settings = sessions.settings(deployment)
        val route = settings.route(SSHHostID.node("N-3"))
        assertNotNull(route)
        assertEquals("10.0.0.9", route!!.address.host)
        assertEquals(2222, route.address.port)
    }

    @Test
    fun `a machine behind another is reached THROUGH it`() {
        val deployment = withThird()
        val route = sessions.settings(deployment).route(SSHHostID.node("N-3"))
        assertEquals(deployment.nodes.first().sshHost, route!!.parent)
    }

    @Test
    fun `a machine dialled directly has no parent`() {
        val base = single("THREE-2", passwordAuth = true)
        val direct = DeploymentNode(
            id = "N-4",
            endpoint = HostEndpoint(host = "198.51.100.7", user = "admin"),
            capabilities = setOf(com.skaymer.gryonixnexus.servercontrol.NodeCapability.WORKER),
        )
        val route = sessions.settings(base.addingNode(direct)).route(SSHHostID.node("N-4"))
        assertNull(route!!.parent)
    }

    @Test
    fun `a third machine signs in with its OWN password`() {
        val deployment = withThird()
        val secrets = DeploymentSecrets(store, deployment.id)
        secrets.setPassword("only-the-lab", SSHHostID.node("N-3"))
        assertEquals("only-the-lab", sessions.settings(deployment).passwords[SSHHostID.node("N-3")])
    }

    @Test
    fun `a third machine is pinned on first use like every other`() {
        val deployment = withThird()
        val secrets = DeploymentSecrets(store, deployment.id)
        secrets.setHostKeyPin("SHA256:third", "N-3")
        assertEquals(
            "SHA256:third",
            sessions.settings(deployment).route(SSHHostID.node("N-3"))!!.address.pin,
        )
    }

    @Test
    fun `a third machine signs in as ITS OWN account`() {
        val deployment = withThird()
        assertEquals("admin", sessions.settings(deployment).username(SSHHostID.node("N-3")))
        assertEquals(
            deployment.entry.user,
            sessions.settings(deployment).username(SSHHostID.VPS),
        )
    }
}
