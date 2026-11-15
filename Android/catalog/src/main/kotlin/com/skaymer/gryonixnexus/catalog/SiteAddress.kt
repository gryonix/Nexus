package com.skaymer.gryonixnexus.catalog

/** A web address a person types for a service */
object SiteAddress {
    /** A host name Caddy and DNS both accept */
    fun isValid(host: String): Boolean {
        val labels = host.split(".")
        if (host.length > 253 || labels.size < 2) return false
        return labels.all { label ->
            label.isNotEmpty() && label.length <= 63 && !label.startsWith("-") && !label.endsWith("-") &&
                label.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '-' }
        }
    }

    /** The typed address, trimmed and lowercased */
    fun normalized(typed: String): String = typed.trim().lowercase()
}
