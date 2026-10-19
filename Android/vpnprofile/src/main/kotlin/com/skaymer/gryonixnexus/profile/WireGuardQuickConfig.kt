package com.skaymer.gryonixnexus.profile

/** A `wg-quick` configuration as the VPN panel exports it */
class WireGuardQuickConfig private constructor(
    /** The exact `[Interface]`/`[Peer]` text */
    val rawText: String,
    /** `host:port` from the peer's Endpoint — also the tunnel's server address */
    val endpoint: String,
    /** A short label derived from the endpoint host */
    val name: String,
    /** The interface's own addresses, e.g */
    val addresses: List<String>,
    val dns: List<String>,
    val mtu: Int?,
    /** The peer's public key — what identifies the server end */
    val peerPublicKey: String?,
    /** `["0.0.0.0/0", "::/0"]` for a full tunnel */
    val allowedIPs: List<String>,
    val persistentKeepalive: Int?,
    val obfuscation: List<Pair<String, String>>,
) {
    val isObfuscated: Boolean get() = obfuscation.isNotEmpty()

    /** Equal by the TEXT, matching Swift's hand-written `==` */
    override fun equals(other: Any?): Boolean =
        this === other || (other is WireGuardQuickConfig && rawText == other.rawText)

    override fun hashCode(): Int = rawText.hashCode()

    /** A reason, not a sentence */
    enum class ParseFailure { MISSING_INTERFACE, MISSING_PEER, MISSING_ENDPOINT, SEVERAL_PEERS }

    class ParseException(val failure: ParseFailure) : Exception(failure.name)

    companion object {
        /** The nine keys AmneziaWG adds under `[Interface]` */
        internal val OBFUSCATION_KEYS =
            listOf("Jc", "Jmin", "Jmax", "S1", "S2", "H1", "H2", "H3", "H4")

        @Throws(ParseException::class)
        fun parse(text: String): WireGuardQuickConfig {
            val trimmed = text.trim()
            val sections = sections(trimmed)
            val interfaceSection = sections.firstOrNull { it.name == "interface" }
                ?: throw ParseException(ParseFailure.MISSING_INTERFACE)
            val peers = sections.filter { it.name == "peer" }
            val peer = peers.firstOrNull() ?: throw ParseException(ParseFailure.MISSING_PEER)
            if (peers.size > 1) throw ParseException(ParseFailure.SEVERAL_PEERS)
            val endpoint = peer.value("Endpoint")
                ?: throw ParseException(ParseFailure.MISSING_ENDPOINT)

            return WireGuardQuickConfig(
                rawText = trimmed,
                endpoint = endpoint,
                name = host(endpoint),
                addresses = list(interfaceSection.allValues("Address")),
                dns = list(interfaceSection.allValues("DNS")),
                mtu = interfaceSection.value("MTU")?.toIntOrNull(),
                peerPublicKey = peer.value("PublicKey"),
                allowedIPs = list(peer.allValues("AllowedIPs")),
                persistentKeepalive = peer.value("PersistentKeepalive")?.toIntOrNull(),
                obfuscation = OBFUSCATION_KEYS.mapNotNull { key ->
                    interfaceSection.value(key)?.let { key to it }
                },
            )
        }

        /** One `[Name]` block and its `Key = value` lines */
        private class Section(val name: String, val lines: List<String>) {
            /** Every line of this key, joined as one comma list */
            fun allValues(key: String): String? =
                lines.mapNotNull { Section(name, listOf(it)).value(key) }
                    .takeIf { it.isNotEmpty() }?.joinToString(",")

            fun value(key: String): String? {
                for (line in lines) {
                    val stripped = line.substringBefore('#')
                    val parts = stripped.split("=", limit = 2)
                    if (parts.size != 2) continue
                    if (!parts[0].trim().equals(key, ignoreCase = true)) continue
                    val value = parts[1].trim()
                    if (value.isNotEmpty()) return value
                }
                return null
            }
        }

        private fun sections(text: String): List<Section> {
            val sections = mutableListOf<Section>()
            var name: String? = null
            var lines = mutableListOf<String>()
            for (rawLine in text.split("\n")) {
                val line = rawLine.trim()
                if (line.startsWith("[") && line.endsWith("]")) {
                    name?.let { sections += Section(it, lines) }
                    name = line.drop(1).dropLast(1).lowercase()
                    lines = mutableListOf()
                } else if (name != null) {
                    lines += line
                }
            }
            name?.let { sections += Section(it, lines) }
            return sections
        }

        /** `10.9.0.4/32, fd00::4/128` — wg-quick's comma-separated lists */
        private fun list(value: String?): List<String> =
            value?.split(",")?.map(String::trim)?.filter(String::isNotEmpty) ?: emptyList()

        private fun host(endpoint: String): String {
            if (endpoint.startsWith("[")) {
                val close = endpoint.indexOf(']')
                if (close > 0) return endpoint.substring(1, close)
            }
            val colon = endpoint.lastIndexOf(':')
            return if (colon < 0) endpoint else endpoint.substring(0, colon)
        }
    }
}
