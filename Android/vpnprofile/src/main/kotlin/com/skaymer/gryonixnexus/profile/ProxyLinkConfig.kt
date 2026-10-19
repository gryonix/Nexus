package com.skaymer.gryonixnexus.profile

data class ProxyLinkConfig(
    val rawText: String,
    val kind: Kind,
    val host: String,
    val port: Int,
    /** The `#fragment`, percent-decoded — the panel writes the device's name there */
    val label: String,
    val credential: Credential,
) {
    enum class Kind(val scheme: String) {
        SHADOWSOCKS("ss"),
        VLESS("vless"),
    }

    sealed interface Credential {
        data class Shadowsocks(val method: String, val password: String) : Credential

        data class Vless(
            val uuid: String,
            /** `none`, `tls` or `reality` */
            val security: String,
            val sni: String,
            /** The uTLS profile to imitate */
            val fingerprint: String,
            val publicKey: String,
            val shortID: String,
            /** `xtls-rprx-vision`, usually */
            val flow: String,
            /** `tcp`, `ws` or `grpc` */
            val network: String,
            /** WebSocket only: the request path and the `Host` header */
            val path: String,
            val host: String,
            /** gRPC only */
            val serviceName: String,
        ) : Credential
    }

    /** `host:port`, the form `TunnelProfile.endpoint` is written in */
    val endpoint: String get() = if (host.contains(":")) "[$host]:$port" else "$host:$port"

    sealed interface ParseFailure {
        data class NoLink(val kind: Kind) : ParseFailure

        data class NoEndpoint(val kind: Kind) : ParseFailure

        data class NoCredential(val kind: Kind) : ParseFailure

        data class UnsupportedTransport(val name: String) : ParseFailure
    }

    class ParseException(val failure: ParseFailure) : Exception(failure.toString())

    companion object {
        /** What the datapath has a branch for */
        internal val CARRIED_NETWORKS = setOf("tcp", "ws", "grpc")
        internal val CARRIED_SECURITIES = setOf("none", "tls", "reality")

        fun kindOf(text: String): Kind? =
            Kind.entries.firstOrNull { VPNLink.firstLink(text, it.scheme) != null }

        @Throws(ParseException::class)
        fun parse(text: String): ProxyLinkConfig {
            val kind = kindOf(text) ?: throw ParseException(ParseFailure.NoLink(Kind.SHADOWSOCKS))
            return parse(text, kind)
        }

        @Throws(ParseException::class)
        fun parse(text: String, kind: Kind): ProxyLinkConfig {
            val link = VPNLink.firstLink(text, kind.scheme)
                ?: throw ParseException(ParseFailure.NoLink(kind))
            val body = link.removePrefix("${kind.scheme}://")
            val fragment = body.substringAfter('#', "")
            val beforeFragment = body.substringBefore('#')
            val query = beforeFragment.substringAfter('?', "")
            val authority = beforeFragment.substringBefore('?')

            val userInfo = authority.substringBeforeLast('@', "")
            val hostPort = if (authority.contains('@')) authority.substringAfterLast('@') else authority
            val endpoint = readEndpoint(hostPort) ?: legacyEndpoint(authority)
                ?: throw ParseException(ParseFailure.NoEndpoint(kind))

            val credential = when (kind) {
                Kind.SHADOWSOCKS -> {
                    if (queryFields(query)["plugin"].orEmpty().isNotEmpty()) {
                        throw ParseException(ParseFailure.UnsupportedTransport("plugin"))
                    }
                    shadowsocks(userInfo, authority)
                }
                Kind.VLESS -> {
                    if (userInfo.isEmpty()) null
                    else {
                        val fields = queryFields(query)
                        val security = fields["security"] ?: "none"
                        if (security !in CARRIED_SECURITIES) {
                            throw ParseException(ParseFailure.UnsupportedTransport(security))
                        }
                        val network = fields["type"] ?: "tcp"
                        if (network !in CARRIED_NETWORKS) {
                            throw ParseException(ParseFailure.UnsupportedTransport(network))
                        }
                        Credential.Vless(
                            uuid = userInfo,
                            security = security,
                            sni = fields["sni"] ?: fields["peer"] ?: "",
                            fingerprint = fields["fp"] ?: "",
                            publicKey = fields["pbk"] ?: "",
                            shortID = fields["sid"] ?: "",
                            flow = if (security == "none") "" else (fields["flow"] ?: ""),
                            network = network,
                            path = fields["path"] ?: "",
                            host = fields["host"] ?: "",
                            serviceName = fields["serviceName"] ?: "",
                        )
                    }
                }
            } ?: throw ParseException(ParseFailure.NoCredential(kind))

            return ProxyLinkConfig(
                rawText = link,
                kind = kind,
                host = endpoint.first,
                port = endpoint.second,
                label = percentDecoded(fragment),
                credential = credential,
            )
        }

        private fun readEndpoint(hostPort: String): Pair<String, Int>? {
            if (hostPort.isEmpty()) return null
            val colon = hostPort.lastIndexOf(':')
            if (colon <= 0) return null
            val host = hostPort.substring(0, colon)
            val port = hostPort.substring(colon + 1).toIntOrNull() ?: return null
            if (host.isEmpty() || port !in 1..65_535) return null
            return host to port
        }

        private fun legacyEndpoint(authority: String): Pair<String, Int>? {
            val decoded = base64Decoded(authority) ?: return null
            val at = decoded.lastIndexOf('@')
            if (at < 0) return null
            return readEndpoint(decoded.substring(at + 1))
        }

        private fun shadowsocks(userInfo: String, authority: String): Credential? {
            if (userInfo.isNotEmpty()) {
                val pair = if (userInfo.contains(':')) percentDecoded(userInfo)
                else base64Decoded(userInfo) ?: return null
                return split(pair)
            }
            val decoded = base64Decoded(authority) ?: return null
            val at = decoded.lastIndexOf('@')
            if (at < 0) return null
            return split(decoded.substring(0, at))
        }

        /** `method:password` → the two halves */
        private fun split(pair: String): Credential? {
            val colon = pair.indexOf(':')
            if (colon <= 0) return null
            val method = pair.substring(0, colon)
            val password = pair.substring(colon + 1)
            if (method.isEmpty() || password.isEmpty()) return null
            return Credential.Shadowsocks(method, password)
        }

        private fun queryFields(query: String): Map<String, String> =
            query.split('&')
                .mapNotNull { field ->
                    val name = field.substringBefore('=', "")
                    val value = field.substringAfter('=', "")
                    if (name.isEmpty() || value.isEmpty()) null
                    else name to percentDecoded(value)
                }
                .toMap()

        internal fun base64Decoded(text: String): String? {
            if (text.isEmpty()) return null
            val normalised = text.replace('-', '+').replace('_', '/')
            val padded = normalised + "=".repeat((4 - normalised.length % 4) % 4)
            return try {
                String(java.util.Base64.getDecoder().decode(padded), Charsets.UTF_8)
            } catch (invalid: IllegalArgumentException) {
                null
            }
        }

        private fun percentDecoded(text: String): String =
            try {
                java.net.URLDecoder.decode(text.replace("+", "%2B"), "UTF-8")
            } catch (invalid: IllegalArgumentException) {
                text
            }
    }
}
