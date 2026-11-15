package com.skaymer.gryonixnexus.app.agent

/** Plain values the agent health rows show */
object AgentHealthText {
    fun startedAt(milliseconds: Long): Long? = milliseconds.takeIf { it > 0 }

    /** Version and size of an add-on, joined for one line */
    fun moduleDetail(version: String, size: String): String =
        listOf(version, size).filter { it.isNotBlank() }.joinToString(" · ")

    /** Never negative, so a skewed clock cannot print nonsense */
    fun nonNegative(bytes: Long): Long = bytes.coerceAtLeast(0)
}
