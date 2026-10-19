package com.skaymer.gryonixnexus.core

import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

/** Publishes generated records through GoDaddy's v3 Domains API */
class GoDaddyDNSProvider(
    private val token: String,
    private val http: CloudflareHTTPClient = JdkCloudflareHTTPClient(),
    private val baseURL: String = GODADDY_API,
) : DNSPublishingProvider {
    override val displayName = "GoDaddy"

    override suspend fun verifyToken() {
        send(Method.GET, "domain-names", query = mapOf("limit" to "1"))
    }

    override suspend fun apply(records: List<DNSRecord>, zone: String) {
        publishReportingOutcomes(records, zone)
    }

    override suspend fun publishReportingOutcomes(
        records: List<DNSRecord>,
        zone: String,
    ): List<DNSPublishOutcome> {
        val outcomes = mutableListOf<DNSPublishOutcome>()
        for (asked in records) {
            try {
                val relative = relativeName(asked.name, zone)
                val match = existingRecord(asked, relative, zone)
                val record = match?.let { asked.merged(it.data) } ?: asked
                when {
                    match == null -> {
                        send(Method.POST, "zones/$zone/dns-records", body = body(record, zone, null))
                        outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Created)
                    }

                    match.isUpToDate(record) ->
                        outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Unchanged)

                    else -> {
                        send(
                            Method.PUT,
                            "zones/$zone/dns-records/${match.id}",
                            body = body(record, zone, match.ttl),
                        )
                        outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Updated)
                    }
                }
            } catch (error: GoDaddyError) {
                outcomes += DNSPublishOutcome(asked, DNSPublishOutcome.Result.Failed(error.message))
            }
        }
        return outcomes
    }

    // ------------------------------------------------------------ Naming

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

    // ------------------------------------------------------ Existing records

    internal data class RemoteRecord(
        val id: String,
        val data: String,
        val ttl: Int?,
        val priority: Int?,
    ) {
        fun isUpToDate(record: DNSRecord): Boolean {
            val srv = record.srv
            if (record.type == DNSRecord.RecordType.SRV && srv != null) {
                val folded = "${srv.weight} ${srv.port} ${srv.target}"
                return normalized(data) == normalized(folded) && priority == srv.priority
            }
            if (record.type == DNSRecord.RecordType.MX) {
                return normalized(data) == normalized(record.value) && priority == record.priority
            }
            return data == record.value
        }

        private fun normalized(value: String): String = value.removeSuffix(".")
    }

    private suspend fun existingRecord(record: DNSRecord, name: String, zone: String): RemoteRecord? {
        val type = record.type.rawValue
        val payload = send(
            Method.GET,
            "zones/$zone/dns-records",
            query = mapOf("type" to type, "name" to name),
        )
        val item = payload.array("items").firstNotNullOfOrNull { element ->
            val obj = element.jsonObject
            if (obj["type"]?.stringOrNull() != type ||
                obj["name"]?.stringOrNull()?.lowercase() != name.lowercase() ||
                !record.replaces(obj["data"]?.stringOrNull().orEmpty())
            ) {
                null
            } else {
                obj
            }
        } ?: return null
        val id = item["recordId"]?.stringOrNull() ?: return null
        return RemoteRecord(
            id = id,
            data = item["data"]?.stringOrNull().orEmpty(),
            ttl = item["ttl"]?.intOrNull(),
            priority = item["priority"]?.intOrNull(),
        )
    }

    private fun body(record: DNSRecord, zone: String, existingTTL: Int?): JsonObject {
        val fields = mutableMapOf<String, JsonElement>(
            "type" to JsonPrimitive(record.type.rawValue),
            "name" to JsonPrimitive(relativeName(record.name, zone)),
            "ttl" to JsonPrimitive(existingTTL ?: DEFAULT_TTL),
        )
        when (record.type) {
            DNSRecord.RecordType.MX -> {
                fields["data"] = JsonPrimitive(withTrailingDot(record.value))
                record.priority?.let { fields["priority"] = JsonPrimitive(it) }
            }

            DNSRecord.RecordType.SRV -> record.srv?.let { srv ->
                fields["data"] = JsonPrimitive("${srv.weight} ${srv.port} ${withTrailingDot(srv.target)}")
                fields["priority"] = JsonPrimitive(srv.priority)
            }

            DNSRecord.RecordType.A, DNSRecord.RecordType.AAAA, DNSRecord.RecordType.TXT ->
                fields["data"] = JsonPrimitive(record.value)
        }
        return JsonObject(fields)
    }

    private fun withTrailingDot(value: String) = if (value.endsWith(".")) value else "$value."

    // ------------------------------------------------------------ Transport

    private enum class Method { GET, POST, PUT }

    private suspend fun send(
        method: Method,
        path: String,
        query: Map<String, String> = emptyMap(),
        body: JsonObject? = null,
    ): GoDaddyPayload {
        val url = buildString {
            append(baseURL.trimEnd('/'))
            append('/')
            append(path)
            if (query.isNotEmpty()) {
                append('?')
                append(
                    query.toSortedMap().entries.joinToString("&") { (key, value) ->
                        "${encode(key)}=${encode(value)}"
                    },
                )
            }
        }
        val request = CloudflareRequest(
            method = method.name,
            url = url,
            headers = mapOf(
                "Authorization" to "Bearer $token",
                "Content-Type" to "application/json",
            ),
            body = body?.let { Json.encodeToString(JsonObject.serializer(), it) },
        )
        val response = http.send(request)
        val zone = if (path.startsWith("zones/")) {
            path.removePrefix("zones/").substringBefore('/')
        } else {
            ""
        }
        return GoDaddyPayload.of(response, zone)
    }

    private fun encode(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20")

    private companion object {
        const val DEFAULT_TTL = 3600
    }
}

/** GoDaddy's own v3 API root */
const val GODADDY_API = "https://api.godaddy.com/v3/domains"

internal class GoDaddyPayload(private val fields: JsonObject) {
    fun array(key: String): List<JsonElement> = (fields[key] as? JsonArray) ?: emptyList()

    companion object {
        fun of(response: CloudflareResponse, zone: String): GoDaddyPayload {
            val parsed = runCatching { Json.parseToJsonElement(response.body).jsonObject }.getOrNull()
            if (response.status !in 200..299) {
                val message = parsed?.get("message")?.stringOrNull() ?: "HTTP ${response.status}"
                if (response.status == 401 || response.status == 403) throw GoDaddyError.InvalidToken
                if (response.status == 404) throw GoDaddyError.ZoneNotFound(zone)
                throw GoDaddyError.Api(response.status, message)
            }
            return GoDaddyPayload(parsed ?: JsonObject(emptyMap()))
        }
    }
}

/** What went wrong, in GoDaddy's own terms */
sealed class GoDaddyError(override val message: String) : Exception(message) {
    data object InvalidToken : GoDaddyError("Invalid API token")
    data class ZoneNotFound(val zone: String) : GoDaddyError("no domain named $zone in this account")
    data class Api(val status: Int, val text: String) : GoDaddyError("$text (HTTP $status)")
}
