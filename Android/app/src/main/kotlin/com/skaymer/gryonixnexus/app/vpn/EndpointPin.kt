package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.profile.ProxyLinkConfig
import com.skaymer.gryonixnexus.profile.ProxyTunnelText
import com.skaymer.gryonixnexus.profile.WireGuardQuickConfig

/** A server domain this device dials by a pinned address */
data class EndpointPin(val host: String, val address: String)

/** What looking up the domain for a pin ends in */
sealed interface PinOutcome {
    data class Pinned(val pin: EndpointPin) : PinOutcome

    data object NotFound : PinOutcome

    data class Private(val address: String) : PinOutcome
}

/** Dials a configuration's domain by address, leaving its text alone */
object EndpointPins {
    private val PINNABLE = setOf(
        ServiceID.WIREGUARD_VPN, ServiceID.AMNEZIA_WG, ServiceID.SHADOWSOCKS, ServiceID.XRAY_REALITY,
    )

    fun canPin(protocol: ServiceID): Boolean = protocol in PINNABLE

    /** One pin per server, protocol and device */
    fun key(serverId: String, protocol: ServiceID, clientId: String, clientName: String, device: String): String =
        "$serverId/${protocol.rawValue}/${clientId.ifEmpty { clientName.ifEmpty { device } }}"

    fun key(profile: LastTunnel.Profile): String =
        key(profile.serverId, profile.protocol, profile.clientId, profile.clientName, profile.device)

    /** The `host:port` a configuration dials, when it names one */
    fun endpoint(protocol: ServiceID, configuration: String): String? = runCatching {
        if (protocol == ServiceID.SHADOWSOCKS || protocol == ServiceID.XRAY_REALITY) {
            ProxyLinkConfig.parse(ProxyTunnelText.split(configuration).first).endpoint
        } else {
            WireGuardQuickConfig.parse(configuration).endpoint
        }
    }.getOrNull()

    /** The host of `host:port`, without IPv6 brackets */
    fun hostOf(endpoint: String): String {
        if (endpoint.startsWith("[")) return endpoint.substringAfter('[').substringBefore(']')
        val colon = endpoint.lastIndexOf(':')
        return if (colon < 0) endpoint else endpoint.substring(0, colon)
    }

    /** `host:port` with only the host swapped for an address */
    fun replaceHost(endpoint: String, address: String): String {
        val port = if (endpoint.startsWith("[")) {
            endpoint.substringAfter(']', "")
        } else {
            endpoint.lastIndexOf(':').let { if (it < 0) "" else endpoint.substring(it) }
        }
        return (if (address.contains(':')) "[$address]" else address) + port
    }

    /** Whether the configuration's domain can be pinned at all */
    fun offersChoice(protocol: ServiceID, endpoint: String?): Boolean =
        endpoint != null && canPin(protocol) && !isAddressLiteral(hostOf(endpoint))

    /** The pinned address, while the pin still fits the configuration */
    fun address(pin: EndpointPin?, protocol: ServiceID, endpoint: String?): String? {
        if (pin == null || !offersChoice(protocol, endpoint)) return null
        if (!hostOf(endpoint!!).equals(pin.host, ignoreCase = true)) return null
        return pin.address
    }

    /** The endpoint actually dialed when a pin applies */
    fun pinnedEndpoint(pin: EndpointPin?, protocol: ServiceID, endpoint: String?): String? =
        address(pin, protocol, endpoint)?.let { replaceHost(endpoint!!, it) }

    /** The WireGuard text with the peer's Endpoint host swapped */
    fun pinnedWireGuard(configuration: String, address: String): String {
        var inPeer = false
        return configuration.lines().joinToString("\n") { line ->
            val trimmed = line.trim()
            if (trimmed.startsWith("[")) inPeer = trimmed.equals("[Peer]", ignoreCase = true)
            if (inPeer && isEndpointLine(trimmed)) {
                "Endpoint = " + replaceHost(trimmed.substringAfter('=').substringBefore('#').trim(), address)
            } else {
                line
            }
        }
    }

    private fun isEndpointLine(line: String): Boolean =
        line.contains('=') && line.substringBefore('=').trim().equals("Endpoint", ignoreCase = true)

