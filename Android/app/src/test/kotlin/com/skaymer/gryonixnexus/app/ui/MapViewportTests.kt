package com.skaymer.gryonixnexus.app.ui

import java.io.File
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class MapViewportTests {
    private val viewport = MapViewport(2000f, 1000f)
    private val viewWidth = 400f
    private val viewHeight = 200f

    @Test
    fun `a pinch keeps the map point under the fingers`() {
        val anchorX = 320f
        val anchorY = 40f
        val beforeX = viewport.mapX(anchorX, viewWidth, viewHeight)
        val beforeY = viewport.mapY(anchorY, viewWidth, viewHeight)
        val zoomed = viewport.zoom(3f, anchorX, anchorY, viewWidth, viewHeight)
        assertTrue(abs(beforeX - zoomed.mapX(anchorX, viewWidth, viewHeight)) < 0.001f)
        assertTrue(abs(beforeY - zoomed.mapY(anchorY, viewWidth, viewHeight)) < 0.001f)
        assertEquals(3f, zoomed.scale)
    }

    @Test
    fun `a tall view shows the whole map and then fills with the zoom`() {
        val tallHeight = 800f
        val shownWidth = viewport.visibleWidth(viewWidth, tallHeight)
        val shownHeight = viewport.visibleHeight(viewWidth, tallHeight)
        assertTrue(abs(shownWidth - 2000f) < 0.001f)
        assertTrue(shownHeight > 1000f)
        assertTrue(abs(viewport.visibleY(viewWidth, tallHeight) + shownHeight / 2 - 500f) < 0.001f)

        val zoomed = viewport.zoom(4f, 200f, 400f, viewWidth, tallHeight)
        assertTrue(zoomed.visibleWidth(viewWidth, tallHeight) < 2000f)
        assertTrue(zoomed.visibleHeight(viewWidth, tallHeight) <= 1000f)
        assertTrue(zoomed.visibleY(viewWidth, tallHeight) >= 0f)
    }

    @Test
    fun `the visible rect never leaves the map`() {
        val zoomed = viewport.zoom(4f, 0f, 0f, viewWidth, viewHeight)
        val far = zoomed.pan(10_000f, 10_000f, viewWidth, viewHeight)
        assertEquals(0f, far.originX)
        assertEquals(0f, far.originY)
        val other = zoomed.pan(-10_000f, -10_000f, viewWidth, viewHeight)
        assertTrue(abs(other.originX + other.visibleWidth(viewWidth, viewHeight) - 2000f) < 0.001f)
        assertTrue(abs(other.originY + other.visibleHeight(viewWidth, viewHeight) - 1000f) < 0.001f)
    }

    @Test
    fun `zooming out stops at the whole map`() {
        val out = viewport.zoom(0.1f, 200f, 100f, viewWidth, viewHeight)
        assertEquals(1f, out.scale)
        assertEquals(0f, out.originX)
        assertEquals(0f, out.originY)
        assertFalse(out.isZoomedIn)
    }

    @Test
    fun `zooming in stops at the limit`() {
        val deep = viewport.zoom(1000f, 200f, 100f, viewWidth, viewHeight)
        assertEquals(MapViewport.MAX_SCALE, deep.scale)
    }

    @Test
    fun `a tap zoomed in hits the country under the finger`() {
        val map = WorldMap.decode(File("src/main/assets/world-map.json").readText())
        val germany = map.countries.getValue("DE")
        val cardWidth = 360f
        val cardHeight = cardWidth / map.width * map.height
        val middleX = cardWidth / 2
        val middleY = cardHeight / 2
        var zoomed = MapViewport(map.width, map.height)
            .zoom(6f, middleX, middleY, cardWidth, cardHeight)
        val perUnit = zoomed.pointsPerUnit(cardWidth, cardHeight)
        zoomed = zoomed.pan(
            (zoomed.mapX(middleX, cardWidth, cardHeight) - germany.centerX) * perUnit,
            (zoomed.mapY(middleY, cardWidth, cardHeight) - germany.centerY) * perUnit,
            cardWidth, cardHeight,
        )
        assertEquals("DE", map.countryAt(zoomed.mapX(middleX, cardWidth, cardHeight),
                                         zoomed.mapY(middleY, cardWidth, cardHeight),
                                         tolerance = 1f))
    }

    @Test
    fun `reset goes back to the whole world`() {
        val back = viewport.zoom(5f, 50f, 50f, viewWidth, viewHeight)
            .reset(viewWidth, viewHeight)
        assertEquals(1f, back.scale)
        assertEquals(0f, back.originX)
        assertEquals(0f, back.originY)
    }
}
