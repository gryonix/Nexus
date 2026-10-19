package com.skaymer.gryonixnexus.core

import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.security.KeyFactory
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Base64
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put

class GoogleCloudDNSProvider(
    token: String,
    private val http: CloudflareHTTPClient = JdkCloudflareHTTPClient(),
    private val baseURL: String = GOOGLE_CLOUD_DNS_API,
    private val nowMillis: () -> Long = { System.currentTimeMillis() },
) : DNSPublishingProvider {
    override val displayName = "Google Cloud DNS"

    private val projectID: String
    private val clientEmail: String
    private val privateKeyPEM: String
    private val tokenURI: String

    init {
        val parsed = runCatching { Json.parseToJsonElement(token).jsonObject }.getOrNull()
        val email = parsed?.get("client_email")?.stringOrNull()
        val key = parsed?.get("private_key")?.stringOrNull()
        val project = parsed?.get("project_id")?.stringOrNull()
        if (!email.isNullOrEmpty() && !key.isNullOrEmpty() && !project.isNullOrEmpty()) {
            clientEmail = email
            privateKeyPEM = key
            projectID = project
            tokenURI = parsed.get("token_uri")?.stringOrNull() ?: "https://oauth2.googleapis.com/token"
        } else {
            clientEmail = ""
            privateKeyPEM = ""
            projectID = ""
            tokenURI = "https://oauth2.googleapis.com/token"
        }
    }

    private val hasCredentials: Boolean
        get() = clientEmail.isNotEmpty() && privateKeyPEM.isNotEmpty() && projectID.isNotEmpty()

    // ------------------------------------------------------------ Public surface

    override suspend fun verifyToken() {
        if (!hasCredentials) throw GoogleCloudDNSError.MalformedToken
        val token = accessToken()
        send(Method.GET, "projects/$projectID/managedZones", query = mapOf("maxResults" to "1"), token = token)
    }

    override suspend fun apply(records: List<DNSRecord>, zone: String) {
        publishReportingOutcomes(records, zone)
    }

    override suspend fun publishReportingOutcomes(
        records: List<DNSRecord>,
        zone: String,
    ): List<DNSPublishOutcome> {
        if (!hasCredentials) throw GoogleCloudDNSError.MalformedToken
        val token = accessToken()
        val managedZone = managedZoneName(zone, token)
        val outcomes = mutableListOf<DNSPublishOutcome>()

        for (record in records) {
            try {
                val existing = existingSet(managedZone, record.name, record.type.rawValue, token)
                val values = record.updatedSet(existing?.values ?: emptyList()) { target(it) }
                if (values == null) {
                    outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Unchanged)
                    continue
                }
                changeRecordSet(managedZone, record.name, record.type.rawValue, existing?.ttl ?: 300, values, existing, token)
                outcomes += DNSPublishOutcome(
                    record,
                    if (existing == null) DNSPublishOutcome.Result.Created else DNSPublishOutcome.Result.Updated,
                )
            } catch (error: GoogleCloudDNSError) {
                outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Failed(error.message))
            }
        }
        return outcomes
    }

    // ------------------------------------------------------------ Zone lookup

    private suspend fun managedZoneName(zone: String, token: String): String {
        val target = normalizedZoneName(zone)
        var pageToken: String? = null
        while (true) {
            val query = buildMap {
                put("maxResults", "200")
                pageToken?.let { put("pageToken", it) }
            }
            val data = send(Method.GET, "projects/$projectID/managedZones", query = query, token = token)
            val obj = runCatching { Json.parseToJsonElement(data).jsonObject }.getOrNull()
                ?: throw GoogleCloudDNSError.UnreadableResponse(200)
            val zones = (obj["managedZones"] as? JsonArray) ?: JsonArray(emptyList())
            for (entry in zones) {
                val item = entry.jsonObject
                val dnsName = item["dnsName"]?.stringOrNull()
                val name = item["name"]?.stringOrNull()
                if (dnsName != null && name != null && normalizedZoneName(dnsName) == target) return name
            }
            pageToken = obj["nextPageToken"]?.stringOrNull()
            if (pageToken == null) throw GoogleCloudDNSError.ZoneNotFound(zone)
        }
    }

    private fun normalizedZoneName(name: String): String =
        (if (name.endsWith(".")) name.dropLast(1) else name).lowercase()

    // ------------------------------------------------------------ Naming and values

    private fun target(record: DNSRecord): String = when (record.type) {
        DNSRecord.RecordType.MX -> "${record.priority ?: 0} ${withTrailingDot(record.value)}"
        DNSRecord.RecordType.SRV -> record.srv?.let { srv ->
            "${srv.priority} ${srv.weight} ${srv.port} ${withTrailingDot(srv.target)}"
        } ?: record.value

        DNSRecord.RecordType.TXT -> bindTXTRData(record.value)
        DNSRecord.RecordType.A, DNSRecord.RecordType.AAAA -> record.value
    }

    private fun withTrailingDot(value: String) = if (value.endsWith(".")) value else "$value."

    // ------------------------------------------------------------ Existing records

    private data class RemoteSet(val ttl: Int, val values: List<String>)

    private suspend fun existingSet(managedZone: String, name: String, type: String, token: String): RemoteSet? {
        val fqdn = if (name.endsWith(".")) name else "$name."
        val data = send(
            Method.GET, "projects/$projectID/managedZones/$managedZone/rrsets",
            query = mapOf("name" to fqdn, "type" to type), token = token,
        )
        val obj = runCatching { Json.parseToJsonElement(data).jsonObject }.getOrNull() ?: return null
        val sets = (obj["rrsets"] as? JsonArray) ?: return null
        val match = sets.map { it.jsonObject }.firstOrNull { it["type"]?.stringOrNull() == type } ?: return null
        val ttl = match["ttl"]?.intOrNull() ?: 300
        val values = (match["rrdatas"] as? JsonArray)?.mapNotNull { it.stringOrNull() } ?: emptyList()
        return RemoteSet(ttl, values)
    }

    private suspend fun changeRecordSet(
        managedZone: String,
        name: String,
        type: String,
        ttl: Int,
        values: List<String>,
        existing: RemoteSet?,
        token: String,
    ) {
        val fqdn = if (name.endsWith(".")) name else "$name."
        val change = buildJsonObject {
            put(
                "additions",
                JsonArray(
                    listOf(
                        buildJsonObject {
                            put("name", fqdn)
                            put("type", type)
                            put("ttl", ttl)
                            put("rrdatas", JsonArray(values.map { JsonPrimitive(it) }))
                        },
                    ),
                ),
            )
            if (existing != null && existing.values.isNotEmpty()) {
                put(
                    "deletions",
                    JsonArray(
                        listOf(
                            buildJsonObject {
                                put("name", fqdn)
                                put("type", type)
                                put("ttl", existing.ttl)
                                put("rrdatas", JsonArray(existing.values.map { JsonPrimitive(it) }))
                            },
                        ),
                    ),
                )
            }
        }
        send(Method.POST, "projects/$projectID/managedZones/$managedZone/changes", body = change, token = token)
    }

    // ------------------------------------------------------------ OAuth2: service-account JWT → access token

    private suspend fun accessToken(): String {
        val jwt = signedJWT()
        val body = "grant_type=${formEncode("urn:ietf:params:oauth:grant-type:jwt-bearer")}" +
            "&assertion=${formEncode(jwt)}"
        val request = CloudflareRequest(
            method = "POST",
            url = tokenURI,
            headers = mapOf("Content-Type" to "application/x-www-form-urlencoded"),
            body = body,
        )
        val response = http.send(request)
        if (response.status !in 200..299) throw GoogleCloudDNSError.from(response.status, response.body)
        val obj = runCatching { Json.parseToJsonElement(response.body).jsonObject }.getOrNull()
        return obj?.get("access_token")?.stringOrNull()
            ?: throw GoogleCloudDNSError.UnreadableResponse(response.status)
    }

    /** RS256 over `base64url(header).base64url(claims)` — Google's own JWT shape */
    private fun signedJWT(): String {
        val iat = nowMillis() / 1000
        val header = buildJsonObject {
            put("alg", "RS256")
            put("typ", "JWT")
        }
        val claims = buildJsonObject {
            put("iss", clientEmail)
            put("scope", SCOPE)
            put("aud", tokenURI)
            put("iat", iat)
            put("exp", iat + 3600)
        }
        val signingInput = "${base64URL(header)}.${base64URL(claims)}"
        val key = rsaPrivateKey(privateKeyPEM) ?: throw GoogleCloudDNSError.SigningFailed
        val signature = Signature.getInstance("SHA256withRSA")
        signature.initSign(key)
        signature.update(signingInput.toByteArray(Charsets.UTF_8))
        return "$signingInput.${base64URLEncode(signature.sign())}"
    }

    private fun base64URL(json: JsonObject): String =
        base64URLEncode(Json.encodeToString(JsonObject.serializer(), json).toByteArray(Charsets.UTF_8))

    private fun base64URLEncode(data: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(data)

    private fun rsaPrivateKey(pem: String): PrivateKey? {
        val stripped = pem
            .replace("-----BEGIN PRIVATE KEY-----", "")
            .replace("-----END PRIVATE KEY-----", "")
            .replace(Regex("\\s"), "")
        return runCatching {
            val der = Base64.getDecoder().decode(stripped)
            KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(der))
        }.getOrNull()
    }

    private fun formEncode(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8)

    // ------------------------------------------------------------ Transport

    private enum class Method { GET, POST }

    private suspend fun send(
        method: Method,
        path: String,
        query: Map<String, String> = emptyMap(),
        body: JsonObject? = null,
        token: String,
    ): String {
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
            headers = buildMap {
                put("Authorization", "Bearer $token")
                if (body != null) put("Content-Type", "application/json")
            },
            body = body?.let { Json.encodeToString(JsonObject.serializer(), it) },
        )
        val response = http.send(request)
        if (response.status !in 200..299) throw GoogleCloudDNSError.from(response.status, response.body)
        return response.body
    }

    private fun encode(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20")

    private companion object {
        const val SCOPE = "https://www.googleapis.com/auth/ndev.clouddns.readwrite"
    }
}

