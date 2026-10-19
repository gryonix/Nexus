package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.catalog.Topology
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.nio.file.Path
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TerminalDirectHostTests {
    @TempDir
    lateinit var dir: Path

    private fun store() = TerminalDirectHostStore(File(dir.toFile(), "terminal-hosts.json"))

    /** A blank name is not a blank row */
    @Test
    fun `a host with no name is called by its address`() {
        assertEquals("203.0.113.10", TerminalDirectHost(host = "203.0.113.10", username = "root").title)
        assertEquals(
            "the box",
            TerminalDirectHost(name = "  the box  ", host = "203.0.113.10", username = "root").title,
        )
    }

    @Test
    fun `it presents as a single-host deployment with no services`() {
        val host = TerminalDirectHost(
            name = "desk", host = "10.0.0.5", port = 2222, username = "admin",
        )
        val deployment = host.deployment
        assertEquals(host.id, deployment.id)
        assertEquals("desk", deployment.name)
        assertEquals(Topology.SINGLE_HOST, deployment.topology)
        assertEquals("10.0.0.5", deployment.entry.host)
        assertEquals(2222, deployment.entry.port)
        assertEquals("admin", deployment.entry.user)
        assertTrue(deployment.services.isEmpty())
        assertEquals("", deployment.domain)
        assertTrue(!deployment.usesAgent)
    }

    @Test
    fun `saving a host again replaces it rather than adding a second`() {
        val store = store()
        val host = TerminalDirectHost(host = "10.0.0.5", username = "root")
        store.upsert(host)
        store.upsert(host.copy(name = "desk", port = 2222))
        val saved = store.load().single()
        assertEquals(host.id, saved.id)
        assertEquals("desk", saved.name)
        assertEquals(2222, saved.port)
    }

    @Test
    fun `removing takes only the host named`() {
        val store = store()
        val keep = TerminalDirectHost(host = "10.0.0.5", username = "root")
        val drop = TerminalDirectHost(host = "10.0.0.6", username = "root")
        store.upsert(keep)
        store.upsert(drop)
        store.remove(drop.id)
        assertEquals(listOf(keep.id), store.load().map { it.id })
    }

    @Test
    fun `a corrupt file reads as no hosts`() {
        val file = File(dir.toFile(), "terminal-hosts.json")
        file.writeText("{ not json")
        assertEquals(emptyList(), TerminalDirectHostStore(file).load())
    }

    /** And one written by a NEWER build still opens */
    @Test
    fun `an unknown field does not empty the list`() {
        val file = File(dir.toFile(), "terminal-hosts.json")
        file.writeText("""[{"id":"a","host":"10.0.0.5","username":"root","somethingNewer":1}]""")
        assertEquals("10.0.0.5", TerminalDirectHostStore(file).load().single().host)
    }
}
