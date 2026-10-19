package com.skaymer.gryonixnexus.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

class HetznerDNSProvider(
    private val token: String,
    private val http: CloudflareHTTPClient = JdkCloudflareHTTPClient(),
    private val baseURL: String = HETZNER_API,
) : DNSPublishingProvider {
    override val displayName = "Hetzner"

    override suspend fun verifyToken() {
        send(Method.GET, "zones", query = mapOf("per_page" to "1"))
    }

    suspend fun zoneID(zone: String): String {
        val payload = send(Method.GET, "zones", query = mapOf("name" to zone))
        val id = payload.array("zones").firstOrNull()?.jsonObject?.get("id")?.stringOrNull()
        if (id.isNullOrEmpty()) throw HetznerError.ZoneNotFound(zone)
        return id
    }

    override suspend fun apply(records: List<DNSRecord>, zone: String) {
        publishReportingOutcomes(records, zone)
    }

    override suspend fun publishReportingOutcomes(
        records: List<DNSRecord>,
        zone: String,
    ): List<DNSPublishOutcome> {
        val zoneID = zoneID(zone)
        val existing = existingRecords(zoneID)
        val records = mergingSPF(records) { record ->
            val relative = relativeName(record.name, zone)
            existing.firstOrNull { it.matches(record.type.rawValue, relative) && record.replaces(it.value) }?.value
        }
        val outcomes = mutableListOf<DNSPublishOutcome>()

        for (record in records) {
            try {
                val relative = relativeName(record.name, zone)
                val value = value(record)
                val match = existing.firstOrNull { it.matches(record.type.rawValue, relative) && record.replaces(it.value) }
                when {
                    match == null -> {
                        send(Method.POST, "records", body = body(zoneID, relative, record, value))
                        outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Created)
                    }

                    match.isUpToDate(value) ->
                        outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Unchanged)

                    else -> {
                        send(
                            Method.PUT,
                            "records/${match.id}",
                            body = body(zoneID, relative, record, value),
                        )
                        outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Updated)
                    }
                }
            } catch (error: HetznerError) {
                outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Failed(error.message))
            }
        }
        return outcomes
    }

    // ------------------------------------------------------ Naming and values

    private fun relativeName(fullName: String, zone: String): String {
        val full = fullName.lowercase()
        val z = zone.lowercase()
        val suffix = ".$z"
        return when {
            full == z -> "@"
            full.endsWith(suffix) -> full.dropLast(suffix.length)
            else -> full
        }
    }

    private fun value(record: DNSRecord): String = when (record.type) {
        DNSRecord.RecordType.MX -> "${record.priority ?: 0} ${withTrailingDot(record.value)}"
        DNSRecord.RecordType.SRV -> record.srv?.let { srv ->
            "${srv.priority} ${srv.weight} ${srv.port} ${withTrailingDot(srv.target)}"
        } ?: record.value

        DNSRecord.RecordType.A, DNSRecord.RecordType.AAAA, DNSRecord.RecordType.TXT -> record.value
    }

    private fun withTrailingDot(value: String) = if (value.endsWith(".")) value else "$value."

    // ------------------------------------------------------ Existing records

    internal data class RemoteRecord(val id: String, val type: String, val name: String, val value: String) {
        fun matches(matchType: String, matchName: String): Boolean =
            type == matchType && name.lowercase() == matchName.lowercase()

        fun isUpToDate(target: String): Boolean = normalized(value) == normalized(target)

        private fun normalized(text: String): String = text.removeSuffix(".")
    }

    private suspend fun existingRecords(zoneID: String): List<RemoteRecord> {
        var page = 1
        val all = mutableListOf<RemoteRecord>()
        while (true) {
            val payload = send(
                Method.GET,
                "records",
                query = mapOf("zone_id" to zoneID, "per_page" to "100", "page" to page.toString()),
            )
            val batch = payload.array("records").mapNotNull { element ->
                val item = element.jsonObject
                val id = item["id"]?.stringOrNull() ?: return@mapNotNull null
                val type = item["type"]?.stringOrNull() ?: return@mapNotNull null
                val name = item["name"]?.stringOrNull() ?: return@mapNotNull null
                val value = item["value"]?.stringOrNull() ?: return@mapNotNull null
                RemoteRecord(id, type, name, value)
            }
            all += batch
            val lastPage = payload.meta()?.get("pagination")?.jsonObject?.get("last_page")?.intOrNull()
            if (lastPage == null || page >= lastPage || page >= 50) return all
            page += 1
        }
    }

    private fun body(zoneID: String, name: String, record: DNSRecord, value: String): JsonObject = JsonObject(
        mapOf(
            "zone_id" to JsonPrimitive(zoneID),
            "type" to JsonPrimitive(record.type.rawValue),
            "name" to JsonPrimitive(name),
            "value" to JsonPrimitive(value),
            "ttl" to JsonPrimitive(300),
        ),
    )

    // ------------------------------------------------------------ Transport

    private enum class Method { GET, POST, PUT }

    private suspend fun send(
        method: Method,
        path: String,
        query: Map<String, String> = emptyMap(),
        body: JsonObject? = null,
    ): HetznerPayload {
        val url = buildString {
            append(baseURL.trimEnd('/'))
            append('/')
            append(path)
            if (query.isNotEmpty()) {
                append('?')
                append(
                    query.toSortedMap().entries.joinToString("&") { (key, value) ->
                        "${java.net.URLEncoder.encode(key, "UTF-8")}=${java.net.URLEncoder.encode(value, "UTF-8")}"
                    },
                )
            }
        }
        val request = CloudflareRequest(
            method = method.name,
            url = url,
            headers = mapOf(
                "Auth-API-Token" to token,
                "Content-Type" to "application/json",
            ),
            body = body?.let { Json.encodeToString(JsonObject.serializer(), it) },
        )
        val response = http.send(request)
        return HetznerPayload.of(response)
    }
}

/** Hetzner's own API root */
const val HETZNER_API = "https://dns.hetzner.com/api/v1"

internal class HetznerPayload(private val fields: JsonObject) {
    fun array(key: String): List<kotlinx.serialization.json.JsonElement> =
        (fields[key] as? JsonArray) ?: emptyList()

    fun meta(): JsonObject? = fields["meta"] as? JsonObject

    companion object {
        fun of(response: CloudflareResponse): HetznerPayload {
            val parsed = runCatching { Json.parseToJsonElement(response.body).jsonObject }.getOrNull()
            if (response.status !in 200..299) {
                val message = (parsed?.get("error") as? JsonObject)?.get("message")?.stringOrNull()
                    ?: "HTTP ${response.status}"
                if (response.status == 401 || response.status == 403) throw HetznerError.InvalidToken
                throw HetznerError.Api(response.status, message)
            }
            val body = parsed ?: throw HetznerError.UnreadableResponse(response.status)
            return HetznerPayload(body)
        }
    }
}

/** What went wrong, in Hetzner's own terms */
sealed class HetznerError(override val message: String) : Exception(message) {
    data object InvalidToken : HetznerError("Invalid API token")
    data class ZoneNotFound(val zone: String) : HetznerError("no zone named $zone in this account")
    data class Api(val status: Int, val text: String) : HetznerError("$text (HTTP $status)")
    data class UnreadableResponse(val status: Int) :
        HetznerError("unreadable response from Hetzner (HTTP $status)")
}
