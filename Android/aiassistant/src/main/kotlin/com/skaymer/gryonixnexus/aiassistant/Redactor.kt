package com.skaymer.gryonixnexus.aiassistant

/** Removes secrets from text before it leaves the device. */
object Redactor {
    private const val KEY_WORDS =
        "password|passwd|passphrase|pwd|secret|token|credential|apikey|(?<![A-Za-z0-9])key(?![A-Za-z])|[_.-]key"

    private val rules: List<Pair<Regex, String>> = listOf(
        "-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|\\z)" to
            "[REDACTED PRIVATE KEY]",
        "(\\b(?:proxy-)?authorization\\b)(\\s*[:=]\\s*)(?:(?:bearer|basic|token|digest)\\s+)?[^\\s,;\"']+" to
            "$1$2[REDACTED]",
        "\\bbearer\\s+[A-Za-z0-9._~+/=-]{8,}" to "Bearer [REDACTED]",
        "\\beyJ[A-Za-z0-9_-]{5,}\\.[A-Za-z0-9_-]{5,}\\.[A-Za-z0-9_-]*" to "[REDACTED JWT]",
        "(?<=://)[^/\\s:@]+:[^/\\s@]+@" to "[REDACTED]@",
        "(--?(?:password|passwd|token|secret|api-key|apikey)[ =])\\S+" to "$1[REDACTED]",
        "([A-Za-z0-9_.-]*(?:$KEY_WORDS)[A-Za-z0-9_.-]*)([\"']?\\s*[:=]\\s*)(\"[^\"]*\"|'[^']*'|[^\\s,;]+)" to
            "$1$2[REDACTED]",
    ).map { (pattern, template) -> Regex(pattern, RegexOption.IGNORE_CASE) to template }

    private val longToken = Regex("(?<![A-Za-z0-9+/_=-])[A-Za-z0-9+/_=-]{32,}(?![A-Za-z0-9+/_=-])")

    fun redact(text: String): String {
        var result = text
        for ((regex, template) in rules) result = regex.replace(result, template)
        return longToken.replace(result) { if (looksSecret(it.value)) "[REDACTED]" else it.value }
    }

    private fun looksSecret(token: String): Boolean = token.any(Char::isDigit) && token.any(Char::isLetter)
}
