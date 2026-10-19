package com.skaymer.gryonixnexus.core

import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class CloudflareRequest(
    val method: String,
    /** The full URL, query string included */
    val url: String,
    val headers: Map<String, String>,
    val body: String? = null,
)

/** What came back: the raw text and the HTTP status */
data class CloudflareResponse(val body: String, val status: Int)

/** The one call the Cloudflare providers make on the network */
interface CloudflareHTTPClient {
    suspend fun send(request: CloudflareRequest): CloudflareResponse
}

class JdkCloudflareHTTPClient(
    private val client: HttpClient = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(15))
        .build(),
    private val timeout: Duration = Duration.ofSeconds(30),
) : CloudflareHTTPClient {
    override suspend fun send(request: CloudflareRequest): CloudflareResponse =
        withContext(Dispatchers.IO) {
            val builder = HttpRequest.newBuilder(URI.create(request.url)).timeout(timeout)
            for ((key, value) in request.headers) builder.header(key, value)
            val publisher = request.body
                ?.let { HttpRequest.BodyPublishers.ofString(it) }
                ?: HttpRequest.BodyPublishers.noBody()
            builder.method(request.method, publisher)
            val response = client.send(builder.build(), HttpResponse.BodyHandlers.ofString())
            CloudflareResponse(body = response.body().orEmpty(), status = response.statusCode())
        }
}
