package com.skaymer.gryonixnexus.profile.advanced

/** Hysteria2 and NaiveProxy share links. */
internal object ExtraLinks {
    fun hysteria2(link: String): SubscriptionImport.Outcome {
        val parts = ProxyLinkParts.parse(link)
        if (parts == null || parts.host.isEmpty()) return SubscriptionImport.skip(null, link, "the link is incomplete")
        val authority = parts.body.substringAfterLast('@')
        if (parts.port == null && ':' in authority && !authority.endsWith("]")) {
            return SubscriptionImport.skip(parts, link, "port ranges are not supported")
        }
        val fields = linkedMapOf("password" to ProxyLinkParts.percentDecoded(parts.userInfo))
        parts.query["sni"]?.let { fields["sni"] = it }
        if (parts.query["insecure"] == "1") fields["insecure"] = "1"
        parts.query["obfs"]?.let { fields["obfs"] = it }
        parts.query["obfs-password"]?.let { fields["obfsPassword"] = it }
        return SubscriptionImport.Outcome.Server(
            AdvancedServer.create(ServerKind.HYSTERIA2, parts.fragment, parts.host, parts.port ?: 443, fields),
        )
    }

    fun naive(link: String): SubscriptionImport.Outcome {
        val parts = ProxyLinkParts.parse(link)
        if (parts == null || parts.host.isEmpty()) return SubscriptionImport.skip(null, link, "the link is incomplete")
        val fields = linkedMapOf<String, String>()
        val login = ProxyLinkParts.percentDecoded(parts.userInfo)
        val colon = login.indexOf(':')
        if (colon >= 0) {
            fields["user"] = login.substring(0, colon)
            fields["password"] = login.substring(colon + 1)
        } else if (login.isNotEmpty()) {
            fields["user"] = login
        }
        parts.query["sni"]?.let { fields["sni"] = it }
        return SubscriptionImport.Outcome.Server(
            AdvancedServer.create(ServerKind.NAIVE, parts.fragment, parts.host, parts.port ?: 443, fields),
        )
    }
}
