package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.profile.ProxyLinkConfig
import com.skaymer.gryonixnexus.profile.WireGuardQuickConfig
import java.net.URLDecoder

/** A configuration from a server the app does not manage */
object ForeignTunnelConfig {
    data class Detected(val protocol: ServiceID, val text: String, val suggestedName: String)

    sealed class Failure : Exception() {
        data object Empty : Failure()

        data object NotRecognised : Failure()

        /** Read, but this build cannot bring it up */
        data class NotCarried(val protocol: ServiceID) : Failure()

        data object Unreadable : Failure()
    }

    fun detect(input: String): Detected {
        val text = input.trim()
        if (text.isEmpty()) throw Failure.Empty
        AmneziaKey.link(text)?.let { key ->
            val decoded = AmneziaKey.decode(key)
            return wireGuard(decoded.config, decoded.name)
        }
        if (text.contains("[Interface]", ignoreCase = true)) return wireGuard(text, null)
        ProxyLinkConfig.kindOf(text)?.let { return proxy(text, it) }
        if (text.contains("\nremote ") || text.startsWith("client") || text.startsWith("remote ")) {
            throw Failure.NotCarried(ServiceID.OPEN_VPN)
        }
        throw Failure.NotRecognised
    }

    private fun wireGuard(text: String, name: String?): Detected {
        val config = runCatching { WireGuardQuickConfig.parse(text) }.getOrNull() ?: throw Failure.Unreadable
        val protocol = if (config.isObfuscated) ServiceID.AMNEZIA_WG else ServiceID.WIREGUARD_VPN
        return Detected(protocol, config.rawText, name?.trim()?.ifEmpty { null } ?: config.name)
    }

    private fun proxy(text: String, kind: ProxyLinkConfig.Kind): Detected {
        val link = runCatching { ProxyLinkConfig.parse(text, kind) }.getOrNull() ?: throw Failure.Unreadable
        val protocol = if (kind == ProxyLinkConfig.Kind.SHADOWSOCKS) ServiceID.SHADOWSOCKS else ServiceID.XRAY_REALITY
        return Detected(protocol, link.rawText, fragment(link.rawText) ?: link.host)
    }

    /** The `#name` a share link ends with */
    fun fragment(link: String): String? {
        val raw = link.substringAfterLast('#', "")
        if (raw.isEmpty()) return null
        return runCatching { URLDecoder.decode(raw.replace("+", "%2B"), "UTF-8") }.getOrDefault(raw).trim().ifEmpty { null }
    }
}
