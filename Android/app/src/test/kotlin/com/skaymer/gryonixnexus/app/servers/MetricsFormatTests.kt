package com.skaymer.gryonixnexus.app.servers

import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class MetricsFormatTests {
    private val cases: List<Triple<String, String, String>> = run {
        val text = javaClass.getResourceAsStream("/swift-metrics-format.tsv")
            ?.bufferedReader()?.readText()
            ?: error("the golden is missing — run Tools/dump-metrics-format-golden.sh")
        text.trim().lines().map { line ->
            val parts = line.split("\t")
            require(parts.size == 3) { "unreadable golden line: $line" }
            Triple(parts[0], parts[1], parts[2])
        }
    }

    @Test
    fun `every recorded case formats the same as Swift`() {
        var checked = 0
        for ((kind, input, expected) in cases) {
            val actual = when (kind) {
                "bytes" -> MetricsFormat.bytes(input.toLong())
                "percent" -> MetricsFormat.percent(input.toDouble())
                "load" -> MetricsFormat.load(input.toDouble())
                "temperature" -> MetricsFormat.temperature(input.toDouble())
                "uptime" -> MetricsFormat.uptime(input.toDouble())
                else -> continue
            }
            assertEquals(expected, actual, "$kind($input)")
            checked += 1
        }
        assertEquals(cases.size, checked, "the golden holds a case this test cannot read")
        assertTrue(checked >= 30, "the golden went thin: only $checked cases")
    }

    /** The two ties, named */
    @Test
    fun `a tie rounds to the even digit, not upwards`() {
        assertEquals("1.2", MetricsFormat.load(1.25))
        assertEquals("42°C", MetricsFormat.temperature(42.5))
    }

    @Test
    fun `a rate is a byte count per second`() {
        assertEquals("1.2 M/s", MetricsFormat.rate(1_258_291.0))
        assertEquals("0 B/s", MetricsFormat.rate(0.0))
    }
}
