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
    fun isNewer(candidate: String, than: String): Boolean {
        val a = components(candidate) ?: return false
        val b = components(than) ?: return false
        for (index in 0 until maxOf(a.size, b.size)) {
            val left = a.getOrElse(index) { 0 }
            val right = b.getOrElse(index) { 0 }
            if (left != right) return left > right
        }
        return false
    }
}
