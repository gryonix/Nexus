package com.skaymer.gryonixnexus.profile.advanced

/** Reads a domain list: plain, hosts-file or adblock lines. */
object BlockListParser {
    /** Most domains one list may add to the tunnel */
    const val DOMAIN_LIMIT = 15_000

    fun domains(text: String): List<String> {
        val seen = LinkedHashSet<String>()
        for (raw in text.lines()) {
            val domain = domain(raw) ?: continue
            seen.add(domain)
            if (seen.size >= DOMAIN_LIMIT) break
        }
        return seen.toList()
    }

    internal fun domain(raw: String): String? {
        var line = raw.trim()
        if (line.isEmpty() || line[0] in "#![") return null
        line.indexOf('#').takeIf { it >= 0 }?.let { line = line.substring(0, it).trim() }
        if (line.startsWith("||")) {
            line = line.drop(2)
            val end = line.indexOfFirst { it == '^' || it == '$' || it == '/' }
            if (end < 0) return valid(line)
            val rest = line.substring(end)
            return if (rest.startsWith("^") && rest.length <= 1) valid(line.substring(0, end)) else null
        }
        val fields = line.split(' ', '\t').filter { it.isNotEmpty() }
        if (fields.size == 2 && fields[0] in listOf("0.0.0.0", "127.0.0.1", "::")) return valid(fields[1])
        return if (fields.size == 1) valid(fields[0]) else null
    }

    private fun valid(text: String): String? {
        val domain = text.lowercase().trim('.')
        if ('.' !in domain || domain == "localhost") return null
        if (!domain.all { it.isLetterOrDigit() || it == '-' || it == '.' || it == '_' }) return null
        if (domain.all { it.isDigit() || it == '.' }) return null
        return domain
    }
}
