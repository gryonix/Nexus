package com.skaymer.gryonixnexus.core

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

class CloudflareDNSProvider(
    token: String,
    http: CloudflareHTTPClient = JdkCloudflareHTTPClient(),
    baseURL: String = CLOUDFLARE_API,
) : DNSPublishingProvider {
    private val transport = CloudflareTransport(token, http, baseURL)

    override val displayName = "Cloudflare"

    // ------------------------------------------------------- Public surface

    /** Confirms the token works before anything is written */
    override suspend fun verifyToken() {
        transport.send(CloudflareTransport.Method.GET, "user/tokens/verify")
    }

    /** The zone id Cloudflare knows this domain by */
    suspend fun zoneID(zone: String): String = transport.zoneID(zone)

    override suspend fun apply(records: List<DNSRecord>, zone: String) {
        applyReportingOutcomes(records, zone)
    }

    override suspend fun publishReportingOutcomes(
        records: List<DNSRecord>,
        zone: String,
    ): List<DNSPublishOutcome> = applyReportingOutcomes(records, zone).map {
        DNSPublishOutcome(it.record, it.result.toShared())
    }

    override suspend fun removeAddressRecords(names: List<String>, address: String, zone: String): List<String> {
        val zoneID = zoneID(zone)
        val wanted = names.map { it.lowercase() }.toSet()
        return existingRecords(zoneID)
            .filter { it.type == "A" && it.content == address && it.name.lowercase() in wanted }
            .map { record ->
                transport.send(CloudflareTransport.Method.DELETE, "zones/$zoneID/dns_records/${record.id}")
                record.name
            }
    }

    suspend fun applyReportingOutcomes(unmerged: List<DNSRecord>, zone: String): List<Outcome> {
        val zoneID = zoneID(zone)
        val existing = existingRecords(zoneID)
        val records = mergingSPF(unmerged) { record ->
            existing.firstOrNull { it.matches(record) }?.let { RemoteRecord.unquoted(it.content) }
        }
        val outcomes = mutableListOf<Outcome>()

        for (record in records) {
            try {
                val match = existing.firstOrNull { it.matches(record) }
                when {
                    match == null -> {
                        transport.send(
                            CloudflareTransport.Method.POST,
                            "zones/$zoneID/dns_records",
                            body = body(record),
                        )
                        outcomes += Outcome(record, Outcome.Result.Created)
                    }

                    match.isUpToDate(record) -> outcomes += Outcome(record, Outcome.Result.Unchanged)

                    else -> {
                        transport.send(
                            CloudflareTransport.Method.PUT,
                            "zones/$zoneID/dns_records/${match.id}",
                            body = body(record),
                        )
                        outcomes += Outcome(record, Outcome.Result.Updated)
                    }
                }
            } catch (error: CloudflareError) {
                outcomes += Outcome(record, Outcome.Result.Failed(error.message))
            }
        }
        return outcomes
    }

    /** What became of one record */
    data class Outcome(val record: DNSRecord, val result: Result) {
        sealed class Result {
            data object Created : Result()
            data object Updated : Result()

            data object Unchanged : Result()
            data class Failed(val message: String) : Result()

            fun toShared(): DNSPublishOutcome.Result = when (this) {
                Created -> DNSPublishOutcome.Result.Created
                Updated -> DNSPublishOutcome.Result.Updated
                Unchanged -> DNSPublishOutcome.Result.Unchanged
                is Failed -> DNSPublishOutcome.Result.Failed(message)
            }
        }
    }

    // ------------------------------------------------------ Existing records

    internal data class RemoteRecord(
        val id: String,
        val type: String,
        val name: String,
        val content: String,
        val priority: Int?,
    ) {
        fun matches(record: DNSRecord): Boolean =
            type == record.type.rawValue && name.lowercase() == record.name.lowercase() &&
                record.replaces(unquoted(content))

        fun isUpToDate(record: DNSRecord): Boolean {
            val srv = record.srv
            if (record.type == DNSRecord.RecordType.SRV && srv != null) {
                return content.endsWith("${srv.weight} ${srv.port} ${srv.target}") &&
                    priority == srv.priority
            }
            if (record.type == DNSRecord.RecordType.TXT) {
                return content.startsWith("\"") && unquoted(content) == record.value
            }
            return content == record.value && priority == record.priority
        }

        companion object {
            /** `"a" "b"` read back as `ab` */
            fun unquoted(content: String): String {
                if (!content.startsWith("\"")) return content
                val text = StringBuilder()
                var inside = false
                var escaped = false
                for (character in content) {
                    when {
                        escaped -> { text.append(character); escaped = false }
                        character == '\\' && inside -> escaped = true
                        character == '"' -> inside = !inside
                        inside -> text.append(character)
                    }
                }
                return text.toString()
            }
        }
    }

    /** Every record in the zone, following Cloudflare's pagination */
    private suspend fun existingRecords(zoneID: String): List<RemoteRecord> {
        var page = 1
        val all = mutableListOf<RemoteRecord>()
        while (true) {
            val payload = transport.send(
                CloudflareTransport.Method.GET,
                "zones/$zoneID/dns_records",
                query = mapOf("per_page" to "100", "page" to page.toString()),
            )
            val batch = payload.resultArray.mapNotNull { item ->
                val id = item["id"]?.stringOrNull() ?: return@mapNotNull null
                val type = item["type"]?.stringOrNull() ?: return@mapNotNull null
                val name = item["name"]?.stringOrNull() ?: return@mapNotNull null
                val content = item["content"]?.stringOrNull() ?: return@mapNotNull null
                RemoteRecord(id, type, name, content, item["priority"]?.intOrNull())
            }
            all += batch
            if (batch.size != 100 || page >= 50) return all
            page += 1
        }
    }

    internal fun body(record: DNSRecord): JsonObject {
        val body = mutableMapOf<String, JsonElement>(
            "type" to JsonPrimitive(record.type.rawValue),
            "name" to JsonPrimitive(record.name),
            "content" to JsonPrimitive(
                if (record.type == DNSRecord.RecordType.TXT) bindTXTRData(record.value, Int.MAX_VALUE) else record.value
            ),
            "ttl" to JsonPrimitive(1),
            "proxied" to JsonPrimitive(false),
        )
        record.priority?.let { body["priority"] = JsonPrimitive(it) }
        val srv = record.srv
        if (record.type == DNSRecord.RecordType.SRV && srv != null) {
            body["data"] = JsonObject(
                mapOf(
                    "priority" to JsonPrimitive(srv.priority),
                    "weight" to JsonPrimitive(srv.weight),
                    "port" to JsonPrimitive(srv.port),
                    "target" to JsonPrimitive(srv.target),
                ),
            )
        }
        record.comment?.let { body["comment"] = JsonPrimitive(it) }
        return JsonObject(body)
    }
}

/** Cloudflare's own API root — the default both providers point at */
const val CLOUDFLARE_API = "https://api.cloudflare.com/client/v4"

/** The zone id for a domain name */
internal suspend fun CloudflareTransport.zoneID(zone: String): String {
    val payload = send(CloudflareTransport.Method.GET, "zones", query = mapOf("name" to zone))
    val id = payload.resultArray.firstOrNull()?.get("id")?.stringOrNull()
    if (id.isNullOrEmpty()) throw CloudflareError.ZoneNotFound(zone)
    return id
}
