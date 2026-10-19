package com.skaymer.gryonixnexus.core

import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

class DigitalOceanDNSProvider(
    private val token: String,
    private val http: CloudflareHTTPClient = JdkCloudflareHTTPClient(),
    private val baseURL: String = DIGITALOCEAN_API,
) : DNSPublishingProvider {
    override val displayName = "DigitalOcean"

    override suspend fun verifyToken() {
        send(Method.GET, "account")
    }

    override suspend fun apply(records: List<DNSRecord>, zone: String) {
        publishReportingOutcomes(records, zone)
    }

    override suspend fun publishReportingOutcomes(
        records: List<DNSRecord>,
        zone: String,
    ): List<DNSPublishOutcome> {
        val existing = existingRecords(zone)
        val records = mergingSPF(records) { record ->
            val relative = relativeName(record.name, zone)
            existing.firstOrNull { it.matches(record.type.rawValue, relative) && record.replaces(it.data) }?.data
        }
        val outcomes = mutableListOf<DNSPublishOutcome>()

        for (record in records) {
            try {
                val relative = relativeName(record.name, zone)
                val match = existing.firstOrNull { it.matches(record.type.rawValue, relative) && record.replaces(it.data) }
                when {
                    match == null -> {
                        send(Method.POST, "domains/$zone/records", body = body(record, zone))
                        outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Created)
                    }

                    match.isUpToDate(record) ->
                        outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Unchanged)

                    else -> {
                        send(
                            Method.PUT,
                            "domains/$zone/records/${match.id}",
                            body = body(record, zone),
                        )
                        outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Updated)
                    }
                }
            } catch (error: DigitalOceanError) {
                outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Failed(error.message))
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
        val id: Int,
        val type: String,
        val name: String,
        val data: String,
        val priority: Int?,
    ) {
        fun matches(matchType: String, matchName: String): Boolean =
            type == matchType && name.lowercase() == matchName.lowercase()

        fun isUpToDate(record: DNSRecord): Boolean {
            val srv = record.srv
            if (record.type == DNSRecord.RecordType.SRV && srv != null) {
                return normalized(data) == normalized(srv.target) && priority == srv.priority
            }
            if (record.type == DNSRecord.RecordType.MX) {
                return normalized(data) == normalized(record.value) && priority == record.priority
            }
            return data == record.value
        }

        private fun normalized(value: String): String = value.removeSuffix(".")
    }

    private suspend fun existingRecords(zone: String): List<RemoteRecord> {
        var page = 1
        val all = mutableListOf<RemoteRecord>()
        while (true) {
            val payload = send(
                Method.GET,
                "domains/$zone/records",
                query = mapOf("per_page" to "200", "page" to page.toString()),
            )
            val batch = payload.array("domain_records").mapNotNull { element ->
                val item = element.jsonObject
                val id = item["id"]?.intOrNull() ?: return@mapNotNull null
                val type = item["type"]?.stringOrNull() ?: return@mapNotNull null
                val name = item["name"]?.stringOrNull() ?: return@mapNotNull null
                val data = item["data"]?.stringOrNull().orEmpty()
                RemoteRecord(id, type, name, data, item["priority"]?.intOrNull())
            }
            all += batch
            if (batch.size != 200 || page >= 50) return all
            page += 1
        }
    }

    private fun body(record: DNSRecord, zone: String): JsonObject {
        val fields = mutableMapOf<String, JsonElement>(
            "type" to JsonPrimitive(record.type.rawValue),
            "name" to JsonPrimitive(relativeName(record.name, zone)),
        )
        when (record.type) {
            DNSRecord.RecordType.MX -> {
                fields["data"] = JsonPrimitive(withTrailingDot(record.value))
                record.priority?.let { fields["priority"] = JsonPrimitive(it) }
            }

            DNSRecord.RecordType.SRV -> record.srv?.let { srv ->
                fields["data"] = JsonPrimitive(withTrailingDot(srv.target))
                fields["priority"] = JsonPrimitive(srv.priority)
                fields["weight"] = JsonPrimitive(srv.weight)
                fields["port"] = JsonPrimitive(srv.port)
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
    ): DigitalOceanPayload {
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
        val zone = path.removePrefix("domains/").substringBefore('/')
        return DigitalOceanPayload.of(response, zone)
    }

    private fun encode(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20")
}

/** DigitalOcean's own API root */
const val DIGITALOCEAN_API = "https://api.digitalocean.com/v2"

internal class DigitalOceanPayload(private val fields: JsonObject) {
    fun array(key: String): List<JsonElement> = (fields[key] as? JsonArray) ?: emptyList()

    companion object {
        fun of(response: CloudflareResponse, zone: String): DigitalOceanPayload {
            val parsed = runCatching { Json.parseToJsonElement(response.body).jsonObject }.getOrNull()
            if (response.status !in 200..299) {
                val message = parsed?.get("message")?.stringOrNull() ?: "HTTP ${response.status}"
                if (response.status == 401 || response.status == 403) throw DigitalOceanError.InvalidToken
                if (response.status == 404) throw DigitalOceanError.ZoneNotFound(zone)
                throw DigitalOceanError.Api(response.status, message)
            }
            val body = parsed ?: throw DigitalOceanError.UnreadableResponse(response.status)
            val single = (body["domain_record"] as? JsonObject)
            return DigitalOceanPayload(
                if (single != null) JsonObject(mapOf("domain_records" to JsonArray(listOf(single)))) else body,
            )
        }
    }
}

/** What went wrong, in DigitalOcean's own terms */
sealed class DigitalOceanError(override val message: String) : Exception(message) {
    data object InvalidToken : DigitalOceanError("Invalid API token")
    data class ZoneNotFound(val zone: String) : DigitalOceanError("no domain named $zone in this account")
    data class Api(val status: Int, val text: String) : DigitalOceanError("$text (HTTP $status)")
    data class UnreadableResponse(val status: Int) :
        DigitalOceanError("unreadable response from DigitalOcean (HTTP $status)")
}
