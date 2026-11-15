package com.skaymer.gryonixnexus.servercontrol

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AudioHubSourcesTest {
    @Test
    fun theReadingTellsWhichPlayersAreInstalled() {
        val both = AudioHubSources.parse("""{"spotify.name":"Living room","spotify.bitrate":"320","airplay.name":"%h"}""")
        assertTrue(both.hasSpotify)
        assertTrue(both.hasAirPlay)
        assertFalse(AudioHubSources.parse("{}").hasSpotify)
        assertTrue(AudioHubSources.parse("not json").values.isEmpty())
    }

    @Test
    fun onlyEditedValuesAreSent() {
        val saved = AudioHubSources(mapOf("spotify.name" to "Kitchen", "spotify.bitrate" to "320", "airplay.name" to "%h"))
        assertNull(saved.changes(saved))
        val edited = saved.with("spotify.name", "Living room").with("spotify.bitrate", "160")
        assertEquals("""{"spotify.bitrate":"160","spotify.name":"Living room"}""", edited.changes(saved))
    }
}
