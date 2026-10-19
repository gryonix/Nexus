package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.core.DNSRecord
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ConfigurationExportFormatGoldenTest {
    private val golden: Map<String, String> by lazy {
        val text = checkNotNull(javaClass.getResourceAsStream("/swift-config-export.json")) {
            "swift-config-export.json missing — run Tools/dump-config-export-golden.sh"
        }.bufferedReader().readText()
        val entries = mutableMapOf<String, String>()
        val regex = Regex(""""([A-Za-z]+)"\s*:\s*"((?:[^"\\]|\\.)*)"""")
        for (match in regex.findAll(text)) {
            entries[match.groupValues[1]] = unescape(match.groupValues[2])
        }
        val fields = Regex("""^\s{2}"[A-Za-z]+"\s*:""", RegexOption.MULTILINE).findAll(text).count()
        check(entries.size == fields) {
            "the golden holds $fields fields and only ${entries.size} parsed"
        }
        entries
    }

    private fun unescape(value: String): String = buildString {
        var index = 0
        while (index < value.length) {
            val ch = value[index]
            if (ch != '\\') { append(ch); index++; continue }
            when (val escape = value[index + 1]) {
                'n' -> { append('\n'); index += 2 }
                't' -> { append('\t'); index += 2 }
                'r' -> { append('\r'); index += 2 }
                'u' -> {
                    append(value.substring(index + 2, index + 6).toInt(16).toChar())
                    index += 6
                }
                else -> { append(escape); index += 2 }
            }
        }
    }

    private val zone = "example.com"

    private val records = listOf(
        DNSRecord(name = zone, type = DNSRecord.RecordType.A, value = "203.0.113.10"),
        DNSRecord(name = "mail.$zone", type = DNSRecord.RecordType.A, value = "203.0.113.10"),
        DNSRecord(name = zone, type = DNSRecord.RecordType.MX, value = "mail.$zone.", priority = 10),
        DNSRecord(name = zone, type = DNSRecord.RecordType.TXT, value = "v=spf1 mx -all"),
        DNSRecord(name = "elsewhere.test", type = DNSRecord.RecordType.A, value = "198.51.100.7"),
        DNSRecord(name = "notexample.com", type = DNSRecord.RecordType.A, value = "198.51.100.8"),
    )

    private val ports = listOf(
        OpenPortRequirement(22, OpenPortRequirement.Proto.TCP, "SSH"),
        OpenPortRequirement(25, OpenPortRequirement.Proto.TCP, "Mailcow (SMTP)"),
        OpenPortRequirement(443, OpenPortRequirement.Proto.TCP, "Caddy (HTTPS), Nextcloud"),
        OpenPortRequirement(51820, OpenPortRequirement.Proto.UDP, "WireGuard"),
        OpenPortRequirement(8443, OpenPortRequirement.Proto.TCP, """Panel "admin""""),
    )

    @Test
    fun `the records a person pastes match the bytes Swift writes`() {
        assertEquals(
            golden.getValue("recordsText"),
            ConfigurationExportFormat.recordsText(records, zone),
        )
    }

    @Test
    fun `with no zone every name survives whole`() {
        assertEquals(
            golden.getValue("recordsTextNoZone"),
            ConfigurationExportFormat.recordsText(records, ""),
        )
    }

    @Test
    fun `the port list and both files match the bytes Swift writes`() {
        assertEquals(golden.getValue("portsText"), ConfigurationExportFormat.portsText(ports))

        val txt = ConfigurationExportFormat.portsTextArtifact(ports, "TXT-SUMMARY")
        assertEquals(golden.getValue("portsTxtFileName"), txt.fileName)
        assertEquals(golden.getValue("portsTxtSummary"), txt.summary)
        assertEquals(golden.getValue("portsTxt"), txt.contents)

        val csv = ConfigurationExportFormat.portsCSVArtifact(ports, "CSV-SUMMARY")
        assertEquals(golden.getValue("portsCsvFileName"), csv.fileName)
        assertEquals(golden.getValue("portsCsvSummary"), csv.summary)
        assertEquals(golden.getValue("portsCsv"), csv.contents)
    }

    @Test
    fun `the decisions the formatter actually makes are exercised`() {
        val csv = ConfigurationExportFormat.portsCSVArtifact(ports, "s").contents
        assertTrue(csv.contains("\"Caddy (HTTPS), Nextcloud\""), csv)
        assertTrue(csv.contains("\"Panel \"\"admin\"\"\""), csv)
        assertEquals("notexample.com", ConfigurationExportFormat.nameField("notexample.com", zone))
        assertEquals("@", ConfigurationExportFormat.nameField(zone, zone))
        assertEquals("mail", ConfigurationExportFormat.nameField("mail.$zone", zone))
    }
}
