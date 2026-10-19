package com.skaymer.gryonixnexus.profile

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class VPNLinkGoldenTest {
    private data class Row(val protocol: String, val input: String, val expected: String?)

    private fun golden(): List<Row> {
        val text = checkNotNull(javaClass.getResourceAsStream("/swift-handoff-links.tsv")) {
            "the golden is missing — capture it with `swift run handoff-golden`"
        }.bufferedReader().readText()

        val rows = text.lineSequence().filter { it.isNotBlank() }.map { line ->
            val parts = line.split("\t")
            require(parts.size == 3 || parts.size == 4) { "malformed golden row: $line" }
            Row(
                protocol = parts[0],
                input = unescape(parts[1]),
                expected = if (parts[2] == "openIn") parts[3] else null,
            )
        }.toList()

        assertTrue(rows.size >= 15, "the golden is implausibly short: ${rows.size} rows")
        assertTrue(rows.any { it.expected != null }, "the golden has no accepted links")
        assertTrue(rows.any { it.expected == null }, "the golden has no refusals")
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

    private fun scheme(protocol: String): String = when (protocol) {
        "shadowsocks" -> "ss"
        "xray-reality" -> "vless"
        else -> error("the golden names a protocol with no link scheme: $protocol")
    }

    @Test
    fun `every link this app produces is the one Swift produces`() {
        for (row in golden()) {
            val actual = VPNLink.firstLink(row.input, scheme(row.protocol))
            assertEquals(
                row.expected, actual,
                "for ${row.protocol} on <${row.input}>",
            )
        }
    }

    @Test
    fun `the credential half is never touched by the fragment encoding`() {
        val link = VPNLink.firstLink("ss://YWVzOnB3@vpn.example.com:8388#iPhone Марины", "ss")
        assertNotNull(link)
        assertTrue(
            link!!.startsWith("ss://YWVzOnB3@vpn.example.com:8388#"),
            "the half before the fragment changed: $link",
        )
    }

    @Test
    fun `a line of the wrong scheme is not a link`() {
        assertNull(VPNLink.firstLink("ss://YWVzOnB3@h:8388#p", "vless"))
        assertNull(VPNLink.firstLink("vless://u@h:443#p", "ss"))
    }
}
