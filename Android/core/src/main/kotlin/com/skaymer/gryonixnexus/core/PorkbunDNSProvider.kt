package com.skaymer.gryonixnexus.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

class PorkbunDNSProvider(
    token: String,
    private val http: CloudflareHTTPClient = JdkCloudflareHTTPClient(),
    private val baseURL: String = PORKBUN_API,
) : DNSPublishingProvider {
    override val displayName = "Porkbun"

    private val apiKey: String
    private val secretApiKey: String

    init {
        val colon = token.indexOf(':')
        if (colon >= 0) {
            apiKey = token.substring(0, colon)
            secretApiKey = token.substring(colon + 1)
        } else {
            apiKey = token
            secretApiKey = ""
        }
    }

    override suspend fun verifyToken() {
        if (secretApiKey.isEmpty()) throw PorkbunError.MalformedToken
        send(Method.POST, "ping", body = credentials(), isPing = true)
    }

    override suspend fun apply(records: List<DNSRecord>, zone: String) {
        publishReportingOutcomes(records, zone)
    }

    override suspend fun publishReportingOutcomes(
        records: List<DNSRecord>,
        zone: String,
    ): List<DNSPublishOutcome> {
        if (secretApiKey.isEmpty()) throw PorkbunError.MalformedToken
        val existing = existingRecords(zone)
        val records = mergingSPF(records) { record ->
            existing.firstOrNull { it.matches(record.type.rawValue, record.name) && record.replaces(it.content) }?.content
        }
        val outcomes = mutableListOf<DNSPublishOutcome>()

        for (record in records) {
            try {
                val relative = relativeName(record.name, zone)
                val content = content(record)
                val priority = record.priority ?: record.srv?.priority
                val match = existing.firstOrNull { it.matches(record.type.rawValue, record.name) && record.replaces(it.content) }
                when {
                    match == null -> {
                        send(Method.POST, "dns/create/$zone", body = createBody(record, relative, content, priority))
                        outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Created)
                    }

                    match.isUpToDate(content, priority) ->
                        outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Unchanged)

                    else -> {
                        send(Method.POST, "dns/edit/$zone/${match.id}", body = editBody(record, relative, content, priority))
                        outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Updated)
                    }
                }
            } catch (error: PorkbunError) {
                outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Failed(error.message ?: error.toString()))
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
            full == z -> ""
            full.endsWith(suffix) -> full.dropLast(suffix.length)
            else -> full
        }
    }

    private fun content(record: DNSRecord): String = when (record.type) {
        DNSRecord.RecordType.MX -> withTrailingDot(record.value)
        DNSRecord.RecordType.SRV -> record.srv?.let { withTrailingDot(it.target) } ?: record.value
        DNSRecord.RecordType.A, DNSRecord.RecordType.AAAA, DNSRecord.RecordType.TXT -> record.value
    }

    private fun withTrailingDot(value: String) = if (value.endsWith(".")) value else "$value."

    private fun credentials(): JsonObject = JsonObject(
        mapOf("apikey" to JsonPrimitive(apiKey), "secretapikey" to JsonPrimitive(secretApiKey)),
    )

    private fun createBody(record: DNSRecord, relative: String, content: String, priority: Int?): JsonObject {
        val fields = mutableMapOf(
            "apikey" to JsonPrimitive(apiKey),
            "secretapikey" to JsonPrimitive(secretApiKey),
            "name" to JsonPrimitive(relative),
            "type" to JsonPrimitive(record.type.rawValue),
            "content" to JsonPrimitive(content),
        )
        if (priority != null) fields["prio"] = JsonPrimitive(priority)
        return JsonObject(fields)
    }

    private fun editBody(record: DNSRecord, relative: String, content: String, priority: Int?): JsonObject {
        val fields = mutableMapOf(
            "apikey" to JsonPrimitive(apiKey),
            "secretapikey" to JsonPrimitive(secretApiKey),
            "name" to JsonPrimitive(relative),
            "type" to JsonPrimitive(record.type.rawValue),
            "content" to JsonPrimitive(content),
        )
        if (priority != null) fields["prio"] = JsonPrimitive(priority)
        return JsonObject(fields)
    }

    // ------------------------------------------------------ Existing records

    internal data class RemoteRecord(val id: String, val type: String, val name: String, val content: String, val priority: Int?) {
        fun matches(matchType: String, matchName: String): Boolean =
            type == matchType && name.lowercase() == matchName.lowercase()

        fun isUpToDate(targetContent: String, targetPriority: Int?): Boolean =
            normalized(content) == normalized(targetContent) && priority == targetPriority

        private fun normalized(text: String): String = text.removeSuffix(".")
    }

    /** No pagination in Porkbun's own docs for this call */
    private suspend fun existingRecords(zone: String): List<RemoteRecord> {
        val payload = send(Method.POST, "dns/retrieve/$zone", body = credentials())
        return payload.array("records").mapNotNull { element ->
            val item = element.jsonObject
            val id = item["id"]?.stringOrNull() ?: return@mapNotNull null
            val type = item["type"]?.stringOrNull() ?: return@mapNotNull null
            val name = item["name"]?.stringOrNull() ?: return@mapNotNull null
            val content = item["content"]?.stringOrNull() ?: return@mapNotNull null
            RemoteRecord(id, type, name, content, item["prio"]?.let(::flexibleIntOrNull))
        }
    }

    private fun flexibleIntOrNull(element: kotlinx.serialization.json.JsonElement): Int? =
        element.intOrNull() ?: element.stringOrNull()?.toIntOrNull()

    // ------------------------------------------------------------ Transport

    private enum class Method { POST }

    private suspend fun send(
        method: Method,
        path: String,
        body: JsonObject? = null,
        isPing: Boolean = false,
    ): PorkbunPayload {
        val url = "${baseURL.trimEnd('/')}/$path"
        val request = CloudflareRequest(
            method = method.name,
            url = url,
            headers = mapOf("Content-Type" to "application/json"),
            body = body?.let { Json.encodeToString(JsonObject.serializer(), it) },
        )
        val response = http.send(request)
        if (isPing && response.status !in 200..299) throw PorkbunError.InvalidToken
        return PorkbunPayload.of(response, zoneName(path))
    }

    private fun zoneName(path: String): String {
        for (prefix in listOf("dns/retrieve/", "dns/create/", "dns/edit/")) {
            if (path.startsWith(prefix)) return path.removePrefix(prefix).substringBefore('/')
        }
        return ""
    }
}

