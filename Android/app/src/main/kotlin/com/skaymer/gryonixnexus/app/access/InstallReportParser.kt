package com.skaymer.gryonixnexus.app.access

/** Lenient parser of the install report text into copyable fields */
object InstallReportParser {
    data class Field(val label: String, val value: String)

    data class Section(val title: String, val fields: List<Field> = emptyList())

    fun sections(text: String): List<Section> {
        val result = mutableListOf<Section>()
        var title: String? = null
        var fields = mutableListOf<Field>()

        fun close() {
            val current = title
            if (current != null && fields.isNotEmpty()) result.add(Section(current, fields.toList()))
        }

        for (line in text.split("\n")) {
            val trimmed = line.trim()
            if (trimmed.isEmpty()) continue
            val indented = line.first().isWhitespace()
            if (!indented) {
                val colon = trimmed.indexOf(": ")
                if (colon >= 0) {
                    close()
                    title = trimmed.substring(0, colon)
                    fields = mutableListOf()
                    val rest = trimmed.substring(colon + 2).trim()
                    if (rest.isNotEmpty()) fields.add(Field(URL, rest))
                } else if (trimmed.endsWith(":")) {
                    close()
                    title = trimmed.dropLast(1)
                    fields = mutableListOf()
                }
                continue
            }
            if (title == null) continue
            val colon = trimmed.indexOf(": ")
            if (colon < 0) continue
            val label = trimmed.substring(0, colon)
            val value = trimmed.substring(colon + 2).trim()
            if (label.isEmpty() || value.isEmpty()) continue
            fields.add(Field(label, value))
        }
        close()
        return result
    }

    const val URL = "URL"
}
