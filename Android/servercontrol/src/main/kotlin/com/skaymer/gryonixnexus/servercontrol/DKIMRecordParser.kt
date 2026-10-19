package com.skaymer.gryonixnexus.servercontrol

data class DKIMRecord(
    /** Record name, e.g */
    val name: String,
    val value: String,
) {
    val type: String get() = "TXT"
}

/** Extracts DKIM records from an install report */
object DKIMRecordParser {
    const val MARKER = "GRYONIXNEXUS_DKIM"

    fun parse(report: String): List<DKIMRecord> = report.split("\n").mapNotNull { line ->
        val trimmed = line.trim()
        if (!trimmed.startsWith("$MARKER ")) return@mapNotNull null
        val rest = trimmed.drop(MARKER.length + 1)
        val separator = rest.indexOf(' ')
        if (separator < 0) return@mapNotNull null
        val name = rest.substring(0, separator)
        val value = rest.substring(separator + 1).trim()
        if (name.isEmpty() || value.isEmpty()) null else DKIMRecord(name, value)
    }

    fun stripMarkers(report: String): String = report.split("\n")
        .filterNot { it.trim().startsWith("$MARKER ") }
        .joinToString("\n")
}
