package com.skaymer.gryonixnexus.core

data class DNSRecord(
    val name: String,
    val type: RecordType,
    val value: String,
    /** MX preference; null for other types */
    val priority: Int? = null,
    /** The SRV parts, and only for [RecordType.SRV] */
    val srv: SRVData? = null,
    /** Human-readable purpose, rendered as a comment in manual exports */
    val comment: String? = null
) {
    enum class RecordType(val rawValue: String) {
        A("A"),
        AAAA("AAAA"),
        MX("MX"),
        TXT("TXT"),

        SRV("SRV")
    }

    /** The four fields an SRV record actually carries */
    data class SRVData(
        val priority: Int,
        val weight: Int,
        val port: Int,
        val target: String
    ) {
        /** Zone-file rdata: `<priority> <weight> <port> <target>.` */
        val zoneRData: String get() = "$priority $weight $port $target."
    }

    companion object {
        fun service(name: String, srv: SRVData, comment: String? = null): DNSRecord =
            DNSRecord(
                name = name,
                type = RecordType.SRV,
                value = "${srv.priority} ${srv.weight} ${srv.port} ${srv.target}",
                priority = srv.priority,
                srv = srv,
                comment = comment
            )
    }
}

fun bindTXTRData(value: String, chunkSize: Int = 255): String {
    fun quoted(part: String): String {
        // Backslash first: escaping the quotes would otherwise be re-escaped.
        val escaped = part.replace("\\", "\\\\").replace("\"", "\\\"")
        return "\"$escaped\""
    }
    val bytes = value.toByteArray(Charsets.UTF_8)
    if (bytes.size <= chunkSize) return quoted(value)
    return (bytes.indices step chunkSize).joinToString(" ") { start ->
        val end = minOf(start + chunkSize, bytes.size)
        quoted(String(bytes, start, end - start, Charsets.UTF_8))
    }
}

/** Whether this record may overwrite that existing value */
fun DNSRecord.replaces(existingValue: String): Boolean =
    type != DNSRecord.RecordType.TXT || txtKind(existingValue) == txtKind(value)

/** The SPF, DMARC or DKIM tag; other TXT are unique */
internal fun txtKind(raw: String): String {
    val value = raw.filter { it != '"' }.trim()
    val tag = value.takeWhile { it != ' ' && it != ';' }.lowercase()
    return if (tag.startsWith("v=")) tag else "other:$value"
}

fun mergingSPF(records: List<DNSRecord>, existing: (DNSRecord) -> String?): List<DNSRecord> =
    records.map { record -> existing(record)?.let(record::merged) ?: record }

fun DNSRecord.merged(existingValue: String): DNSRecord {
    if (type != DNSRecord.RecordType.TXT || txtKind(value) != "v=spf1" ||
        txtKind(existingValue) != "v=spf1") return this
    return copy(value = mergedSPF(existingValue, value))
}

internal fun mergedSPF(existing: String, ours: String): String {
    fun mechanisms(raw: String) = raw.filter { it != '"' }.split(" ")
        .filter { it.isNotEmpty() && !it.equals("v=spf1", ignoreCase = true) }
    fun isAll(token: String) = token.lowercase().dropWhile { it in "+-~?" } == "all"
    val owners = mechanisms(existing)
    val kept = owners.filterNot(::isAll).toMutableList()
    for (token in mechanisms(ours)) {
        if (!isAll(token) && kept.none { it.equals(token, ignoreCase = true) }) kept += token
    }
    val closing = owners.firstOrNull(::isAll) ?: mechanisms(ours).firstOrNull(::isAll)
    return (listOf("v=spf1") + kept + listOfNotNull(closing)).joinToString(" ")
}

fun DNSRecord.updatedSet(existing: List<String>, target: (DNSRecord) -> String): List<String>? {
    val wanted = target(this)
    if (type != DNSRecord.RecordType.TXT) {
        val present = existing.any { it.trim('.') == wanted.trim('.') }
        return if (present) null else existing + wanted
    }
    fun plain(value: String) = value.filter { it != '"' }
    val kind = txtKind(value)
    val sameKind = existing.filter { txtKind(plain(it)) == kind }
    val others = existing.filter { txtKind(plain(it)) != kind }
    if (kind == "v=dmarc1" && sameKind.isNotEmpty()) return null
    val final = if (kind == "v=spf1" && sameKind.isNotEmpty()) merged(plain(sameKind.first())) else this
    val result = others + target(final)
    return if (result.toSet() == existing.toSet() && result.size == existing.size) null else result
}
