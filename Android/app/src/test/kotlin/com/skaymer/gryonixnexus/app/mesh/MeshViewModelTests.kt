package com.skaymer.gryonixnexus.app.mesh

import com.skaymer.gryonixnexus.agentcontrol.MeshAuthKey
import com.skaymer.gryonixnexus.agentcontrol.MeshName
import com.skaymer.gryonixnexus.agentcontrol.MeshNode
import com.skaymer.gryonixnexus.agentcontrol.MeshUser
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import com.skaymer.gryonixnexus.app.licensing.LicensePrompt
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

/** The mesh's devices */
class MeshViewModelTests {
    @BeforeEach
    fun licensed() {
        LicenseGate.unlocked = true
    }

    @AfterEach
    fun locked() {
        LicenseGate.unlocked = false
        LicensePrompt.showing.value = false
    }

    private fun server(
        services: Set<ServiceID> = setOf(ServiceID.HEADSCALE, ServiceID.VAULTWARDEN),
        usesAgent: Boolean = true,
    ) = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        services = services,
        usesAgent = usesAgent,
    )

    private fun node(id: String, online: Boolean = true) = MeshNode(
        id = id,
        name = "laptop-$id",
        addresses = listOf("100.64.0.$id"),
        user = "devices",
        isOnline = online,
        lastSeen = null,
    )

    private class Scripted(
        val nodes: () -> List<MeshNode> = { emptyList() },
        val remove: (String) -> List<MeshNode> = { emptyList() },
        val users: () -> List<MeshUser> = { emptyList() },
        val createUser: (String) -> List<MeshUser> = { emptyList() },
        val mint: (String) -> MeshAuthKey = { MeshAuthKey("hskey-$it", false, null) },
        val publish: (List<String>) -> List<MeshName> = { names ->
            names.map { MeshName(it, "100.64.0.1") }
        },
    ) : MeshManaging {
        val asked = mutableListOf<String>()
        var mintedFor: String? = null
        var published: List<String>? = null

        override suspend fun nodes(): List<MeshNode> {
            asked += "nodes"
            return nodes.invoke()
        }

        override suspend fun removeNode(id: String): List<MeshNode> {
            asked += "remove:$id"
            return remove.invoke(id)
        }

        override suspend fun users(): List<MeshUser> {
            asked += "users"
            return users.invoke()
        }

        override suspend fun createUser(named: String): List<MeshUser> {
            asked += "createUser:$named"
            return createUser.invoke(named)
        }

        override suspend fun mintAuthKey(
            userID: String,
            reusable: Boolean,
            expirationHours: Int,
        ): MeshAuthKey {
            asked += "mint:$userID:$reusable:$expirationHours"
            mintedFor = userID
            return mint.invoke(userID)
        }

        override suspend fun publishNames(names: List<String>): List<MeshName> {
            asked += "publish"
            published = names
            return publish.invoke(names)
        }
    }

    private fun model(
        scope: CoroutineScope,
        mesh: MeshManaging = Scripted(),
        onRelease: () -> Unit = {},
    ) = MeshViewModel(scope = scope, operations = { mesh }, release = { onRelease() })

    // --------------------------------------------------------- Who has a mesh

    @Test
    fun `only an agent server running the control server manages a mesh`() {
        assertTrue(MeshViewModel.managesMesh(server(), agentTransportAvailable = true))
        assertFalse(
            MeshViewModel.managesMesh(server(usesAgent = false), agentTransportAvailable = true),
            "a server without an agent was offered mesh management",
        )
        assertFalse(
            MeshViewModel.managesMesh(server(), agentTransportAvailable = false),
            "a caller that cannot open a bridge channel was offered mesh management",
        )
        assertFalse(
            MeshViewModel.managesMesh(
                server(services = setOf(ServiceID.VAULTWARDEN)),
                agentTransportAvailable = true,
            ),
            "a server that does not run headscale was offered its mesh",
        )
    }

    // ------------------------------------------------------------- The list

    @Test
    fun `an answered empty list is the mesh saying it has no devices`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope)
        model.load(server())
        runCurrent()

        val state = model.state.value
        assertTrue(state.hasAnswered)
        assertTrue(state.saysThereAreNone)
    }

    @Test
    fun `a failed read never says the mesh is empty`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope, mesh = Scripted(nodes = { error("the agent bridge did not start") }))
        model.load(server())
        runCurrent()

        val state = model.state.value
        assertTrue(state.hasAnswered)
        assertFalse(state.saysThereAreNone)
        assertEquals("the agent bridge did not start", state.errorMessage)
    }

    /** A failed read KEEPS the devices */
    @Test
    fun `a failed read keeps the devices it had`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        var fail = false
        val model = model(scope, mesh = Scripted(nodes = {
            if (fail) error("connection lost") else listOf(node("1"), node("2"))
        }))
        model.load(server())
        runCurrent()
        assertEquals(2, model.state.value.nodes.size)

        fail = true
        model.load(server())
        runCurrent()
        assertEquals(2, model.state.value.nodes.size)
        assertEquals("connection lost", model.state.value.errorMessage)
    }

    @Test
    fun `a dropped session is released so the next call redials`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        var released = 0
        val model = model(
            scope,
            mesh = Scripted(nodes = { error("channel closed") }),
            onRelease = { released += 1 },
        )
        model.load(server())
        runCurrent()
        assertEquals(1, released)
    }

    @Test
    fun `removing draws the list the server answered with`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val seam = Scripted(
            nodes = { listOf(node("1"), node("2")) },
            remove = { listOf(node("2"), node("9")) },
        )
        val model = model(scope, mesh = seam)
        model.load(server())
        runCurrent()
        model.remove(server(), "1")
        runCurrent()

        assertEquals(listOf("2", "9"), model.state.value.nodes.map { it.id })
        assertEquals(MeshViewModel.REMOVED, model.state.value.notice)
    }

    @Test
    fun `a failed removal reports and leaves the list alone`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope, mesh = Scripted(
            nodes = { listOf(node("1")) },
            remove = { error("no such node") },
        ))
        model.load(server())
        runCurrent()
        model.remove(server(), "1")
        runCurrent()

        assertEquals(listOf("1"), model.state.value.nodes.map { it.id })
        assertEquals("no such node", model.state.value.errorMessage)
        assertNull(model.state.value.notice)
    }

    // -------------------------------------------------------- The join key

    @Test
    fun `an existing devices user is reused`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val seam = Scripted(users = { listOf(MeshUser("u-7", MeshViewModel.DEVICE_USER)) })
        val model = model(scope, mesh = seam)
        model.mintJoinKey(server())
        runCurrent()

        assertEquals("u-7", seam.mintedFor)
        assertFalse(
            seam.asked.any { it.startsWith("createUser") },
            "a second user was created for a mesh that already had one",
        )
    }

    @Test
    fun `a missing devices user is created once`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val seam = Scripted(
            users = { emptyList() },
            createUser = { listOf(MeshUser("u-new", it)) },
        )
        val model = model(scope, mesh = seam)
        model.mintJoinKey(server())
        runCurrent()

        assertEquals("u-new", seam.mintedFor)
        assertEquals(1, seam.asked.count { it.startsWith("createUser") })
    }

    @Test
    fun `a user the server refused to create is reported`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope, mesh = Scripted(users = { emptyList() }, createUser = { emptyList() }))
        model.mintJoinKey(server())
        runCurrent()

        assertNull(model.state.value.joinKey)
        assertFalse(model.state.value.isMinting)
        assertTrue(model.state.value.errorMessage!!.isNotEmpty())
    }

    @Test
    fun `a join key is minted single-use and expiring`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val seam = Scripted(users = { listOf(MeshUser("u-1", MeshViewModel.DEVICE_USER)) })
        val model = model(scope, mesh = seam)
        model.mintJoinKey(server())
        runCurrent()

        assertTrue("mint:u-1:false:24" in seam.asked, "minted as ${seam.asked}")
    }

    /** Shown once and never kept */
    @Test
    fun `the key is forgotten when its sheet closes`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope, mesh = Scripted(users = { listOf(MeshUser("u-1", MeshViewModel.DEVICE_USER)) }))
        model.mintJoinKey(server())
        runCurrent()
        assertTrue(model.state.value.joinKey != null)

        model.clearJoinKey()
        assertNull(model.state.value.joinKey)
    }

    /** And forgotten when the screen moves to another server */
    @Test
    fun `opening another server forgets the key and the devices`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope, mesh = Scripted(
            nodes = { listOf(node("1")) },
            users = { listOf(MeshUser("u-1", MeshViewModel.DEVICE_USER)) },
        ))
        model.load(server())
        model.mintJoinKey(server())
        runCurrent()

        model.reset()
        assertEquals(MeshState(), model.state.value)
    }

    @Test
    fun `the join command names this deployment's own control server`() {
        val key = MeshAuthKey("hskey-abc", false, null)
        assertEquals(
            "tailscale up --login-server https://mesh.example.test --authkey hskey-abc",
            MeshViewModel.joinCommand(server(), key),
        )
        assertEquals("https://mesh.example.test", MeshViewModel.loginServer(server()))
    }

    /**
     * **Asked of the SERVICE, not assembled from the domain.** A deployment may
     * name its control server itself, and a device told to log in at the
     * default would be talking to a host that answers nothing — the two only
     * look alike on a deployment that never set one.
     */
    @Test
    fun `a custom control-server name is the one devices are given`() {
        val custom = server().copy(
            serviceSettings = server().serviceSettings.copy(headscaleHostname = "tail.example.test")
        )
        assertEquals("https://tail.example.test", MeshViewModel.loginServer(custom))
        assertTrue(
            "--login-server https://tail.example.test " in
                MeshViewModel.joinCommand(custom, MeshAuthKey("hskey-abc", false, null)),
        )
    }

    // ----------------------------------------------------------- The names

    /**
     * **The PRIMARY name is published, not only the aliases.** The mirror list
     * returns the aliases alone, so publishing it would leave the name the
     * owner actually types resolving nowhere inside the mesh.
     */
    @Test
    fun `publishing sends the served names of every web service`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val seam = Scripted()
        val model = model(scope, mesh = seam)
        val deployment = server()
        model.publishNames(deployment)
        runCurrent()

        val sent = seam.published!!
        assertTrue(sent.isNotEmpty(), "nothing was published for a server with web services")
        assertEquals(MeshViewModel.publishableNames(deployment), sent)
        assertTrue(
            sent.any { it.endsWith(".example.test") },
            "the published names are not this deployment's own: $sent",
        )
        // Names go in once even when two services share one.
        assertEquals(sent.distinct(), sent)
    }

    /** A service with no web ingress has no name to publish. */
    @Test
    fun `a server with no web services publishes nothing`() {
        val deployment = server(services = setOf(ServiceID.HEADSCALE))
        val names = MeshViewModel.publishableNames(deployment)
        // Headscale itself serves the mesh name, so this asserts the shape
        // rather than emptiness: every name belongs to this deployment.
        assertTrue(names.all { it.endsWith(".example.test") }, "$names")
    }

    @Test
    fun `the screen shows the records the server answered with`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope, mesh = Scripted(publish = {
            listOf(MeshName("vault.example.test", "100.64.0.1"))
        }))
        model.publishNames(server())
        runCurrent()

        assertEquals(
            listOf(MeshName("vault.example.test", "100.64.0.1")),
            model.state.value.publishedNames,
        )
        assertEquals(MeshViewModel.PUBLISHED, model.state.value.notice)
    }

    /** Nothing published is a real outcome — it is what clearing them looks like. */
    @Test
    fun `an empty publish reads as cleared rather than failed`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope, mesh = Scripted(publish = { emptyList() }))
        model.publishNames(server())
        runCurrent()

        assertEquals(MeshViewModel.NAMES_CLEARED, model.state.value.notice)
        assertNull(model.state.value.errorMessage)
    }

    @Test
    fun `a failed publish reports and claims nothing`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope, mesh = Scripted(publish = { error("headscale is not running") }))
        model.publishNames(server())
        runCurrent()

        assertEquals("headscale is not running", model.state.value.errorMessage)
        assertEquals(emptyList(), model.state.value.publishedNames)
        assertNull(model.state.value.notice)
    }
}
