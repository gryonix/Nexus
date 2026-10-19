package com.skaymer.gryonixnexus.catalog

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class DeploymentScope(val wireValue: String) {
    /** Normal flow: a real domain, DNS records, automatic ACME certificates */
    @SerialName("publicInternet") PUBLIC_INTERNET("publicInternet"),

    @SerialName("localOnly") LOCAL_ONLY("localOnly"),

    @SerialName("cloudflareTunnel") CLOUDFLARE_TUNNEL("cloudflareTunnel"),

    @SerialName("dynamicDNS") DYNAMIC_DNS("dynamicDNS"),

    @SerialName("meshOnly") MESH_ONLY("meshOnly");

    /** Whether Caddy issues its own certificate instead of asking ACME */
    val usesInternalTLS: Boolean
        get() = when (this) {
            PUBLIC_INTERNET, DYNAMIC_DNS -> false
            LOCAL_ONLY, CLOUDFLARE_TUNNEL, MESH_ONLY -> true
        }

    /** Whether the deployment publishes A records naming its own address */
    val publishesAddressRecords: Boolean
        get() = when (this) {
            PUBLIC_INTERNET, DYNAMIC_DNS -> true
            LOCAL_ONLY, CLOUDFLARE_TUNNEL, MESH_ONLY -> false
        }

    val carriesNonWebServices: Boolean
        get() = when (this) {
            PUBLIC_INTERNET, DYNAMIC_DNS -> true
            LOCAL_ONLY, CLOUDFLARE_TUNNEL, MESH_ONLY -> false
        }

    /** Whether the server keeps its own DNS records current */
    val maintainsItsOwnDNSRecords: Boolean get() = this == DYNAMIC_DNS

    val requiresMesh: Boolean get() = this == MESH_ONLY

    companion object {
        fun from(wireValue: String): DeploymentScope? =
            entries.firstOrNull { it.wireValue == wireValue }
    }
}
