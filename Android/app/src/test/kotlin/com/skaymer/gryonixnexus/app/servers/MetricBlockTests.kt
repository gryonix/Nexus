package com.skaymer.gryonixnexus.app.servers

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The room a card gives its readings */
class MetricBlockTests {
    @Test
    fun `the block is one height, and the style is not part of the question`() {
        assertEquals(MetricBlock.WIDE, MetricBlock.height(compact = false))
        assertEquals(MetricBlock.COMPACT, MetricBlock.height(compact = true))
        assertTrue(MetricBlock.COMPACT < MetricBlock.WIDE)
    }

    @Test
    fun `a ring is the room that is there, not a rung on a ladder`() {
        val small = RingLayout.diameter(width = 200f, height = MetricBlock.WIDE, count = 3)
        val large = RingLayout.diameter(width = 320f, height = MetricBlock.WIDE, count = 3)
        assertTrue(large > small)
    }

    @Test
    fun `a row of rings pays for the air BETWEEN them, not around them`() {
        val between = RingLayout.diameter(width = 300f, height = 200f, count = 3, outerAir = false)
        val around = RingLayout.diameter(width = 300f, height = 200f, count = 3, outerAir = true)
        assertTrue(between > around)
        assertEquals((300f - MetricBlock.RING_GUTTER * 2) / 3f, between)
    }

    @Test
    fun `a ring never grows past the block it is drawn in`() {
        val diameter = RingLayout.diameter(width = 900f, height = MetricBlock.WIDE, count = 3)
        assertEquals(MetricBlock.WIDE - MetricBlock.LABEL_HEIGHT, diameter)
    }

    @Test
    fun `a ring is never drawn smaller than a dot with a number in it`() {
        val diameter = RingLayout.diameter(width = 40f, height = 30f, count = 3)
        assertEquals(MetricBlock.RING_FLOOR, diameter)
    }

    @Test
    fun `rings stack only where standing under one another draws them bigger`() {
        assertFalse(RingLayout.stacks(width = 150f, height = MetricBlock.COMPACT, count = 3))
        assertTrue(RingLayout.stacks(width = 150f, height = 350f, count = 3))
    }

    @Test
    fun `a stacked ring is not drawn smaller than a dot either`() {
        val cramped = RingLayout.stackedDiameter(width = 150f, height = MetricBlock.COMPACT, count = 3)
        assertEquals(MetricBlock.RING_FLOOR, cramped)
    }

    @Test
    fun `a stacked ring costs width for its name and not height`() {
        val stacked = RingLayout.stackedDiameter(width = 200f, height = 300f, count = 3)
        assertEquals((300f - MetricBlock.STACKED_RING_GUTTER * 2) / 3f, stacked)
    }
}
