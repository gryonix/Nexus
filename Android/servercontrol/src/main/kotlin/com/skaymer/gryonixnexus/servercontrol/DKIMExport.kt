package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.core.ArtifactKind
import com.skaymer.gryonixnexus.core.bindTXTRData

object DKIMExport {
    private const val TTL = 3600

    data class Bundle(
        val copyText: String,
        val zoneFile: Artifact,
        val csvFile: Artifact,
    )

    fun bundle(
        records: List<DKIMRecord>,
        zoneSummary: String,
        csvSummary: String,
    ): Bundle? {
        if (records.isEmpty()) return null
        return Bundle(
            copyText = recordsText(records),
            zoneFile = zoneArtifact(records, zoneSummary),
            csvFile = csvArtifact(records, csvSummary),
        )
    }

    fun recordsText(records: List<DKIMRecord>): String =
        records.joinToString("\n") { "TXT\t${it.name}\t${it.value}" }

    private fun zoneArtifact(records: List<DKIMRecord>, summary: String): Artifact {
        val lines = mutableListOf(
            "; BIND zone file (DKIM) - import this at your DNS provider.",
            "\$TTL $TTL",
        )
        records.mapTo(lines) { "${it.name}.    $TTL    IN TXT    ${bindTXTRData(it.value)}" }
        return Artifact(
            fileName = "dkim-dns-zone.txt",
            kind = ArtifactKind.DNS_RECORD,
            contents = lines.joinToString("\n") + "\n",
            summary = summary,
        )
    }

    private fun csvArtifact(records: List<DKIMRecord>, summary: String): Artifact {
        val lines = mutableListOf("type,name,value,ttl,priority")
        records.mapTo(lines) { "TXT,${csvField(it.name)},${csvField(it.value)},$TTL," }
        return Artifact(
            fileName = "dkim-dns-records.csv",
            kind = ArtifactKind.DNS_RECORD,
            contents = lines.joinToString("\n") + "\n",
            summary = summary,
        )
    }

    /** RFC 4180 quoting, matching the DNS CSV export */
    private fun csvField(value: String): String {
        if (!value.contains(",") && !value.contains("\"") && !value.contains("\n")) return value
        return "\"" + value.replace("\"", "\"\"") + "\""
    }
}
