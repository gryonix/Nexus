package com.skaymer.gryonixnexus.app.ui

import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class WorldMapTests {
    private val map = WorldMap.decode(File("src/main/assets/world-map.json").readText())

    @Test
    fun `every pickable country has a shape or a dot`() {
        val missing = CountryCatalog.allCodes.filterNot(map.countries::containsKey)
        assertTrue(missing.isEmpty(), "no map entry for $missing")
    }

    @Test
    fun `a tap on a country's middle finds that country`() {
        for (code in listOf("DE", "BR", "RU", "AU", "US")) {
            val country = map.countries.getValue(code)
            assertEquals(code, map.countryAt(country.centerX, country.centerY, tolerance = 1f))
        }
    }

    @Test
    fun `crimea is drawn as part of ukraine`() {
        assertEquals("UA", map.countryAt(1172f, 213f, tolerance = 1f),
                     "the source draws Crimea as Russia; the generator moves it")
    }

    @Test
    fun `russia is not in europe`() {
        assertEquals(Continent.ASIA, CountryCatalog.regionByCode["RU"]?.continent)
        assertTrue("RU" !in CountryCatalog.codesIn(Continent.EUROPE))
        assertTrue("RU" in CountryCatalog.codesIn(CountryRegion.NORTHERN_ASIA))
    }

    @Test
    fun `every shape on the map can be picked from the list`() {
        val unpickable = map.countries.keys.filterNot(CountryCatalog.allCodes::contains)
        assertTrue(unpickable.isEmpty(),
                   "$unpickable are drawn but not offered, so they stay grey whatever is picked")
    }

    @Test
    fun `the continents cover every country exactly once`() {
        val covered = Continent.entries.flatMap(CountryCatalog::codesIn)
        assertEquals(CountryCatalog.allCodes.size, covered.size)
        assertEquals(CountryCatalog.allCodes.toSet(), covered.toSet())
    }

    @Test
    fun `the regions cover every country exactly once`() {
        val covered = CountryRegion.entries.flatMap(CountryCatalog::codesIn)
        assertEquals(CountryCatalog.allCodes.size, covered.size)
        assertEquals(CountryCatalog.allCodes.toSet(), covered.toSet())
    }

    @Test
    fun `every continent holds the regions that name it`() {
        for (continent in Continent.entries) {
            val fromRegions = continent.regions.flatMap(CountryCatalog::codesIn).toSet()
            assertEquals(CountryCatalog.codesIn(continent).toSet(), fromRegions,
                         "$continent disagrees with its own regions")
            assertTrue(continent.regions.isNotEmpty())
        }
    }

    @Test
    fun `a region ripples out within the stagger limit`() {
        val delays = MapTransition.staggered(CountryCatalog.codesIn(CountryRegion.EASTERN_EUROPE).toSet(), map)
        assertTrue(delays.values.all { it in 0..MapTransition.MAX_STAGGER_MILLIS })
        assertEquals(MapTransition.MAX_STAGGER_MILLIS, delays.values.max())
    }
}
