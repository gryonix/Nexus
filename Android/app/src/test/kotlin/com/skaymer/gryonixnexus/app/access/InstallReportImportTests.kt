package com.skaymer.gryonixnexus.app.access

import com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.ExecResult
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.addingNode
import com.skaymer.gryonixnexus.servercontrol.NodeCapability
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** Reading a machine's own copy of its install report */
class InstallReportImportTests {
    private val secrets = InMemorySecretStore()

    private val report: String =
        checkNotNull(javaClass.getResourceAsStream("/install-report-single.txt"))
            .bufferedReader().readText()

    private fun server(
        id: String = "S-1",
        domain: String = "example.com",
        topology: Topology = Topology.SINGLE_HOST,
        homeWGAddress: String? = null,
    ) = Deployment(
        id = id,
        name = "middle",
        topology = topology,
        domain = domain,
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        homeWGAddress = homeWGAddress,
    )

    private class Scripted(private val answers: Map<SSHHostID, String>) : SSHCommandRunner {
        val asked = mutableListOf<Pair<String, SSHHostID>>()
        var failWith: Throwable? = null

        override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult {
            asked += command to host
            failWith?.let { throw it }
            return ExecResult(exitCode = 0, stdout = answers[host].orEmpty(), stderr = "")
        }

        override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> =
            emptyFlow()

        override suspend fun fireAndForget(command: String, host: SSHHostID) = Unit
        override suspend fun disconnect() = Unit
    }

    private fun importer(
        runner: SSHCommandRunner,
        onDomainFound: (Deployment, String) -> Unit = { _, _ -> },
    ) = InstallReportImport(
        runners = { runner },
        reports = { InstallReportStore(secrets, it.id) },
        onDomainFound = onDomainFound,
    )

    private fun stored(id: String = "S-1") = InstallReportStore(secrets, id)

    @Test
    fun `the machines own copy is filed under its host`() = runTest {
        val runner = Scripted(mapOf(SSHHostID.VPS to report))
        assertTrue(importer(runner).importIfNeeded(server()))
        assertEquals(listOf("single"), stored().load().map { it.host })
        assertTrue("Nextcloud" in stored().load().single().text)
    }

    @Test
    fun `the report is read with the catalog command and nothing else`() = runTest {
        val runner = Scripted(mapOf(SSHHostID.VPS to report))
        importer(runner).importIfNeeded(server())
        val (command, host) = runner.asked.single()
        assertEquals(
            com.skaymer.gryonixnexus.servercontrol.CommandCatalog.INSTALL_REPORT,
            command
        )
        assertEquals(SSHHostID.VPS, host)
        assertFalse("sudo" in command)
    }

    /** Once per machine, not once per open */
    @Test
    fun `a machine already asked is not asked again`() = runTest {
        val runner = Scripted(mapOf(SSHHostID.VPS to report))
        val import = importer(runner)
        import.importIfNeeded(server())
        import.importIfNeeded(server())
        assertEquals(1, runner.asked.size)
    }

    @Test
    fun `a relay pair is asked on both machines`() = runTest {
        val runner = Scripted(
            mapOf(SSHHostID.VPS to "VPS: report", SSHHostID.HOME to report)
        )
        val pair = server(
            topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
            homeWGAddress = "10.8.0.2",
        )
        importer(runner).importIfNeeded(pair)
        assertEquals(listOf(SSHHostID.VPS, SSHHostID.HOME), runner.asked.map { it.second })
        assertEquals(listOf("vps", "home"), stored().load().map { it.host })
    }

    @Test
    fun `a single host that gained a worker still files under single`() = runTest {
        val single = server()
        val entry = single.nodes.single()
        val grown = single.addingNode(
            DeploymentNode(
                id = "dddddddd-dddd-dddd-dddd-dddddddddddd",
                endpoint = HostEndpoint(host = "203.0.113.41", user = "root"),
                capabilities = setOf(NodeCapability.WORKER),
                routedThrough = entry.id,
            )
        )
        assertTrue(grown.hasHomeHost, "the added worker is what made this question misfire")
        assertFalse(grown.hasRelayIngress, "and there is still no relay in front of anything")

        val runner = Scripted(mapOf(SSHHostID.VPS to report))
        importer(runner).importIfNeeded(grown)

        assertEquals(
            listOf("single"),
            stored().load().map { it.host },
            "the entry machine's report moved out from under everything stored for it",
        )
    }

    @Test
    fun `a relay pair still files its entry machine under vps`() = runTest {
        val pair = server(
            topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
            homeWGAddress = "10.8.0.2",
        )
        val runner = Scripted(mapOf(SSHHostID.VPS to "VPS: report"))
        importer(runner).importIfNeeded(pair)
        assertEquals(listOf("vps"), stored().load().map { it.host })
    }

    /** Having a copy is not having the CURRENT one */
    @Test
    fun `a report that has moved on replaces the stored one`() = runTest {
        stored().save("single", "an older report")
        val runner = Scripted(mapOf(SSHHostID.VPS to report))
        assertTrue(importer(runner).importIfNeeded(server()))
        assertEquals(report.trim(), stored().load().single().text.trim())
    }

    @Test
    fun `an unchanged report is not written again`() = runTest {
        val runner = Scripted(mapOf(SSHHostID.VPS to report))
        importer(runner).importIfNeeded(server())
        val first = stored().load().single()
        val second = importer(runner).importIfNeeded(server())
        assertFalse(second)
        assertEquals(first, stored().load().single())
    }

    @Test
    fun `an unreachable machine leaves the stored report alone`() = runTest {
        stored().save("single", report)
        val runner = Scripted(emptyMap()).apply { failWith = IllegalStateException("no route") }
        assertFalse(importer(runner).importIfNeeded(server()))
        assertEquals(report, stored().load().single().text)
    }

    @Test
    fun `an empty answer stores nothing`() = runTest {
        val runner = Scripted(mapOf(SSHHostID.VPS to "   \n"))
        assertFalse(importer(runner).importIfNeeded(server()))
        assertTrue(stored().load().isEmpty())
    }

    /** The server states its domain, and the app takes it */
    @Test
    fun `the domain the report states is offered to the fleet`() = runTest {
        val found = mutableListOf<String>()
        val runner = Scripted(mapOf(SSHHostID.VPS to report))
        importer(runner) { _, domain -> found += domain }.importIfNeeded(server(domain = ""))
        assertEquals(listOf("example.com"), found)
    }

    @Test
    fun `an already stored report still offers its domain`() = runTest {
        stored().save("single", report)
        val found = mutableListOf<String>()
        val runner = Scripted(mapOf(SSHHostID.VPS to report))
        importer(runner) { _, domain -> found += domain }.importIfNeeded(server(domain = ""))
        assertEquals(listOf("example.com"), found)
    }
}
