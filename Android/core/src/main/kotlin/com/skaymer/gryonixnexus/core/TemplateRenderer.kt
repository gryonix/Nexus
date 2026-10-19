package com.skaymer.gryonixnexus.core

/** Renders text templates into a finished config */
interface TemplateRenderer {
    fun render(template: String, values: Map<String, String>): String
}

class UnresolvedPlaceholderException(val placeholder: String) :
    Exception("unresolved placeholder $placeholder")

/** A simple built-in renderer with no external dependencies */
class StringTemplateRenderer : TemplateRenderer {
    override fun render(template: String, values: Map<String, String>): String {
        var result = template
        for ((key, value) in values) {
            result = result.replace("{{$key}}", value)
        }
        REMAINING.find(result)?.let { throw UnresolvedPlaceholderException(it.value) }
        return result
    }

    private companion object {
        val REMAINING = Regex("""\{\{[A-Za-z0-9_.-]+}}""")
    }
}
