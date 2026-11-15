package com.skaymer.gryonixnexus.aiassistant

sealed interface MarkdownBlock {
    data class Paragraph(val text: String) : MarkdownBlock
    data class Heading(val level: Int, val text: String) : MarkdownBlock
    data class Code(val language: String, val text: String) : MarkdownBlock
    data class Bullets(val items: List<String>) : MarkdownBlock
    data class Numbered(val items: List<String>) : MarkdownBlock
    data class Quote(val text: String) : MarkdownBlock
}

/** Block parser; an open fence runs on. */
object MarkdownBlocks {
    fun parse(text: String): List<MarkdownBlock> {
        val blocks = mutableListOf<MarkdownBlock>()
        val paragraph = mutableListOf<String>()
        fun flush() {
            if (paragraph.isNotEmpty()) blocks += MarkdownBlock.Paragraph(paragraph.joinToString("\n"))
            paragraph.clear()
        }
        val lines = text.split("\n").iterator()
        while (lines.hasNext()) {
            val trimmed = lines.next().trim()
            val item = listItem(trimmed)
            val heading = heading(trimmed)
            when {
                trimmed.startsWith("```") -> { flush(); blocks += fence(trimmed.drop(3).trim(), lines) }
                item != null -> { flush(); append(item, blocks) }
                heading != null -> { flush(); blocks += heading }
                trimmed.startsWith(">") -> { flush(); blocks += MarkdownBlock.Quote(trimmed.drop(1).trim()) }
                trimmed.isEmpty() -> flush()
                else -> paragraph += trimmed
            }
        }
        flush()
        return blocks
    }

    private fun fence(language: String, lines: Iterator<String>): MarkdownBlock {
        val body = mutableListOf<String>()
        while (lines.hasNext()) {
            val next = lines.next()
            if (next.trim().startsWith("```")) break
            body += next
        }
        return MarkdownBlock.Code(language, body.joinToString("\n"))
    }

    private fun heading(line: String): MarkdownBlock? {
        val level = line.takeWhile { it == '#' }.length
        if (level !in 1..6 || !line.drop(level).startsWith(" ")) return null
        return MarkdownBlock.Heading(level, line.drop(level).trim())
    }

    private fun listItem(line: String): Pair<Boolean, String>? {
        if (line.startsWith("- ") || line.startsWith("* ") || line.startsWith("+ ")) return false to line.drop(2)
        val digits = line.takeWhile { it.isDigit() }
        if (digits.isEmpty() || !line.drop(digits.length).startsWith(". ")) return null
        return true to line.drop(digits.length + 2)
    }

    private fun append(item: Pair<Boolean, String>, blocks: MutableList<MarkdownBlock>) {
        val last = blocks.lastOrNull()
        when {
            last is MarkdownBlock.Bullets && !item.first -> blocks[blocks.lastIndex] = MarkdownBlock.Bullets(last.items + item.second)
            last is MarkdownBlock.Numbered && item.first -> blocks[blocks.lastIndex] = MarkdownBlock.Numbered(last.items + item.second)
            item.first -> blocks += MarkdownBlock.Numbered(listOf(item.second))
            else -> blocks += MarkdownBlock.Bullets(listOf(item.second))
        }
    }
}
