package com.skaymer.gryonixnexus.profile

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ProxyLinkConfigGoldenTest {
    private data class Row(val kind: String, val input: String, val answer: List<String>)

    private fun golden(): List<Row> {
        val text = checkNotNull(javaClass.getResourceAsStream("/swift-proxy-links.tsv")) {
            "the golden is missing — capture it with `swift run proxy-link-golden`"
        }.bufferedReader().readText()

        val rows = text.lineSequence().filter { it.isNotBlank() }.map { line ->
            val parts = line.split("\t")
            require(parts.size >= 3) { "malformed golden row: $line" }
            Row(kind = parts[0], input = unescape(parts[1]), answer = parts.drop(2))
        }.toList()

        assertTrue(rows.size >= 12, "the golden is implausibly short: ${rows.size} rows")
        assertTrue(rows.any { it.answer[0] == "ok" }, "the golden has no accepted links")
        assertTrue(rows.any { it.answer[0] == "fail" }, "the golden has no refusals")
        return rows
    }

    private fun unescape(field: String): String {
        val out = StringBuilder(field.length)
        var i = 0
        while (i < field.length) {
            val c = field[i]
            if (c == '\\' && i + 1 < field.length) {
                when (field[i + 1]) {
                    'n' -> { out.append('\n'); i += 2; continue }
                    't' -> { out.append('\t'); i += 2; continue }
                    '\\' -> { out.append('\\'); i += 2; continue }
                }
            }
            out.append(c)
            i++
        }
        return out.toString()
    }

    private fun kind(name: String): ProxyLinkConfig.Kind = when (name) {
        "shadowsocks" -> ProxyLinkConfig.Kind.SHADOWSOCKS
        "vless" -> ProxyLinkConfig.Kind.VLESS
        else -> error("the golden names a kind this port has no case for: $name")
    }

    private fun credentialOf(link: ProxyLinkConfig): List<String> =
        when (val c = link.credential) {
            is ProxyLinkConfig.Credential.Shadowsocks ->
                listOf("shadowsocks", c.method, c.password)
            is ProxyLinkConfig.Credential.Vless -> listOf(
                "vless", c.uuid, c.security, c.sni, c.fingerprint,
                c.publicKey, c.shortID, c.flow,
                c.network, c.path, c.host, c.serviceName,
            )
        }

    private fun reasonOf(failure: ProxyLinkConfig.ParseFailure): String = when (failure) {
        is ProxyLinkConfig.ParseFailure.NoLink -> "noLink"
        is ProxyLinkConfig.ParseFailure.NoEndpoint -> "noEndpoint"
        is ProxyLinkConfig.ParseFailure.NoCredential -> "noCredential"
        is ProxyLinkConfig.ParseFailure.UnsupportedTransport ->
            "unsupportedTransport\t${failure.name}"
    }

    @Test
    fun `every link is read the way Swift reads it`() {
        for (row in golden()) {
            val where = "for ${row.kind} on <${row.input}>"
            val parsed = try {
                ProxyLinkConfig.parse(row.input, kind(row.kind))
            } catch (refused: ProxyLinkConfig.ParseException) {
                assertEquals("fail", row.answer[0], "$where — this port refused it")
                assertEquals(row.answer.drop(1).joinToString("\t"), reasonOf(refused.failure),
                    "$where — the reason")
                continue
            }
            assertEquals("ok", row.answer[0], "$where — this port accepted it and Swift did not")
            assertEquals(row.answer[1], parsed.endpoint, "$where — endpoint")
            assertEquals(row.answer[2], parsed.label, "$where — label")
            assertEquals(row.answer.drop(3), credentialOf(parsed), "$where — credential")
        }
    }
}
