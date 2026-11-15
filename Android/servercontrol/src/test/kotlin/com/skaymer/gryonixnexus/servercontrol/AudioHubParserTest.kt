package com.skaymer.gryonixnexus.servercontrol

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class AudioHubParserTest {
    @Test
    fun outputsPlayersAndServicesComeFromOdioBodies() {
        val outputs = AudioHubParser.outputs("""[{"id":0,"name":"alsa_output.hdmi","description":"HDMI","volume":0.5,"muted":false,"default":true}]""")
        assertEquals(listOf(AudioHubState.Output("alsa_output.hdmi", "HDMI", 0.5, false, true)), outputs)

        val players = AudioHubParser.players("""[{"bus_name":"org.mpris.MediaPlayer2.mpd","identity":"Music Player Daemon","playback_status":"Playing","metadata":{"xesam:title":"Song","xesam:artist":"Band"},"capabilities":{"can_go_next":true}}]""")
        assertEquals("Song", players.first().title)
        assertEquals("Band", players.first().artist)
        assertTrue(players.first().isPlaying)
        assertFalse(players.first().canGoPrevious)

        val services = AudioHubParser.services("""[{"name":"bluetooth.service","scope":"system","running":true},{"name":"mpd.service","scope":"user","running":false,"exists":true,"description":"Music Player Daemon"},{"name":"spotifyd.service","scope":"user","exists":false}]""")
        assertEquals(listOf(AudioHubState.Service("mpd.service", "Music Player Daemon", false)), services)
    }

    @Test
    fun serverAndBluetoothStateAndVolumeBody() {
        var state = AudioHubParser.withServer("""{"volume":0.8,"muted":true}""", AudioHubState())
        state = AudioHubParser.withBluetooth("""{"powered":true,"pairing_active":false}""", state)
        assertEquals(80, AudioHubState.percent(state.volume))
        assertTrue(state.muted)
        assertTrue(state.bluetoothPowered)
        assertEquals("""{"volume":1.00}""", AudioHubParser.volumeBody(1.4))
        assertTrue(AudioHubParser.withServer("not json", state).muted)
    }
}
