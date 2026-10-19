package com.skaymer.gryonixnexus.agentclient

import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class SchemaIsReachableTest {
    private val schema = File("../../Proto/gryonixnexusd/v1/gryonixnexusd.proto")
    private val client = File("src/main/kotlin/com/skaymer/gryonixnexus/agentclient/AgentClient.kt")

    /** `service Foo { rpc Bar(...) }` → "/gryonixnexusd.v1.Foo/Bar" */
    private fun declaredPaths(): List<String> {
        val text = schema.readText()
        val paths = mutableListOf<String>()
        var service: String? = null
        for (raw in text.lineSequence()) {
            val line = raw.trim()
            Regex("""^service\s+(\w+)\s*\{""").find(line)?.let { service = it.groupValues[1] }
            if (line == "}") service = null
            Regex("""^rpc\s+(\w+)\s*\(""").find(line)?.let { match ->
                service?.let { paths += "/gryonixnexusd.v1.$it/${match.groupValues[1]}" }
            }
        }
        return paths
    }

    @Test
    fun `the schema is where the paths come from, and it parses`() {
        assertTrue(schema.exists(), "the schema must be readable from the module directory: ${schema.absolutePath}")
        val paths = declaredPaths()
        assertTrue(paths.size > 40, "expected the schema to declare many RPCs, found ${paths.size}")
        assertTrue(paths.contains("/gryonixnexusd.v1.Install/InstallService"), paths.take(5).toString())
    }

    @Test
    fun `every rpc the schema declares is called by this client`() {
        val source = client.readText()
        val missing = declaredPaths().filterNot { source.contains("\"$it\"") }
        assertEquals(
            emptyList(), missing,
            "these RPCs exist in the schema but no verb here calls them — on a host they are simply unreachable",
        )
    }

    @Test
    fun `every path this client calls is declared by the schema`() {
        val declared = declaredPaths().toSet()
        val called = Regex(""""(/gryonixnexusd\.v1\.[A-Za-z]+/[A-Za-z]+)"""")
            .findAll(client.readText())
            .map { it.groupValues[1] }
            .toSet()
        assertTrue(called.isNotEmpty(), "found no RPC paths in the client at all")
        assertEquals(
            emptySet(), called - declared,
            "these paths are called but the schema declares no such RPC",
        )
    }

    /** `service Foo { rpc Bar(Req) returns (Resp); }` → path to "Resp" */
    private fun declaredResponses(): Map<String, String> {
        val text = schema.readText()
        val responses = mutableMapOf<String, String>()
        var service: String? = null
        for (raw in text.lineSequence()) {
            val line = raw.trim()
            Regex("""^service\s+(\w+)\s*\{""").find(line)?.let { service = it.groupValues[1] }
            if (line == "}") service = null
            Regex("""^rpc\s+(\w+)\s*\([^)]*\)\s*returns\s*\(\s*(?:stream\s+)?(\w+)""")
                .find(line)?.let { match ->
                    service?.let {
                        responses["/gryonixnexusd.v1.$it/${match.groupValues[1]}"] = match.groupValues[2]
                    }
                }
        }
        return responses
    }

    @Test
    fun `every verb decodes with the response type the schema declares`() {
        val source = client.readText()
        val responses = declaredResponses()
        assertTrue(responses.size > 40, "the harness parsed ${responses.size} responses — it must see them all")

        val wrong = mutableListOf<String>()
        for ((path, expected) in responses) {
            val at = source.indexOf("\"$path\"")
            if (at < 0) continue // the reachability test above owns that failure
            val next = source.indexOf("\"/gryonixnexusd.v1.", at + 1)
            val window = source.substring(at, if (next < 0) source.length else next)
            val adapter = Regex("""(\w+)\.ADAPTER""").find(window)?.groupValues?.get(1)
            if (adapter != expected) wrong += "$path decodes $adapter, schema says $expected"
        }

        assertEquals(emptyList(), wrong, "a wrong adapter decodes into nonsense rather than failing")
    }
}
