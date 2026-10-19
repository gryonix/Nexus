package com.skaymer.gryonixnexus.core

import java.net.URLEncoder
import java.security.MessageDigest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

class OVHDNSProvider(
    token: String,
    private val http: CloudflareHTTPClient = JdkCloudflareHTTPClient(),
    private val baseURL: String = OVH_API,
    private val nowSeconds: () -> Long = { System.currentTimeMillis() / 1000 },
) : DNSPublishingProvider {
    override val displayName = "OVHcloud"

    private val applicationKey: String
    private val applicationSecret: String
    private val consumerKey: String

    init {
        val parts = token.split(':', limit = 3)
        applicationKey = parts.getOrElse(0) { "" }
        applicationSecret = parts.getOrElse(1) { "" }
        consumerKey = parts.getOrElse(2) { "" }
    }

    private val hasAllKeys: Boolean
        get() = applicationKey.isNotEmpty() && applicationSecret.isNotEmpty() && consumerKey.isNotEmpty()

    override suspend fun verifyToken() {
        if (!hasAllKeys) throw OVHError.MalformedToken
        val delta = serverTimeDelta()
        send(Method.GET, "/domain/zone", delta = delta)
    }

    override suspend fun apply(records: List<DNSRecord>, zone: String) {
        publishReportingOutcomes(records, zone)
    }

    override suspend fun publishReportingOutcomes(
        records: List<DNSRecord>,
        zone: String,
    ): List<DNSPublishOutcome> {
        if (!hasAllKeys) throw OVHError.MalformedToken
        val delta = serverTimeDelta()
        val outcomes = mutableListOf<DNSPublishOutcome>()
        var changed = false

        for (asked in records) {
            try {
                val sub = relativeName(asked.name, zone)
                val existing = matchingRecords(zone, asked.type.rawValue, sub, delta)
                val match = existing.firstOrNull { asked.replaces(it.target) }
                val record = match?.let { asked.merged(it.target) } ?: asked
                val target = target(record)
                when {
                    match == null -> {
                        send(
                            Method.POST,
                            "/domain/zone/$zone/record",
                            body = JsonObject(
                                mapOf(
                                    "fieldType" to JsonPrimitive(record.type.rawValue),
                                    "subDomain" to JsonPrimitive(sub),
                                    "target" to JsonPrimitive(target),
                                    "ttl" to JsonPrimitive(3600),
                                ),
                            ),
                            delta = delta,
                        )
                        changed = true
                        outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Created)
                    }

                    normalized(match.target) == normalized(target) ->
                        outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Unchanged)

                    else -> {
                        send(
                            Method.PUT,
                            "/domain/zone/$zone/record/${match.id}",
                            body = JsonObject(
                                mapOf(
                                    "subDomain" to JsonPrimitive(sub),
                                    "target" to JsonPrimitive(target),
                                    "ttl" to JsonPrimitive(3600),
                                ),
                            ),
                            delta = delta,
                        )
                        changed = true
                        outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Updated)
                    }
                }
            } catch (error: OVHError) {
                outcomes += DNSPublishOutcome(asked, DNSPublishOutcome.Result.Failed(error.message))
            }
        }

        if (changed) send(Method.POST, "/domain/zone/$zone/refresh", delta = delta)
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

    private fun target(record: DNSRecord): String = when (record.type) {
        DNSRecord.RecordType.MX -> "${record.priority ?: 0} ${withTrailingDot(record.value)}"
        DNSRecord.RecordType.SRV -> record.srv?.let { srv ->
            "${srv.priority} ${srv.weight} ${srv.port} ${withTrailingDot(srv.target)}"
        } ?: record.value

        DNSRecord.RecordType.A, DNSRecord.RecordType.AAAA, DNSRecord.RecordType.TXT -> record.value
    }

    private fun withTrailingDot(value: String) = if (value.endsWith(".")) value else "$value."

    private fun normalized(text: String): String = text.removeSuffix(".")

    // ------------------------------------------------------ Existing records

    internal data class RemoteRecord(val id: Int, val target: String)

    private suspend fun matchingRecords(zone: String, type: String, subDomain: String, delta: Long): List<RemoteRecord> {
        val ids = send(
            Method.GET,
            "/domain/zone/$zone/record",
            query = mapOf("fieldType" to type, "subDomain" to subDomain),
            delta = delta,
        ).ints()
        return ids.map { id ->
            val obj = send(Method.GET, "/domain/zone/$zone/record/$id", delta = delta).obj()
            RemoteRecord(id, obj?.get("target")?.stringOrNull() ?: "")
        }
    }

    // ------------------------------------------------------------ Signing

    private suspend fun serverTimeDelta(): Long {
        val request = CloudflareRequest(method = "GET", url = "${baseURL.trimEnd('/')}/auth/time", headers = emptyMap())
        val response = http.send(request)
        if (response.status !in 200..299) throw OVHError.UnreadableResponse(response.status)
        val serverNow = response.body.trim().toLongOrNull() ?: throw OVHError.UnreadableResponse(response.status)
        return serverNow - nowSeconds()
    }

    private fun signature(method: String, url: String, body: String, timestamp: String): String {
        val base = listOf(applicationSecret, consumerKey, method, url, body, timestamp).joinToString("+")
        val digest = MessageDigest.getInstance("SHA-1").digest(base.toByteArray(Charsets.UTF_8))
        return "\$1\$" + digest.joinToString("") { "%02x".format(it) }
    }

    // ------------------------------------------------------------ Transport

    private enum class Method { GET, POST, PUT }

    private suspend fun send(
        method: Method,
        path: String,
        query: Map<String, String> = emptyMap(),
        body: JsonObject? = null,
        delta: Long,
    ): OVHResponse {
        val url = buildString {
            append(baseURL.trimEnd('/'))
            append(path)
            if (query.isNotEmpty()) {
                append('?')
                append(
                    query.toSortedMap().entries.joinToString("&") { (key, value) ->
                        "${URLEncoder.encode(key, "UTF-8")}=${URLEncoder.encode(value, "UTF-8")}"
                    },
                )
            }
        }
        val bodyText = body?.let { Json.encodeToString(JsonObject.serializer(), it) } ?: ""
        val timestamp = (nowSeconds() + delta).toString()
        val headers = mutableMapOf(
            "X-Ovh-Application" to applicationKey,
            "X-Ovh-Consumer" to consumerKey,
            "X-Ovh-Timestamp" to timestamp,
            "X-Ovh-Signature" to signature(method.name, url, bodyText, timestamp),
        )
        if (body != null) headers["Content-Type"] = "application/json"
        val request = CloudflareRequest(method = method.name, url = url, headers = headers, body = body?.let { bodyText })
        val response = http.send(request)
        return OVHResponse.of(response, zoneName(path))
    }

    private fun zoneName(path: String): String {
        val prefix = "/domain/zone/"
        if (!path.startsWith(prefix)) return ""
        return path.removePrefix(prefix).substringBefore('/')
    }
}