/** Google Cloud DNS's own API root */
const val GOOGLE_CLOUD_DNS_API = "https://dns.googleapis.com/dns/v1"

sealed class GoogleCloudDNSError(override val message: String) : Exception(message) {
    data object MalformedToken : GoogleCloudDNSError("Paste the full service-account JSON key")
    data object SigningFailed : GoogleCloudDNSError("could not sign the request with this private key")
    data object InvalidToken : GoogleCloudDNSError("invalid or unauthorized service-account credentials")
    data class ZoneNotFound(val zone: String) : GoogleCloudDNSError("no managed zone for $zone in this project")
    data class Api(val status: Int, val text: String) : GoogleCloudDNSError("$text (HTTP $status)")
    data class UnreadableResponse(val status: Int) :
        GoogleCloudDNSError("unreadable response from Google Cloud DNS (HTTP $status)")

    companion object {
        fun from(status: Int, body: String): GoogleCloudDNSError {
            if (status == 401 || status == 403) return InvalidToken
            val parsed = runCatching { Json.parseToJsonElement(body).jsonObject }.getOrNull()
            val message = (parsed?.get("error") as? JsonObject)?.get("message")?.stringOrNull()
                ?: parsed?.get("error_description")?.stringOrNull()
                ?: parsed?.get("error")?.stringOrNull()
                ?: "HTTP $status"
            return Api(status, message)
        }
    }
}