    /** The proxy link aimed at an address, keeping TLS names */
    fun pinnedLink(link: ProxyLinkConfig, address: String): ProxyLinkConfig {
        val credential = link.credential
        val kept = if (credential is ProxyLinkConfig.Credential.Vless && credential.security != "none") {
            credential.copy(sni = credential.sni.ifEmpty { link.host })
        } else {
            credential
        }
        return link.copy(host = address, credential = kept)
    }

    /** A lookup's answers turned into a pin or a refusal */
    fun outcome(host: String, resolved: List<String>): PinOutcome {
        val address = preferred(resolved) ?: return PinOutcome.NotFound
        if (!isPublicAddress(address)) return PinOutcome.Private(address)
        return PinOutcome.Pinned(EndpointPin(host, address))
    }

    /** IPv4 first, else IPv6 */
    fun preferred(addresses: List<String>): String? =
        addresses.firstOrNull { ipv4(it) != null } ?: addresses.firstOrNull { ipv6(it) != null }

    fun isAddressLiteral(host: String): Boolean = ipv4(host) != null || ipv6(host) != null

    /** Routable on the internet: no private, local or multicast */
    fun isPublicAddress(address: String): Boolean {
        ipv4(address)?.let { return isPublicV4(it) }
        val v6 = ipv6(address) ?: return false
        mappedV4(v6)?.let { return isPublicV4(it) }
        return isPublicV6(v6)
    }

    private fun isPublicV4(bytes: IntArray): Boolean {
        val first = bytes[0]
        val second = bytes[1]
        return !(
            first == 0 || first == 10 || first == 127 || first >= 224 ||
                (first == 100 && second in 64..127) ||
                (first == 169 && second == 254) ||
                (first == 172 && second in 16..31) ||
                (first == 192 && second == 168) ||
                (first == 198 && second in 18..19)
            )
    }

    private fun isPublicV6(bytes: IntArray): Boolean {
        val unspecifiedOrLoopback = bytes.take(15).all { it == 0 } && bytes[15] <= 1
        val uniqueLocal = (bytes[0] and 0xFE) == 0xFC
        val linkLocal = bytes[0] == 0xFE && (bytes[1] and 0xC0) == 0x80
        val multicast = bytes[0] == 0xFF
        return !(unspecifiedOrLoopback || uniqueLocal || linkLocal || multicast)
    }

    /** The IPv4 inside `::ffff:a.b.c.d` */
    private fun mappedV4(bytes: IntArray): IntArray? {
        val mapped = bytes.take(10).all { it == 0 } && bytes[10] == 0xFF && bytes[11] == 0xFF
        return if (mapped) bytes.copyOfRange(12, 16) else null
    }

    /** Four bytes of a dotted IPv4 literal */
    internal fun ipv4(text: String): IntArray? {
        val parts = text.split('.')
        if (parts.size != 4) return null
        if (parts.any { it.isEmpty() || it.length > 3 || !it.all { c -> c in '0'..'9' } }) return null
        val bytes = parts.map { it.toInt() }
        return if (bytes.all { it in 0..255 }) bytes.toIntArray() else null
    }

    /** Sixteen bytes of an IPv6 literal, zone dropped */
    internal fun ipv6(text: String): IntArray? {
        val bare = text.substringBefore('%')
        if (!bare.contains(':')) return null
        val halves = bare.split("::")
        if (halves.size > 2) return null
        val head = groups(halves[0]) ?: return null
        val tail = if (halves.size == 2) groups(halves[1]) ?: return null else emptyList()
        val missing = 8 - head.size - tail.size
        if (if (halves.size == 1) missing != 0 else missing < 1) return null
        val words = head + List(if (halves.size == 2) missing else 0) { 0 } + tail
        return words.flatMap { listOf(it shr 8, it and 0xFF) }.toIntArray()
    }

    /** Colon-separated 16-bit groups; a final IPv4 counts two */
    private fun groups(text: String): List<Int>? {
        if (text.isEmpty()) return emptyList()
        val parts = text.split(':')
        val words = mutableListOf<Int>()
        parts.forEachIndexed { index, part ->
            if (index == parts.lastIndex && part.contains('.')) {
                val v4 = ipv4(part) ?: return null
                words += (v4[0] shl 8) or v4[1]
                words += (v4[2] shl 8) or v4[3]
            } else {
                if (part.isEmpty() || part.length > 4 || !part.all(::isHexDigit)) return null
                words += part.toInt(16)
            }
        }
        return words
    }

    private fun isHexDigit(char: Char): Boolean = char in '0'..'9' || char.lowercaseChar() in 'a'..'f'
}
