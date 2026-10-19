package com.skaymer.gryonixnexus.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** One published name and where the tunnel should send it */
data class TunnelRoute(
    val hostname: String,
    /** What the connector dials on the server itself */
    val service: String = "https://127.0.0.1:443",
)

class CloudflareTunnelProvider(
    token: String,
    private val accountID: String,
    http: CloudflareHTTPClient = JdkCloudflareHTTPClient(),
    baseURL: String = CLOUDFLARE_API,
) {
    private val transport = CloudflareTransport(token, http, baseURL)

    // ------------------------------------------------------------ Discovery

    companion object {
        /** Where a tunnel hostname points */
        const val TUNNEL_DOMAIN = "cfargotunnel.com"

        suspend fun accountID(
            token: String,
            http: CloudflareHTTPClient = JdkCloudflareHTTPClient(),
            baseURL: String = CLOUDFLARE_API,
        ): String {
            val transport = CloudflareTransport(token, http, baseURL)
            val payload = transport.send(CloudflareTransport.Method.GET, "zones")
            for (zone in payload.resultArray) {
                val id = (zone["account"] as? JsonObject)?.get("id")?.stringOrNull()
                if (!id.isNullOrEmpty()) return id
            }
            throw CloudflareError.Api(0, "no zone in this account names its account id")
        }
    }

    // ----------------------------------------------------------- The tunnel

    suspend fun findOrCreateTunnel(name: String): String {
        val existing = transport.send(
            CloudflareTransport.Method.GET,
            "accounts/$accountID/cfd_tunnel",
            query = mapOf("is_deleted" to "false", "name" to name),
        )
        val found = existing.resultArray
            .firstOrNull { it["name"]?.stringOrNull() == name }
            ?.get("id")?.stringOrNull()
        if (!found.isNullOrEmpty()) return found

        val created = transport.send(
            CloudflareTransport.Method.POST,
            "accounts/$accountID/cfd_tunnel",
            body = JsonObject(
                mapOf(
                    "name" to JsonPrimitive(name),
                    "config_src" to JsonPrimitive("cloudflare"),
                ),
            ),
        )
        val id = created.resultObject?.get("id")?.stringOrNull()
        if (id.isNullOrEmpty()) throw CloudflareError.Api(0, "the tunnel was created without an id")
        return id
    }

    /** The credential the connector runs with — what goes into `TUNNEL_TOKEN` */
    suspend fun connectorToken(tunnelID: String): String {
        val payload = transport.send(
            CloudflareTransport.Method.GET,
            "accounts/$accountID/cfd_tunnel/$tunnelID/token",
        )
        val token = payload.resultString
        if (token.isNullOrEmpty()) {
            throw CloudflareError.Api(0, "the tunnel returned no connector token")
        }
        return token
    }

    /** Point every published name at this server's Caddy */
    suspend fun applyIngress(tunnelID: String, routes: List<TunnelRoute>) {
        val ingress = routes.map { route ->
            JsonObject(
                mapOf(
                    "hostname" to JsonPrimitive(route.hostname),
                    "service" to JsonPrimitive(route.service),
                    "originRequest" to JsonObject(
                        mapOf(
                            "noTLSVerify" to JsonPrimitive(true),
                            "originServerName" to JsonPrimitive(route.hostname),
                        ),
                    ),
                ),
            )
        } + JsonObject(mapOf("service" to JsonPrimitive("http_status:404")))

        transport.send(
            CloudflareTransport.Method.PUT,
            "accounts/$accountID/cfd_tunnel/$tunnelID/configurations",
            body = JsonObject(
                mapOf("config" to JsonObject(mapOf("ingress" to JsonArray(ingress)))),
            ),
        )
    }

    /** Remove a tunnel */
    suspend fun deleteTunnel(id: String) {
        transport.send(CloudflareTransport.Method.DELETE, "accounts/$accountID/cfd_tunnel/$id")
    }

    // ------------------------------------------------------------ The names

    suspend fun publishHostnames(
        hostnames: List<String>,
        tunnelID: String,
        zone: String,
    ): List<String> {
        val zoneID = transport.zoneID(zone)
        val target = "$tunnelID.$TUNNEL_DOMAIN"
        for (hostname in hostnames) publish(hostname, target, zoneID)
        return hostnames
    }

    /** One name as a proxied CNAME, clearing its address records */
    private suspend fun publish(hostname: String, target: String, zoneID: String) {
        val existing = transport.send(
            CloudflareTransport.Method.GET,
            "zones/$zoneID/dns_records",
            query = mapOf("name" to hostname),
        )
        var cnameID: String? = null
        for (record in existing.resultArray) {
            val id = record["id"]?.stringOrNull() ?: continue
            when (record["type"]?.stringOrNull()) {
                "CNAME" -> cnameID = id
                "A", "AAAA" -> transport.send(CloudflareTransport.Method.DELETE, "zones/$zoneID/dns_records/$id")
            }
        }
        val body = JsonObject(
            mapOf(
                "type" to JsonPrimitive("CNAME"),
                "name" to JsonPrimitive(hostname),
                "content" to JsonPrimitive(target),
                "ttl" to JsonPrimitive(1),
                "proxied" to JsonPrimitive(true),
            ),
        )
        val id = cnameID
        if (id != null) {
            transport.send(CloudflareTransport.Method.PUT, "zones/$zoneID/dns_records/$id", body = body)
        } else {
            transport.send(CloudflareTransport.Method.POST, "zones/$zoneID/dns_records", body = body)
        }
    }
}
