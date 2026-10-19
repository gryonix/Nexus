package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.AppLanguage

/** Facts read back out of an install report */
object InstallReportFacts {
    /** The deployment's domain, as the report states it */
    fun domain(report: String): String? {
        for (language in AppLanguage.entries) {
            val label = L10nScripts.domainLabel(language).trim()
            if (label.isEmpty()) continue
            for (line in report.split("\n")) {
                val text = line.trim()
                if (!text.startsWith(label)) continue
                val candidate = sanitised(text.drop(label.length).trim()) ?: continue
                return candidate
            }
        }
        return null
    }

    /** What may be taken as a domain */
    private fun sanitised(value: String): String? {
        val candidate = value.lowercase()
        if (!candidate.contains(".")) return null
        if (candidate.contains(" ") || candidate.contains("/") || candidate.contains(":")) return null
        if (candidate.startsWith(".") || candidate.endsWith(".")) return null
        if (!candidate.all { it.isLetter() || it.isDigit() || it == '.' || it == '-' }) return null
        return candidate
    }
}
