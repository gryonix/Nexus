package com.skaymer.gryonixnexus.app.metrics

import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** Where a machine's history opens */
class HistoryPresentationTests {
    @Test
    fun `a separate screen until somebody says otherwise, as on the other side`() {
        assertEquals(false, HistoryPresentation.inline(null))
        assertTrue(HistoryPresentation.inline(true))
        assertEquals(false, HistoryPresentation.inline(false))
    }

    @Test
    fun `the key is the one the other app writes`() {
        assertEquals("metrics.historyInline", HistoryPresentation.INLINE_KEY)
    }
}
