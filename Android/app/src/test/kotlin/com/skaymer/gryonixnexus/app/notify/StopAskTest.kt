package com.skaymer.gryonixnexus.app.notify

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class StopAskTest {
    @Test
    fun theFirstTapAsksAndAStopTapWithinFiveSecondsStops() {
        val ask = StopAsk()
        assertEquals(StopAsk.Tap.ASK, ask.tap(1_000))
        assertTrue(ask.isAsking(1_000))
        assertTrue(ask.isAsking(5_999))
        assertEquals(StopAsk.Tap.STOP, ask.tap(5_999))
        assertFalse(ask.isAsking(6_000))
    }

    @Test
    fun theQuestionLapsesAfterFiveSecondsAndTheNextTapAsksAgain() {
        val ask = StopAsk()
        assertEquals(StopAsk.Tap.ASK, ask.tap(1_000))
        assertFalse(ask.isAsking(6_000))
        assertEquals(StopAsk.Tap.ASK, ask.tap(6_000))
        assertEquals(StopAsk.Tap.STOP, ask.tap(7_000))
    }

    @Test
    fun aStopStartsOverWithAQuestion() {
        val ask = StopAsk()
        ask.tap(0)
        ask.tap(1)
        assertEquals(StopAsk.Tap.ASK, ask.tap(2))
    }
}
