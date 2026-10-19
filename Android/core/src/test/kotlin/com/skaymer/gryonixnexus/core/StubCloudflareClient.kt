package com.skaymer.gryonixnexus.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

class StubCloudflareClient(responses: List<Pair<String, Int>>) : CloudflareHTTPClient {
    private val queue = ArrayDeque(responses.map { CloudflareResponse(it.first, it.second) })
    private val recorded = mutableListOf<CloudflareRequest>()

    /** Every request made, in order */
    val sent: List<CloudflareRequest> get() = recorded

    /** The body of request [index], parsed */
    fun body(index: Int): JsonObject? =
        recorded[index].body?.let { Json.parseToJsonElement(it).jsonObject }

    /** The body of the last request, parsed */
    fun lastBody(): JsonObject? = body(recorded.lastIndex)

    override suspend fun send(request: CloudflareRequest): CloudflareResponse {
        recorded += request
        return queue.removeFirstOrNull() ?: CloudflareResponse("{}", 500)
    }
}

/** A successful envelope carrying [result] verbatim */
fun ok(result: String): Pair<String, Int> =
    """{"success":true,"errors":[],"result":$result}""" to 200
