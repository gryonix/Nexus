package com.skaymer.gryonixnexus.app.install

import com.skaymer.gryonixnexus.app.access.InstallReportStore
import com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.core.ArtifactKind
import com.skaymer.gryonixnexus.core.GeneratedBundle
import com.skaymer.gryonixnexus.core.ServerRole
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertNotSame
import kotlin.test.assertSame
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** What counts as "the same install" */
class InstallRegistryTests {
    private fun registry(scope: kotlinx.coroutines.CoroutineScope) =
        InstallRegistry(
            scope,
            InstallSessions(InMemorySecretStore()),
            reports = { InstallReportStore(InMemorySecretStore(), it.id) },
        )

    private fun bundle(body: String, note: String = "") = GeneratedBundle(
        artifacts = listOf(
            Artifact(
                fileName = "setup.sh",
                kind = ArtifactKind.SHELL_SCRIPT,
                contents = body,
                summary = "setup",
                server = ServerRole.SINGLE_HOST,
            ),
            Artifact(
                fileName = "dns-records.txt",
                kind = ArtifactKind.DNS_RECORD,
                contents = note,
                summary = "records",
            ),
        )
    )

    private val server = Deployment(
        id = "S-1",
        name = "example.com",
        topology = Topology.SINGLE_HOST,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.10", user = "server-user"),
    )

    /** Reopening the screen finds the run that is already going */
    @Test
    fun `the same scripts resume the same install`() = runTest {
        val registry = registry(this)
        val first = registry.model(server, bundle("echo one"), null)
        val second = registry.model(server, bundle("echo one"), null)
        assertSame(first, second)
    }

    /** The DNS artefact is not what runs on the machine */
    @Test
    fun `a note that changed is not a new install`() = runTest {
        val registry = registry(this)
        val first = registry.model(server, bundle("echo one", note = "A record"), null)
        val second = registry.model(server, bundle("echo one", note = "A and MX records"), null)
        assertSame(first, second)
    }

    /** Regenerated scripts are a different installation of the same server */
    @Test
    fun `changed scripts start a fresh install`() = runTest {
        val registry = registry(this)
        val first = registry.model(server, bundle("echo one"), null)
        val second = registry.model(server, bundle("echo two"), null)
        assertNotSame(first, second)
    }

    @Test
    fun `another server gets its own install`() = runTest {
        val registry = registry(this)
        val first = registry.model(server, bundle("echo one"), null)
        val second = registry.model(server.copy(id = "S-2"), bundle("echo one"), null)
        assertNotSame(first, second)
    }
}