const val OVH_API = "https://eu.api.ovh.com/1.0"

internal class OVHResponse(private val element: JsonElement?) {
    fun ints(): List<Int> = (element as? JsonArray)?.mapNotNull { it.intOrNull() } ?: emptyList()
    fun obj(): JsonObject? = element as? JsonObject

    companion object {
        fun of(response: CloudflareResponse, zone: String): OVHResponse {
            val parsed = runCatching { Json.parseToJsonElement(response.body) }.getOrNull()
            if (response.status !in 200..299) {
                val message = (parsed as? JsonObject)?.get("message")?.stringOrNull() ?: "HTTP ${response.status}"
                if (response.status == 401 || response.status == 403) throw OVHError.InvalidToken
                if (response.status == 404 && zone.isNotEmpty()) throw OVHError.ZoneNotFound(zone)
                throw OVHError.Api(response.status, message)
            }
            if (parsed == null) throw OVHError.UnreadableResponse(response.status)
            return OVHResponse(parsed)
        }
    }
}

/** What went wrong, in OVH's own terms */
sealed class OVHError(override val message: String) : Exception(message) {
    /** The token field did not hold three colon-separated keys */
    data object MalformedToken :
        OVHError("Paste all three keys as applicationKey:applicationSecret:consumerKey")
    data object InvalidToken : OVHError("Invalid application key, secret or consumer key")
    data class ZoneNotFound(val zone: String) : OVHError("no DNS zone named $zone in this account")
    data class Api(val status: Int, val text: String) : OVHError("$text (HTTP $status)")
    data class UnreadableResponse(val status: Int) :
        OVHError("unreadable response from OVH (HTTP $status)")
}
