package com.skaymer.gryonixnexus.aiassistant

import java.time.Instant
import java.time.ZoneOffset

enum class AIBudgetState { UNLIMITED, OK, NEAR_LIMIT, REACHED }

/** Tokens used per calendar month, kept on this device. */
class AITokenLedger(initial: Map<String, Int> = emptyMap()) {
    private val months = initial.toMutableMap()

    fun add(tokens: Int, atMillis: Long) {
        months.merge(monthKey(atMillis), maxOf(0, tokens), Int::plus)
    }

    fun used(atMillis: Long): Int = months[monthKey(atMillis)] ?: 0

    fun snapshot(): Map<String, Int> = months.toMap()

    companion object {
        fun monthKey(millis: Long): String {
            val date = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC)
            return "%04d-%02d".format(date.year, date.monthValue)
        }

        fun state(used: Int, limit: Int): AIBudgetState = when {
            limit <= 0 -> AIBudgetState.UNLIMITED
            used >= limit -> AIBudgetState.REACHED
            used * 10 >= limit * 8 -> AIBudgetState.NEAR_LIMIT
            else -> AIBudgetState.OK
        }
    }
}
