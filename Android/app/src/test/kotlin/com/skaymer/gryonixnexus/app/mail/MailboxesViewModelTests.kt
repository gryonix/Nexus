package com.skaymer.gryonixnexus.app.mail

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.Mailbox
import com.skaymer.gryonixnexus.servercontrol.MailboxManaging
import java.io.IOException
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** The mailboxes of the docker-mailserver engine */
class MailboxesViewModelTests {
    @Test
    fun `only an accepted password reaches the vault and double tap is refused`() = runTest {
        val engine = Scripted()
        val saved = mutableListOf<String>()
        val vm = MailboxesViewModel(this, { engine }, savePassword = { _, address, password ->
            assertEquals(listOf("password $address"), engine.asked)
            saved += password
        })
        val deployment = server().copy(usesAgent = true)
        vm.setPassword(deployment, "owner@example.test", "new-password")
        vm.setPassword(deployment, "owner@example.test", "second-password")
        runCurrent()
        assertEquals(listOf("new-password"), saved)
        engine.failAction = true
        vm.setPassword(deployment, "owner@example.test", "refused-password")
        runCurrent()
        assertEquals(listOf("new-password"), saved)
    }

    @Test
    fun `vault failure does not retry a successful mailbox change`() = runTest {
        val engine = Scripted()
        val vm = MailboxesViewModel(this, { engine }, savePassword = { _, _, _ -> error("secret must not be shown") })
        vm.add(server().copy(usesAgent = true), "owner@example.test", "new-password")
        runCurrent()
        assertEquals(1, engine.asked.size)
        assertEquals("owner@example.test", vm.state.value.mailboxes.single().address)
        assertEquals(MailboxesViewModel.VAULT_FAILURE, vm.state.value.errorMessage)
        assertFalse(vm.state.value.isWorking)
    }

    @Test
    fun `mailbox identity matches the other platform and password edits keep the id`() {
        val entry = MailboxVault.entry(server(), "Owner@Example.Test", "one", 100, "phone")
        assertEquals("single|Mailbox: owner@example.test", entry.id)
        assertEquals("owner@example.test", entry.login)
        assertEquals(100L, entry.updated_at)
        assertEquals(entry.id, MailboxVault.entry(server(), "owner@example.test", "two", 200, "other").id)
    }

    private fun server(
        services: Set<ServiceID> = setOf(ServiceID.DOCKER_MAILSERVER),
        additionalDomains: List<String> = emptyList(),
    ) = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        services = services,
        additionalDomains = additionalDomains,
    )

    private class Scripted(
        var listing: List<Mailbox> = emptyList(),
        var failListing: Boolean = false,
        var failAction: Boolean = false,
    ) : MailboxManaging {
        val asked = mutableListOf<String>()
        var reads = 0

        override val isAvailable: Boolean get() = true

        override suspend fun list(): List<Mailbox> {
            reads += 1
            if (failListing) throw IOException("the wrapper did not answer")
            return listing
        }

        override suspend fun add(address: String, password: String) {
            asked += "add $address"
            if (failAction) throw IOException("invalid address")
            listing = listing + Mailbox(address)
        }

        override suspend fun delete(address: String) {
            asked += "delete $address"
            if (failAction) throw IOException("no such mailbox")
            listing = listing.filterNot { it.address == address }
        }

        override suspend fun setPassword(address: String, password: String) {
            asked += "password $address"
            if (failAction) throw IOException("refused")
        }
    }

    private fun model(scope: CoroutineScope, engine: Scripted) =
        MailboxesViewModel(scope = scope, mailboxes = { engine })

    // ---------------------------------------------------------- The screen

    @Test
    fun `the engine decides whether the screen exists at all`() {
        assertTrue(MailboxesViewModel.hasEngine(server()))
        assertFalse(MailboxesViewModel.hasEngine(server(services = setOf(ServiceID.MAILCOW))))
    }

    @Test
    fun `mail is offered on every domain the deployment serves`() {
        assertEquals(
            listOf("example.test", "second.test"),
            MailboxesViewModel.domains(server(additionalDomains = listOf("second.test"))),
        )
    }

    // ----------------------------------------------------------- The reads

    @Test
    fun `only an answered, unfailed, finished read says there are none`() =
        runTest(StandardTestDispatcher()) {
            val quiet = model(this, Scripted())
            quiet.load(server())
            runCurrent()
            assertTrue(quiet.state.value.saysThereAreNone)

            val broken = model(this, Scripted(failListing = true))
            broken.load(server())
            runCurrent()
            // Answered and empty, and NOT a sentence about the server.
            assertFalse(broken.state.value.saysThereAreNone)
            assertEquals("the wrapper did not answer", broken.state.value.errorMessage)
        }

    @Test
    fun `a listing that failed keeps the mailboxes already on screen`() =
        runTest(StandardTestDispatcher()) {
            val engine = Scripted(listing = listOf(Mailbox("me@example.test")))
            val mailboxes = model(this, engine)
            mailboxes.load(server())
            runCurrent()

            engine.failListing = true
            mailboxes.load(server())
            runCurrent()

            assertEquals(listOf("me@example.test"), mailboxes.state.value.mailboxes.map { it.address })
            assertEquals("the wrapper did not answer", mailboxes.state.value.errorMessage)
        }

    // --------------------------------------------------------- The changes

    @Test
    fun `every change is followed by a re-read`() = runTest(StandardTestDispatcher()) {
        val engine = Scripted()
        val mailboxes = model(this, engine)
        mailboxes.add(server(), "new@example.test", "hunter2hunter2")
        runCurrent()

        assertEquals(listOf("add new@example.test"), engine.asked)
        assertEquals(1, engine.reads)
        assertEquals(listOf("new@example.test"), mailboxes.state.value.mailboxes.map { it.address })
    }

    @Test
    fun `a change that failed says so and does not pretend it landed`() =
        runTest(StandardTestDispatcher()) {
            val engine = Scripted(failAction = true)
            val mailboxes = model(this, engine)
            mailboxes.delete(server(), "me@example.test")
            runCurrent()

            assertEquals("no such mailbox", mailboxes.state.value.errorMessage)
            assertFalse(mailboxes.state.value.isWorking)
            assertEquals(0, engine.reads)
        }

    // -------------------------------------------------------- The addresses

    @Test
    fun `an address the wrapper would refuse never leaves the app`() {
        assertTrue(MailboxesViewModel.canCreate("me@example.test", "hunter2hunter2"))
        assertFalse(MailboxesViewModel.canCreate("me @example.test", "hunter2hunter2"))
        assertFalse(MailboxesViewModel.canCreate("@example.test", "hunter2hunter2"))
    }

    @Test
    fun `a password shorter than the server accepts is refused here`() {
        assertFalse(MailboxesViewModel.canCreate("me@example.test", "short"))
        assertFalse(MailboxesViewModel.canChangePassword("short"))
        assertTrue(MailboxesViewModel.canChangePassword("longenough"))
    }

    @Test
    fun `a generated password carries no look-alike characters`() {
        val password = MailboxPassword.generate()
        assertEquals(20, password.length)
        assertTrue(password.none { it in "0O1lI" })
        // And it is not the same one twice.
        assertFalse(password == MailboxPassword.generate())
    }
}
