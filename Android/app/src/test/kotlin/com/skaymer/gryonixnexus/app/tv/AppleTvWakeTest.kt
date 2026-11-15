package com.skaymer.gryonixnexus.app.tv

import com.skaymer.gryonixnexus.tvlink.TvAddress
import com.skaymer.gryonixnexus.tvlink.TvPairedTv
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AppleTvWakeTest {
    private val now = 1_800_000_000L
    private val paired = listOf(
        TvPairedTv("tv-living", "draco", TvAddress("192.0.2.4"), pairedAt = 1),
        TvPairedTv("tv-sleeping", "orion", TvAddress("192.0.2.5"), pairedAt = 1),
    )

    private fun seen(id: String, ago: Long?) = TvNearby(id, id, TvAddress("192.0.2.4"), ago?.let { now - it })

    @Test
    fun aTvWithAFreshStampIsVouchedTo() {
        assertEquals(listOf("tv-living"), awakeTvs(paired, listOf(seen("tv-living", 30)), now).map { it.id })
    }

    @Test
    fun aSleepingTvKeepsAnOldStampAndIsLeftAlone() {
        val nearby = listOf(seen("tv-living", 30), seen("tv-sleeping", 600))
        assertEquals(listOf("tv-living"), awakeTvs(paired, nearby, now).map { it.id })
    }

    @Test
    fun aRecordWithoutAStampIsLeftAlone() {
        assertTrue(awakeTvs(paired, listOf(seen("tv-living", null)), now).isEmpty())
        assertFalse(seen("tv-living", 200).isAwake(now))
    }

    @Test
    fun aSleepingTvIsNotDialledByItsLastAddress() {
        assertTrue(awakeTvs(paired, emptyList(), now).isEmpty())
    }

    @Test
    fun confirmingByHandReachesEveryTvTheNetworkSees() {
        val nearby = listOf(seen("tv-living", 30), seen("tv-sleeping", null))
        assertEquals(listOf("tv-living", "tv-sleeping"), seenTvs(paired, nearby).map { it.id })
    }
}
