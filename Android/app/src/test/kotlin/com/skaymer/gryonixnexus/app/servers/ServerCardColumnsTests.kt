package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.servercontrol.ServerCardSize
import kotlin.test.assertEquals
import org.junit.jupiter.api.Test

class ServerCardColumnsTests {
    @Test
    fun `an unset setting means one wide card per row`() {
        assertEquals(ServerCardColumns.ONE, ServerCardColumns.of(null))
        assertEquals(ServerCardSize.WIDE, ServerCardColumns.of(null).cardSize)
    }

    @Test
    fun `two columns means the compact card`() {
        assertEquals(ServerCardSize.COMPACT, ServerCardColumns.TWO.cardSize)
    }

    @Test
    fun `the stored spellings are honoured and anything else falls back`() {
        assertEquals(ServerCardColumns.TWO, ServerCardColumns.of("two"))
        assertEquals(ServerCardColumns.ONE, ServerCardColumns.of("one"))
        assertEquals(ServerCardColumns.ONE, ServerCardColumns.of("compact"))
    }
}
