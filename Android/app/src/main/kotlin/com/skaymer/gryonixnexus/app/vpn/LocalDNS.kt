package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry

/** AdGuard Home or Pi-hole on the VPN's own server */
data class LocalDNS(
    /** Empty when the server cannot relay one */
    val address: String = "",
    /** The resolvers devices can reach there */
    val services: List<ServiceID> = emptyList(),
) {
    val isOffered: Boolean get() = address.isNotEmpty() && services.isNotEmpty()

    fun isChosen(addresses: List<String>): Boolean = address.isNotEmpty() && addresses == listOf(address)

    /** Chosen, but no resolver answers there */
    fun isGone(addresses: List<String>): Boolean = isChosen(addresses) && services.isEmpty()

    /** The resolvers' names, or null when none is installed */
    val serviceNames: String?
        get() = services.takeIf { it.isNotEmpty() }
            ?.joinToString(" / ") { ServiceRegistry.service(it)?.displayName ?: it.rawValue }

    /** Whose resolver these addresses are */
    fun source(addresses: List<String>): DNSSource = when {
        isChosen(addresses) -> DNSSource.YourServer(serviceNames)
        addresses == listOf(SERVER_ADDRESS) -> DNSSource.YourServer(null)
        addresses.isEmpty() -> DNSSource.Public(PublicDNS.all.first())
        else -> PublicDNS.matching(addresses)?.let { DNSSource.Public(it) } ?: DNSSource.Typed(addresses)
    }

    companion object {
        /** Where the agent relays its server's resolver */
        const val SERVER_ADDRESS = "10.53.0.53"

        /** The choice itself, without the trailing relay */
        fun chosen(dns: List<String>): List<String> =
            if (dns.size > 1 && dns.last() == SERVER_ADDRESS) dns.dropLast(1) else dns
    }
}

/** Where a device's DNS answers come from */
sealed interface DNSSource {
    /** The user's own server; names null when unknown */
    data class YourServer(val names: String?) : DNSSource

    data class Public(val preset: PublicDNS) : DNSSource

    data class Typed(val addresses: List<String>) : DNSSource
}
