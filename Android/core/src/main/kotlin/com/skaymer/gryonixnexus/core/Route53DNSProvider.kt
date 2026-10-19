package com.skaymer.gryonixnexus.core

import java.io.ByteArrayInputStream
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element

class Route53DNSProvider(
    token: String,
    private val http: CloudflareHTTPClient = JdkCloudflareHTTPClient(),
    private val baseURL: String = ROUTE53_API,
    private val nowMillis: () -> Long = { System.currentTimeMillis() },
) : DNSPublishingProvider {
    override val displayName = "Amazon Route 53"

    private val accessKeyID: String
    private val secretAccessKey: String

    init {
        val colon = token.indexOf(':')
        if (colon >= 0) {
            accessKeyID = token.substring(0, colon)
            secretAccessKey = token.substring(colon + 1)
        } else {
            accessKeyID = token
            secretAccessKey = ""
        }
    }

    private val hasKeys: Boolean get() = accessKeyID.isNotEmpty() && secretAccessKey.isNotEmpty()

    // ------------------------------------------------------------ Public surface

    override suspend fun verifyToken() {
        if (!hasKeys) throw Route53Error.MalformedToken
        send(Method.GET, "/2013-04-01/hostedzone")
    }

    override suspend fun apply(records: List<DNSRecord>, zone: String) {
        publishReportingOutcomes(records, zone)
    }

    override suspend fun publishReportingOutcomes(
        records: List<DNSRecord>,
        zone: String,
    ): List<DNSPublishOutcome> {
        if (!hasKeys) throw Route53Error.MalformedToken
        val zoneID = zoneID(zone)
        val outcomes = mutableListOf<DNSPublishOutcome>()

        for (record in records) {
            try {
                val existing = existingSet(zoneID, record.name, record.type.rawValue)
                val values = record.updatedSet(existing?.values ?: emptyList()) { target(it) }
                if (values == null) {
                    outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Unchanged)
                    continue
                }
                changeRecordSet(zoneID, record.name, record.type.rawValue, existing?.ttl ?: 300, values)
                outcomes += DNSPublishOutcome(
                    record,
                    if (existing == null) DNSPublishOutcome.Result.Created else DNSPublishOutcome.Result.Updated,
                )
            } catch (error: Route53Error) {
                outcomes += DNSPublishOutcome(record, DNSPublishOutcome.Result.Failed(error.message))
            }
        }
        return outcomes
    }

    // ------------------------------------------------------------ Zone lookup

    private suspend fun zoneID(zone: String): String {
        val data = send(Method.GET, "/2013-04-01/hostedzonesbyname", query = mapOf("dnsname" to zone))
        val zones = parseZoneList(data)
        val first = zones.firstOrNull()
        if (first == null || normalizedZoneName(first.second) != zone.lowercase()) {
            throw Route53Error.ZoneNotFound(zone)
        }
        return first.first.replace("/hostedzone/", "")
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

    private suspend fun existingSet(zoneID: String, name: String, type: String): RemoteSet? {
        val data = send(
            Method.GET, "/2013-04-01/hostedzone/$zoneID/rrset",
            query = mapOf("name" to name, "type" to type, "maxitems" to "1"),
        )
        val set = parseRecordSets(data).firstOrNull() ?: return null
        if (set.type != type || normalizedZoneName(set.name) != normalizedZoneName(name)) return null
        return RemoteSet(set.ttl, set.values)
    }

    private suspend fun changeRecordSet(zoneID: String, name: String, type: String, ttl: Int, values: List<String>) {
        val records = values.joinToString("") { "<ResourceRecord><Value>${xmlEscape(it)}</Value></ResourceRecord>" }
        val resourceRecordSet = "<Name>${xmlEscape(name)}</Name><Type>$type</Type><TTL>$ttl</TTL>" +
            "<ResourceRecords>$records</ResourceRecords>"
        val body = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" +
            "<ChangeResourceRecordSetsRequest xmlns=\"https://route53.amazonaws.com/doc/2013-04-01/\">" +
            "<ChangeBatch><Changes><Change><Action>UPSERT</Action>" +
            "<ResourceRecordSet>$resourceRecordSet</ResourceRecordSet>" +
            "</Change></Changes></ChangeBatch></ChangeResourceRecordSetsRequest>"
        send(Method.POST, "/2013-04-01/hostedzone/$zoneID/rrset", body = body)
    }

    private fun xmlEscape(text: String): String =
        text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

    // ------------------------------------------------------------ XML parsing

    private fun parseDocument(xml: String) = DocumentBuilderFactory.newInstance()
        .newDocumentBuilder()
        .parse(ByteArrayInputStream(xml.toByteArray(Charsets.UTF_8)))

    /** `HostedZones/HostedZone/Id`+`Name` pairs, in document order */
    private fun parseZoneList(xml: String): List<Pair<String, String>> {
        val nodes = parseDocument(xml).getElementsByTagName("HostedZone")
        return (0 until nodes.length).map { i ->
            val element = nodes.item(i) as Element
            val id = element.getElementsByTagName("Id").item(0)?.textContent ?: ""
            val name = element.getElementsByTagName("Name").item(0)?.textContent ?: ""
            id to name
        }
    }

    private data class ParsedSet(val name: String, val type: String, val ttl: Int, val values: List<String>)

    /** `ResourceRecordSets/ResourceRecordSet` — `Name`, `Type`, `TTL`, every `Value` */
    private fun parseRecordSets(xml: String): List<ParsedSet> {
        val nodes = parseDocument(xml).getElementsByTagName("ResourceRecordSet")
        return (0 until nodes.length).map { i ->
            val element = nodes.item(i) as Element
            val name = element.getElementsByTagName("Name").item(0)?.textContent ?: ""
            val type = element.getElementsByTagName("Type").item(0)?.textContent ?: ""
            val ttl = element.getElementsByTagName("TTL").item(0)?.textContent?.toIntOrNull() ?: 300
            val valueNodes = element.getElementsByTagName("Value")
            val values = (0 until valueNodes.length).map { valueNodes.item(it).textContent }
            ParsedSet(name, type, ttl, values)
        }
    }

    // ------------------------------------------------------------ Transport + SigV4

    private enum class Method { GET, POST }

    private suspend fun send(method: Method, path: String, query: Map<String, String> = emptyMap(), body: String? = null): String {
        val sortedQuery = query.toSortedMap()
        val canonicalQuery = sortedQuery.entries.joinToString("&") { (key, value) ->
            "${awsURIEncode(key)}=${awsURIEncode(value)}"
        }
        val url = buildString {
            append(baseURL.trimEnd('/'))
            append(path)
            if (canonicalQuery.isNotEmpty()) { append('?'); append(canonicalQuery) }
        }
        val host = baseURL.removePrefix("https://").removePrefix("http://").trimEnd('/')

        val payloadHash = sha256Hex(body ?: "")
        val amzDate = dateFormatter().format(Date(nowMillis()))
        val dateStamp = amzDate.substring(0, 8)

        val headers = sortedMapOf("host" to host, "x-amz-date" to amzDate)
        if (body != null) headers["content-type"] = "application/xml"
        val signedHeaders = headers.keys.joinToString(";")
        val canonicalHeaders = headers.entries.joinToString("") { "${it.key}:${it.value}\n" }

        val canonicalRequest = listOf(
            method.name, awsURIEncodePath(path), canonicalQuery, canonicalHeaders, signedHeaders, payloadHash,
        ).joinToString("\n")

        val scope = "$dateStamp/$REGION/$SERVICE/aws4_request"
        val stringToSign = listOf(
            "AWS4-HMAC-SHA256", amzDate, scope, sha256Hex(canonicalRequest),
        ).joinToString("\n")

        val signingKey = signingKey(secretAccessKey, dateStamp)
        val signature = hmacHex(signingKey, stringToSign)

        val authorization = "AWS4-HMAC-SHA256 Credential=$accessKeyID/$scope, " +
            "SignedHeaders=$signedHeaders, Signature=$signature"

        val request = CloudflareRequest(
            method = method.name,
            url = url,
            headers = buildMap {
                put("X-Amz-Date", amzDate)
                put("Authorization", authorization)
                if (body != null) put("Content-Type", "application/xml")
            },
            body = body,
        )
        val response = http.send(request)
        if (response.status !in 200..299) throw Route53Error.from(response.status, response.body)
        return response.body
    }

    private fun signingKey(secret: String, dateStamp: String): ByteArray {
        val kSecret = "AWS4$secret".toByteArray(Charsets.UTF_8)
        val kDate = hmacBytes(kSecret, dateStamp)
        val kRegion = hmacBytes(kDate, REGION)
        val kService = hmacBytes(kRegion, SERVICE)
        return hmacBytes(kService, "aws4_request")
    }

    private fun hmacBytes(key: ByteArray, data: String): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(data.toByteArray(Charsets.UTF_8))
    }

    private fun hmacHex(key: ByteArray, data: String): String =
        hmacBytes(key, data).joinToString("") { "%02x".format(it) }

    private fun sha256Hex(text: String): String =
        MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    private fun dateFormatter(): SimpleDateFormat {
        val formatter = SimpleDateFormat("yyyyMMdd'T'HHmmss'Z'", Locale.US)
        formatter.timeZone = TimeZone.getTimeZone("UTC")
        return formatter
    }

    private fun awsURIEncode(value: String): String {
        val sb = StringBuilder()
        for (b in value.toByteArray(Charsets.UTF_8)) {
            val c = (b.toInt() and 0xFF).toChar()
            val unreserved = c in 'A'..'Z' || c in 'a'..'z' || c in '0'..'9' || c == '-' || c == '.' || c == '_' || c == '~'
            if (unreserved) sb.append(c) else sb.append("%%%02X".format(b.toInt() and 0xFF))
        }
        return sb.toString()
    }

    private fun awsURIEncodePath(path: String): String =
        path.split("/").joinToString("/") { awsURIEncode(it) }

    private companion object {
        const val REGION = "us-east-1"
        const val SERVICE = "route53"
    }
}

const val ROUTE53_API = "https://route53.amazonaws.com"

/** Route 53 answers a failure with `<ErrorResponse><Error><Code> */
sealed class Route53Error(override val message: String) : Exception(message) {
    /** The token field did not hold `accessKeyID:secretAccessKey` */
    data object MalformedToken : Route53Error("Paste both keys as accessKeyID:secretAccessKey")
    data object InvalidToken : Route53Error("Invalid access key or secret key")
    data class ZoneNotFound(val zone: String) : Route53Error("no hosted zone named $zone in this account")
    data class Api(val status: Int, val text: String) : Route53Error("$text (HTTP $status)")

    companion object {
        fun from(status: Int, body: String): Route53Error {
            if (status == 403) return InvalidToken
            val message = body.substringAfter("<Message>", "").substringBefore("</Message>", "")
                .ifEmpty { "HTTP $status" }
            return Api(status, message)
        }
    }
}
