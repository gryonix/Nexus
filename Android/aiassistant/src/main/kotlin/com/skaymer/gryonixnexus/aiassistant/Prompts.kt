package com.skaymer.gryonixnexus.aiassistant

enum class AIContextKind { PROBLEM, SERVICE, OPERATION, WEEKLY, TERMINAL_EXPLAIN, TERMINAL_ASK }

data class AIContextSection(val label: String, val text: String)

/** Read-only facts handed to the model, redacted on assembly. */
data class AIContext(val kind: AIContextKind, val title: String, val sections: List<AIContextSection>)

object AIPrompts {
    const val MAX_SECTION_CHARACTERS = 6000

    fun systemPrompt(languageName: String): String =
        """
        You are an advisor inside a server-management app. You only explain and suggest.
        You cannot run commands, change servers or reach anything yourself, and you must never claim or imply that you did or can.
        Offer commands only as suggestions the user should check first, each in a fenced code block, with a short note on what it does and what to verify beforehand.
        If the data is not enough, say what is missing. Secrets are replaced by [REDACTED].
        Answer in $languageName. Be concise.
        """.trimIndent()

    fun contextMessage(context: AIContext): String {
        val parts = mutableListOf(intro(context.kind) + " " + Redactor.redact(context.title))
        for (section in context.sections.filter { it.text.isNotEmpty() }) {
            parts += "### ${section.label}\n```\n${Redactor.redact(tail(section.text))}\n```"
        }
        return parts.joinToString("\n\n")
    }

    fun tail(text: String): String =
        if (text.length <= MAX_SECTION_CHARACTERS) text else "…" + text.takeLast(MAX_SECTION_CHARACTERS)

    private fun intro(kind: AIContextKind): String = when (kind) {
        AIContextKind.PROBLEM -> "Explain this server problem and suggest what to check:"
        AIContextKind.SERVICE -> "Explain what these service logs show and what may be wrong:"
        AIContextKind.OPERATION -> "This operation failed. Explain why and what to check:"
        AIContextKind.WEEKLY -> "Summarise the last 7 days for these servers, noting anything unusual:"
        AIContextKind.TERMINAL_EXPLAIN -> "Explain this terminal command or output:"
        AIContextKind.TERMINAL_ASK -> "Suggest commands for this need, as copy-only suggestions:"
    }
}
