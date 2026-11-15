package com.skaymer.gryonixnexus.catalog

import com.skaymer.gryonixnexus.catalog.services.ShairportSyncOptions
import com.skaymer.gryonixnexus.catalog.services.ShairportSyncService
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ShairportSyncTest {
    private fun context(settings: ServiceSettings) =
        ServiceContext(domain = "example.com", sshUser = "admin", settings = settings)

    private fun compose(settings: ServiceSettings) =
        ShairportSyncService().composeFile(context(settings))!!.composeContents

    @Test
    fun `options become a config and bad values are dropped`() {
        val options = "interpolation=soxr;output_rate=44100;audio_backend_latency_offset_in_seconds=-0.15;" +
            "volume_range_db=500;mixer_control_name=PCM;output_format=S16\";x;session_timeout=1e3"
        assertEquals(
            "general = {\n  interpolation = \"soxr\";\n  audio_backend_latency_offset_in_seconds = -0.15;\n};\n" +
                "alsa = {\n  mixer_control_name = \"PCM\";\n  output_rate = 44100;\n};\n",
            ShairportSyncOptions.configContents(context(ServiceSettings(shairportOptions = options))),
        )
        assertEquals("interpolation=soxr;output_rate=44100",
            ShairportSyncOptions.text(mapOf("output_rate" to "44100", "interpolation" to "soxr", "session_timeout" to "")))
    }

    @Test
    fun `the mode picks the image tag`() {
        assertTrue(compose(ServiceSettings()).contains("mikebrady/shairport-sync:latest"))
        assertTrue(compose(ServiceSettings(shairportMode = "airplay1")).contains("mikebrady/shairport-sync:classic"))
    }

    @Test
    fun `the name cannot break the command line`() {
        val text = compose(ServiceSettings(shairportName = "A\"$(x)`b\\", shairportOutput = "hw:0;rm"))
        assertTrue(text.contains("-a \"A(x)b\""), text)
        assertTrue(text.contains("-d hw:0rm"), text)
        assertTrue(compose(ServiceSettings(shairportName = "\"", shairportOutput = ";"))
            .contains("-a \"gryonix\" -o alsa -- -d default"))
    }

    @Test
    fun `it is home only, has no backup and keeps its ports off the relay`() {
        val service = ShairportSyncService()
        val ctx = context(ServiceSettings())
        assertTrue(service.requiresHomeMachine)
        assertNull(service.actions(ctx).backup)
        assertNull(service.webIngress(ctx))
        assertEquals(listOf(80), ForwardedPorts.tcp(listOf(service), ctx))
        assertEquals(16, service.firewallPorts(ctx).size)
    }

    @Test
    fun `HDMI volume forces the slider off and shares the metadata pipe`() {
        val settings = ServiceSettings(shairportOptions = "cec_volume=yes;cec_volume_min=5;cec_volume_max=60")
        assertEquals("general = {\n  ignore_volume_control = \"yes\";\n};\nalsa = {\n};\nmetadata = {\n  enabled = \"yes\";\n  include_cover_art = \"no\";\n  pipe_name = \"/run/shairport-sync/metadata\";\n  pipe_timeout = 5000;\n};\n", ShairportSyncOptions.configContents(context(settings)))
        assertEquals("general = {\n};\nalsa = {\n};\n",
            ShairportSyncOptions.configContents(context(ServiceSettings(shairportOptions = "cec_volume=no"))))
        assertTrue(compose(settings).contains(":/etc/shairport-sync.conf:ro\n      - /run/shairport-sync:/run/shairport-sync\n"), compose(settings))
        assertEquals(ShairportSyncOptions.CecVolume(true, 5, 60), ShairportSyncOptions.cecVolume(context(settings)))
    }

    @Test
    fun `a bad HDMI range falls back and keeps the gap`() {
        val bad = context(ServiceSettings(shairportOptions = "cec_volume=yes;cec_volume_min=50;cec_volume_max=10"))
        assertEquals(ShairportSyncOptions.CecVolume(true, 9, 10), ShairportSyncOptions.cecVolume(bad))
        assertEquals(ShairportSyncOptions.CecVolume(false, 1, 40), ShairportSyncOptions.cecVolume(context(ServiceSettings())))
        val wakes = context(ServiceSettings(shairportOptions = "cec_volume=yes;cec_tv_wakes=yes"))
        assertEquals(false, ShairportSyncOptions.cecVolume(wakes).tvOff)
        val timed = context(ServiceSettings(
            shairportOptions = "cec_volume=yes;cec_tv_wait=30;cec_off_delay=5;cec_grace=999;cec_keep_connected=yes"))
        val custom = ShairportSyncOptions.cecVolume(timed)
        assertEquals(listOf(30, 5, 15), listOf(custom.tvWait, custom.offDelay, custom.grace))
        assertEquals(false, custom.disconnect)
    }
}
