package com.skaymer.gryonixnexus.catalog

data class PublishedHostPort(
    val address: String = WILDCARD,
    val port: Int,
    val proto: FirewallPort.Proto = FirewallPort.Proto.TCP
) {
    val label: String get() = "$port/${proto.wireValue}"

    fun collides(other: PublishedHostPort): Boolean {
        if (port != other.port || proto != other.proto) return false
        return address == other.address || isWildcard(address) || isWildcard(other.address)
    }

    companion object {
        /** What compose means by an address-less mapping */
        const val WILDCARD = "0.0.0.0"

        fun isWildcard(address: String): Boolean =
            address.isEmpty() || address == WILDCARD || address == "::" ||
                address == "[::]" || address == "*"
    }
}

object ComposePorts {
    /** Every host port published by a compose body */
    fun published(composeContents: String): List<PublishedHostPort> {
        val found = mutableListOf<PublishedHostPort>()
        var listIndent: Int? = null
        for (line in composeContents.split("\n")) {
            val trimmed = line.trim(' ', '\t')
            if (trimmed.isEmpty()) continue
            val indent = line.takeWhile { it == ' ' }.length
            if (trimmed == "ports:") {
                listIndent = indent
                continue
            }
            val openIndent = listIndent ?: continue
            if (trimmed.startsWith("#")) continue
            if (!trimmed.startsWith("- ") || indent <= openIndent) {
                listIndent = null
                continue
            }
            entry(trimmed.drop(2))?.let { found.add(it) }
        }
        return found
    }

    /** One `ports:` entry — `"IP:HOST:CONTAINER/proto"`, `"HOST:CONTAINER"` */
    fun entry(raw: String): PublishedHostPort? {
        var text = raw.trim(' ', '\t')
        for (quote in listOf("\"", "'")) {
            if (text.length >= 2 && text.startsWith(quote) && text.endsWith(quote)) {
                text = text.substring(1, text.length - 1)
            }
        }
        var proto = FirewallPort.Proto.TCP
        val slash = text.lastIndexOf('/')
        if (slash >= 0) {
            val named = FirewallPort.Proto.entries
                .firstOrNull { it.wireValue == text.substring(slash + 1).lowercase() }
                ?: return null
            proto = named
            text = text.substring(0, slash)
        }
        val parts = text.split(":")
        val address: String
        val hostSide: String
        when (parts.size) {
            3 -> { address = parts[0]; hostSide = parts[1] }
            2 -> { address = PublishedHostPort.WILDCARD; hostSide = parts[0] }
            else -> return null
        }
        val port = hostSide.toIntOrNull() ?: return null
        if (port !in 1..65535) return null
        return PublishedHostPort(address = address, port = port, proto = proto)
    }
}

/** The host ports this service takes when it is installed */
fun ManagedService.publishedHostPorts(context: ServiceContext): List<PublishedHostPort> {
    val compose = composeFile(context)
        ?: return firewallPorts(context).map { PublishedHostPort(port = it.port, proto = it.proto) }
    return ComposePorts.published(compose.composeContents)
}
