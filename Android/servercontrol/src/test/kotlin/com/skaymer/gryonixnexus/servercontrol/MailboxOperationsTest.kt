package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class MailboxOperationsTest {
    private fun deployment(
        topology: Topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        services: Set<ServiceID> = setOf(ServiceID.DOCKER_MAILSERVER),
    ) = Deployment(
        id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        name = "Mail",
        topology = topology,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.4", user = "admin"),
        homeWGAddress = if (topology == Topology.VPS_RELAY_WITH_HOME_BACKEND) "10.8.0.2" else null,
        services = services,
    )

    private fun ops(runner: FakeSSHCommandRunner, deployment: Deployment = deployment()) =
        MailboxOperations(runner, deployment)

    @Test
    fun `the listing uses the wrapper literal on the machine the engine runs on`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("dms-mailbox.sh list", stdout = "* user@example.com ( 0 / ~ ) [0%]")

        val mailboxes = ops(runner).list()

        assertEquals(listOf("user@example.com"), mailboxes.map { it.address })
        assertEquals("sudo /opt/gryonixnexus-dms-mailbox.sh list", runner.calls.first().command)
        assertEquals(SSHHostID.HOME, runner.calls.first().host)
    }

    @Test
    fun `in scenario A the listing runs on the single host`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("dms-mailbox.sh list", stdout = "")
        ops(runner, deployment(topology = Topology.SINGLE_HOST)).list()
        assertEquals(SSHHostID.VPS, runner.calls.first().host)
    }

    @Test
    fun `a stale whitelist surfaces as an outdated sudoers, not a broken command`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("dms-mailbox.sh list", exitCode = 1, stderr = "sudo: a password is required")
        assertFailsWith<ServerControlError.SudoPasswordRequired> { ops(runner).list() }
    }

    @Test
    fun `every action refuses a server without the engine`() = runTest {
        val runner = FakeSSHCommandRunner()
        val without = ops(runner, deployment(services = emptySet()))
        assertFalse(without.isAvailable)
        assertFailsWith<ServerControlError.NotConfigured> { without.list() }
        assertFailsWith<ServerControlError.NotConfigured> { without.add("a@example.com", "pw") }
        assertFailsWith<ServerControlError.NotConfigured> { without.delete("a@example.com") }
        assertFailsWith<ServerControlError.NotConfigured> {
            without.setPassword("a@example.com", "pw")
        }
        assertTrue(runner.calls.isEmpty(), "nothing may reach a server that has no wrapper")
    }

    @Test
    fun `add sends the password on stdin and never in argv`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("dms-mailbox.sh add", stdout = "GRYONIXNEXUS_MAILBOX_DONE\n")

        ops(runner).add("user@example.com", "s3cr3t")

        val sent = runner.calls.first().command
        assertEquals("sudo /opt/gryonixnexus-dms-mailbox.sh add 'user@example.com'", sent)
        assertEquals(listOf("s3cr3t"), runner.fed)
    }

    @Test
    fun `add refuses an address the wrapper would reject`() = runTest {
        val runner = FakeSSHCommandRunner()
        assertFailsWith<ServerControlError.NotConfigured> {
            ops(runner).add("not an address", "pw")
        }
        assertTrue(runner.calls.isEmpty())
    }

    @Test
    fun `add refuses an empty password before the round-trip`() = runTest {
        val runner = FakeSSHCommandRunner()
        assertFailsWith<ServerControlError.NotConfigured> { ops(runner).add("user@example.com", "") }
        assertTrue(runner.calls.isEmpty())
    }

    @Test
    fun `a failed add echoes neither the command nor the password`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("dms-mailbox.sh add", exitCode = 1, stderr = "adduser: failed for s3cr3t")

        val error = assertFailsWith<ServerControlError> {
            ops(runner).add("user@example.com", "s3cr3t")
        }
        assertFalse(error.toString().contains("s3cr3t"), "the secret must be redacted")
        assertTrue(error.toString().contains("add mailbox"), "the label stands in for the command")
    }

    @Test
    fun `a missing marker is a failure even on exit zero`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("dms-mailbox.sh add", stdout = "nothing to report")
        assertFailsWith<ServerControlError.CommandFailed> {
            ops(runner).add("user@example.com", "pw")
        }
    }

    @Test
    fun `delete uses the wrapper and carries no stdin`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("dms-mailbox.sh del", stdout = "GRYONIXNEXUS_MAILBOX_DONE\n")

        ops(runner).delete("user@example.com")

        assertEquals(
            "sudo /opt/gryonixnexus-dms-mailbox.sh del 'user@example.com'",
            runner.calls.first().command,
        )
    }

    @Test
    fun `the engine's coloured failure reaches the user as plain text`() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub(
            "dms-mailbox.sh del",
            exitCode = 1,
            stderr = "\u001B[1;31mERROR\u001B[0m delmailuser: no such mailbox\n",
        )

        val error = assertFailsWith<ServerControlError> { ops(runner).delete("user@example.com") }
        val text = error.toString()
        assertTrue(text.contains("ERROR delmailuser: no such mailbox"))
        assertFalse(text.contains("\u001B"), "no escape sequences in an alert")
    }
}
