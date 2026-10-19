package com.skaymer.gryonixnexus.core

import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Builds and sends one Cloudflare API call */
internal class CloudflareTransport(
    private val token: String,
    private val http: CloudflareHTTPClient,
    private val baseURL: String,
) {
    enum class Method { GET, POST, PUT, DELETE }

    suspend fun send(
        method: Method,
        path: String,
        query: Map<String, String> = emptyMap(),
        body: JsonObject? = null,
    ): CloudflarePayload {
        val response = http.send(request(method, path, query, body))
        return CloudflarePayload.of(response)
    }

    fun request(
        method: Method,
        path: String,
        query: Map<String, String> = emptyMap(),
        body: JsonObject? = null,
    ) = CloudflareRequest(
        method = method.name,
        url = url(path, query),
        headers = mapOf(
            "Authorization" to "Bearer $token",
            "Content-Type" to "application/json",
        ),
        body = body?.let { JSON.encodeToString(JsonObject.serializer(), sorted(it)) },
    )

    private fun url(path: String, query: Map<String, String>) = buildString {
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

    private fun encode(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20")

    private companion object {
        val JSON = Json

        /** Sorts object keys at every depth — `.sortedKeys` is not shallow */
        fun sorted(element: JsonElement): JsonElement = when (element) {
            is JsonObject -> JsonObject(
                element.entries
                    .sortedBy { it.key }
                    .associateTo(LinkedHashMap()) { it.key to sorted(it.value) },
            )

            is JsonArray -> JsonArray(element.map(::sorted))
            else -> element
        }

        fun sorted(object_: JsonObject): JsonObject = sorted(object_ as JsonElement) as JsonObject
    }
}

internal class CloudflarePayload(val result: JsonElement?) {
    val resultArray: List<JsonObject>
        get() = (result as? JsonArray)?.mapNotNull { it as? JsonObject } ?: emptyList()

    val resultObject: JsonObject? get() = result as? JsonObject

    val resultString: String? get() = result?.stringOrNull()

    companion object {
        fun of(response: CloudflareResponse): CloudflarePayload {
            val envelope = runCatching {
                Json.parseToJsonElement(response.body).jsonObject
            }.getOrNull() ?: throw CloudflareError.UnreadableResponse(response.status)

            val success = envelope["success"]?.jsonPrimitive?.booleanOrNull ?: false
            if (!success) {
                val errors = (envelope["errors"] as? JsonArray)?.mapNotNull { it as? JsonObject }
                throw CloudflareError.of(response.status, errors.orEmpty())
            }
            return CloudflarePayload(envelope["result"])
        }
    }
}

/** What went wrong, in the terms Cloudflare used */
sealed class CloudflareError(override val message: String) : Exception(message) {
    data object InvalidToken : CloudflareError("Invalid API token")

    data class ZoneNotFound(val zone: String) :
        CloudflareError("no zone named $zone in this account")

    data class Api(val code: Int, val text: String) :
        CloudflareError("$text (Cloudflare code $code)")

    data class UnreadableResponse(val status: Int) :
        CloudflareError("unreadable response from Cloudflare (HTTP $status)")

    data class BadRequest(val path: String) :
        CloudflareError("could not build a request for $path")

    internal companion object {
        fun of(status: Int, errors: List<JsonObject>): CloudflareError {
            val first = errors.firstOrNull()
            val code = first?.get("code")?.intOrNull() ?: 0
            val text = first?.get("message")?.stringOrNull() ?: "HTTP $status"
            return if (code == 1000 || code == 6003 || status == 401 || status == 403) {
                InvalidToken
            } else {
                Api(code, text)
            }
        }
    }
}

internal fun JsonElement.stringOrNull(): String? =
    (this as? JsonPrimitive)?.takeIf { it.isString }?.content

internal fun JsonElement.intOrNull(): Int? =
    (this as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull
