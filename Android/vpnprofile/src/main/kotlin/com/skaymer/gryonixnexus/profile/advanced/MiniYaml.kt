package com.skaymer.gryonixnexus.profile.advanced

sealed interface YamlValue {
    data class Scalar(val text: String) : YamlValue
    data class Items(val items: List<YamlValue>) : YamlValue
    data class Entries(val entries: Map<String, YamlValue>) : YamlValue
    data object Null : YamlValue

    val string: String? get() = (this as? Scalar)?.text
    val list: List<YamlValue>? get() = (this as? Items)?.items
    operator fun get(key: String): YamlValue? = (this as? Entries)?.entries?.get(key)
}

object MiniYaml {
    private class Line(var indent: Int, var text: String)

    fun parse(text: String): YamlValue {
        val lines = text.lines().mapNotNull { raw ->
            val stripped = stripComment(raw).replace("\t", "  ")
            val trimmed = stripped.trim()
            if (trimmed.isEmpty() || trimmed == "---") null else Line(stripped.takeWhile { it == ' ' }.length, trimmed)
        }.toMutableList()
        if (lines.isEmpty()) return YamlValue.Null
        return block(lines, intArrayOf(0), lines[0].indent)
    }

    private fun stripComment(line: String): String {
        var quote: Char? = null
        var previous = ' '
        for ((offset, character) in line.withIndex()) {
            val open = quote
            if (open != null) {
                if (character == open) quote = null
            } else if (character == '"' || character == '\'') {
                quote = character
            } else if (character == '#' && (previous == ' ' || offset == 0)) {
                return line.substring(0, offset)
            }
            previous = character
        }
        return line
    }

    private fun isItem(text: String) = text == "-" || text.startsWith("- ")

    private fun block(lines: MutableList<Line>, position: IntArray, indent: Int): YamlValue {
        if (position[0] >= lines.size) return YamlValue.Null
        return if (isItem(lines[position[0]].text)) list(lines, position, indent) else map(lines, position, indent)
    }

    private fun list(lines: MutableList<Line>, position: IntArray, indent: Int): YamlValue {
        val items = mutableListOf<YamlValue>()
        while (position[0] < lines.size && lines[position[0]].indent == indent && isItem(lines[position[0]].text)) {
            val current = lines[position[0]]
            val rest = current.text.drop(1).trim()
            if (rest.isEmpty()) {
                position[0]++
                items.add(nested(lines, position, indent))
            } else if (splitKey(rest) != null && !rest.startsWith("{") && !rest.startsWith("[")) {
                val offset = current.text.length - rest.length
                lines[position[0]] = Line(indent + offset, rest)
                items.add(map(lines, position, indent + offset))
            } else {
                position[0]++
                items.add(inline(rest))
            }
        }
        return YamlValue.Items(items)
    }

    private fun map(lines: MutableList<Line>, position: IntArray, indent: Int): YamlValue {
        val entries = LinkedHashMap<String, YamlValue>()
        while (position[0] < lines.size && lines[position[0]].indent == indent) {
            val (key, value) = splitKey(lines[position[0]].text) ?: break
            position[0]++
            entries[key] = if (value.isEmpty()) nestedOrSiblingList(lines, position, indent) else inline(value)
        }
        return YamlValue.Entries(entries)
    }

    private fun nested(lines: MutableList<Line>, position: IntArray, above: Int): YamlValue {
        if (position[0] >= lines.size || lines[position[0]].indent <= above) return YamlValue.Null
        return block(lines, position, lines[position[0]].indent)
    }

    private fun nestedOrSiblingList(lines: MutableList<Line>, position: IntArray, indent: Int): YamlValue {
        if (position[0] >= lines.size) return YamlValue.Null
        val next = lines[position[0]]
        if (next.indent == indent && isItem(next.text)) return list(lines, position, indent)
        return nested(lines, position, indent)
    }

    /** `key: value` split at the first colon outside quotes */
    private fun splitKey(text: String): Pair<String, String>? {
        var quote: Char? = null
        for ((offset, character) in text.withIndex()) {
            val open = quote
            if (open != null) {
                if (character == open) quote = null
            } else if (character == '"' || character == '\'') {
                quote = character
            } else if (character == '{' || character == '[') {
                return null
            } else if (character == ':' && (offset + 1 == text.length || text[offset + 1] == ' ')) {
                return unquote(text.substring(0, offset).trim()) to text.substring(offset + 1).trim()
            }
        }
        return null
    }

    private fun inline(text: String): YamlValue {
        if (text.startsWith("{") || text.startsWith("[")) return Flow(text).value()
        if (text == "~" || text == "null") return YamlValue.Null
        return YamlValue.Scalar(unquote(text))
    }

    private fun unquote(text: String): String {
        val first = text.firstOrNull() ?: return text
        if (text.length < 2 || first != text.last() || (first != '"' && first != '\'')) return text
        val body = text.substring(1, text.length - 1)
        return if (first == '"') body.replace("\\\"", "\"") else body
    }

    /** Reads `{a: b}` and `[a, b]` */
    private class Flow(val text: String) {
        var index = 0

        fun value(): YamlValue {
            skipSpace()
            if (index >= text.length) return YamlValue.Null
            return when (text[index]) {
                '{' -> mapping()
                '[' -> sequence()
                else -> scalar()
            }
        }

        fun mapping(): YamlValue {
            index++
            val entries = LinkedHashMap<String, YamlValue>()
            while (true) {
                skipSpace()
                if (index >= text.length || text[index] == '}') break
                val key = token(setOf(':', ',', '}'))
                if (index < text.length && text[index] == ':') {
                    index++
                    entries[key] = value()
                }
                skipSpace()
                if (index < text.length && text[index] == ',') index++
            }
            index++
            return YamlValue.Entries(entries)
        }

        fun sequence(): YamlValue {
            index++
            val items = mutableListOf<YamlValue>()
            while (true) {
                skipSpace()
                if (index >= text.length || text[index] == ']') break
                items.add(value())
                skipSpace()
                if (index < text.length && text[index] == ',') index++
            }
            index++
            return YamlValue.Items(items)
        }

        fun scalar(): YamlValue {
            val raw = token(setOf(',', '}', ']'))
            return if (raw == "~" || raw == "null") YamlValue.Null else YamlValue.Scalar(raw)
        }

        fun token(stops: Set<Char>): String {
            skipSpace()
            val result = StringBuilder()
            if (index < text.length && (text[index] == '"' || text[index] == '\'')) {
                val quote = text[index++]
                while (index < text.length && text[index] != quote) result.append(text[index++])
                index++
                return result.toString()
            }
            while (index < text.length && text[index] !in stops) result.append(text[index++])
            return result.toString().trim()
        }

        fun skipSpace() {
            while (index < text.length && text[index] == ' ') index++
        }
    }
}
