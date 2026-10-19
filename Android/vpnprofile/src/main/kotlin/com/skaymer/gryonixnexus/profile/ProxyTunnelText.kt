package com.skaymer.gryonixnexus.profile

/** A proxy link stored with its DNS */
object ProxyTunnelText {
    private const val PREFIX = "dns="

    val fallbackDNS: List<String> = listOf("1.1.1.1", "8.8.8.8")

    fun compose(link: String, dns: List<String>): String =
        if (dns.isEmpty()) link else link + "\n" + PREFIX + dns.joinToString(",")

    /** The link alone, and the DNS kept beside it */
    fun split(text: String): Pair<String, List<String>> {
        val lines = text.lines().filter { it.isNotBlank() }
        val link = lines.firstOrNull { !it.startsWith(PREFIX) }.orEmpty()
        val dns = lines.firstOrNull { it.startsWith(PREFIX) }
            ?.removePrefix(PREFIX)?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }.orEmpty()
        return link to dns.ifEmpty { fallbackDNS }
    }

    /** IPv4 resolvers when any: proxy servers may lack IPv6 */
    fun reachableDNS(dns: List<String>): List<String> = dns.filter { ':' !in it }.ifEmpty { dns }
}
