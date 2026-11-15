package com.skaymer.gryonixnexus.recipe

object AgentVersion {
    /** Numeric components, ignoring anything that is not a number */
    internal fun components(version: String): List<Int>? {
        val trimmed = version.trim()
        if (trimmed.firstOrNull()?.isDigit() != true) return null
        val parts = trimmed.split('.', '-', '+').map { part -> part.takeWhile { it.isDigit() } }.filter { it.isNotEmpty() }
        return parts.mapNotNull { it.toIntOrNull() }
    }

    /** Is [candidate] a LATER version than [installed]? */
    fun isNewer(candidate: String, than: String, today: java.time.LocalDate = java.time.LocalDate.now(java.time.ZoneOffset.UTC)): Boolean {
        val a = components(candidate)?.let { orderingKey(it, today) } ?: return false
        val b = components(than)?.let { orderingKey(it, today) } ?: return false
        for (index in 0 until maxOf(a.size, b.size)) {
            val left = a.getOrElse(index) { 0 }
            val right = b.getOrElse(index) { 0 }
            if (left != right) return left > right
        }
        return false
    }

    /** Old November counters sort below dated 26.11.D versions */
    internal fun orderingKey(parts: List<Int>, today: java.time.LocalDate): List<Int> {
        if (parts.size < 3 || parts[0] != 26 || parts[1] != 11) return parts
        val day = parts[2]
        val inFuture = day > 30 || java.time.LocalDate.of(2026, 11, day).isAfter(today)
        return if (inFuture) listOf(26, 11, 0) + parts.drop(2) else parts
    }
}
