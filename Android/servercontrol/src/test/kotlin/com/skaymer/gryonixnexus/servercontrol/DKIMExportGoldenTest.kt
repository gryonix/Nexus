package com.skaymer.gryonixnexus.servercontrol

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DKIMExportGoldenTest {
    private val golden: JsonArray by lazy {
        val text = checkNotNull(javaClass.getResourceAsStream("/swift-dkim-export.json")) {
            "swift-dkim-export.json missing — run Tools/dump-dkim-export-golden.sh"
        }.bufferedReader().readText()
        Json.parseToJsonElement(text) as JsonArray
    }

    /** The dumper's own inputs, restated here */
    private fun records(case: String): List<DKIMRecord> {
        val longKey = "v=DKIM1;k=rsa;t=s;p=" + "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A".repeat(13)
        return when (case) {
            "empty" -> emptyList()
            "short" -> listOf(DKIMRecord("dkim._domainkey.example.com", "v=DKIM1;k=rsa;p=short"))
            "long-split" -> listOf(DKIMRecord("dkim._domainkey.example.com", longKey))
            "needs-csv-quoting" ->
                listOf(DKIMRecord("dkim._domainkey.example.com", "v=DKIM1,k=rsa;p=abc"))
            "embedded-quote" ->
                listOf(DKIMRecord("dkim._domainkey.example.com", "v=DKIM1;n=say \"hi\";p=abc"))
            "backslash" ->
                listOf(DKIMRecord("dkim._domainkey.example.com", """v=DKIM1;n=a\b;p=abc"""))
            "several-domains" -> listOf(
                DKIMRecord("dkim._domainkey.example.com", longKey),
                DKIMRecord("dkim._domainkey.mail.example.org", "v=DKIM1;k=rsa;p=second"),
            )
            else -> error("the golden holds a case this test does not build: $case")
        }
    }

    @Test
    fun `every case matches the bytes Swift writes`() {
        assertTrue(golden.size >= 7, "the golden holds only ${golden.size} cases")
        for (entry in golden) {
            val obj = entry.jsonObject
            val case = obj.getValue("case").jsonPrimitive.content
            val bundle = DKIMExport.bundle(
                records = records(case),
                zoneSummary = "ZONE-SUMMARY",
                csvSummary = "CSV-SUMMARY",
            )
            if (obj["bundle"]?.jsonPrimitive?.content == "none") {
                assertNull(bundle, "$case: Swift produced no bundle and Kotlin produced one")
                continue
            }
            assertNotNull(bundle, "$case: Swift produced a bundle and Kotlin produced none")
            assertEquals(obj.getValue("copyText").jsonPrimitive.content, bundle.copyText, "$case copy text")
            assertEquals(obj.getValue("zoneFileName").jsonPrimitive.content, bundle.zoneFile.fileName, "$case zone file name")
            assertEquals(obj.getValue("zoneSummary").jsonPrimitive.content, bundle.zoneFile.summary, "$case zone summary")
            assertEquals(obj.getValue("zone").jsonPrimitive.content, bundle.zoneFile.contents, "$case zone file")
            assertEquals(obj.getValue("csvFileName").jsonPrimitive.content, bundle.csvFile.fileName, "$case csv file name")
            assertEquals(obj.getValue("csvSummary").jsonPrimitive.content, bundle.csvFile.summary, "$case csv summary")
            assertEquals(obj.getValue("csv").jsonPrimitive.content, bundle.csvFile.contents, "$case csv file")
        }
    }

    @Test
    fun `a long key is split into several quoted strings`() {
        val bundle = checkNotNull(
            DKIMExport.bundle(records("long-split"), zoneSummary = "z", csvSummary = "c")
        )
        assertTrue(
            bundle.zoneFile.contents.contains("\" \""),
            "a 2048-bit key must be written as several character-strings",
        )
        assertTrue(
            bundle.csvFile.contents.contains("MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A".repeat(13)),
            "the CSV value must not be chunked",
        )
    }
}