/** Porkbun's own API root */
const val PORKBUN_API = "https://api.porkbun.com/api/json/v3"

internal class PorkbunPayload(private val fields: JsonObject) {
    fun array(key: String): List<kotlinx.serialization.json.JsonElement> =
        (fields[key] as? JsonArray) ?: emptyList()

    companion object {
        fun of(response: CloudflareResponse, zone: String): PorkbunPayload {
            val parsed = runCatching { Json.parseToJsonElement(response.body).jsonObject }.getOrNull()
            if (response.status !in 200..299) {
                val message = parsed?.get("message")?.stringOrNull() ?: "HTTP ${response.status}"
                if (response.status == 404) throw PorkbunError.ZoneNotFound(zone)
                throw PorkbunError.Api(response.status, message)
            }
            val body = parsed ?: throw PorkbunError.UnreadableResponse(response.status)
            if (body["status"]?.stringOrNull() == "ERROR") {
                throw PorkbunError.Api(response.status, body["message"]?.stringOrNull() ?: "unknown error")
            }
            return PorkbunPayload(body)
        }
    }
}

/** What went wrong, in Porkbun's own terms */
sealed class PorkbunError(override val message: String) : Exception(message) {
    /** The token field did not contain `apikey:secretapikey` */
    data object MalformedToken : PorkbunError("Paste both keys as apikey:secretapikey")
    data object InvalidToken : PorkbunError("Invalid API key or secret key")
    data class ZoneNotFound(val zone: String) : PorkbunError("no domain named $zone in this account")
    data class Api(val status: Int, val text: String) : PorkbunError("$text (HTTP $status)")
    data class UnreadableResponse(val status: Int) :
        PorkbunError("unreadable response from Porkbun (HTTP $status)")
}
