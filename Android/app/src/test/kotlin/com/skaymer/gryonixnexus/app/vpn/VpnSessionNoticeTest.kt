package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import com.skaymer.gryonixnexus.catalog.ServiceID
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class VpnSessionNoticeTest {
    @Test
    fun `the notice names the server and the protocol`() {
        val session = VpnTunnel.Session("gvps.example.net", ServiceID.WIREGUARD_VPN, 1_000L)
        val text = VpnSessionNotice.content(session, "VPN connected")
        assertEquals("VPN connected · gvps.example.net", text.title)
        assertEquals(VpnSessionNotice.protocolName(ServiceID.WIREGUARD_VPN), text.body)
    }

    @Test
    fun `without a server the title says only connected`() {
        val session = VpnTunnel.Session("", ServiceID.AMNEZIA_WG, 1_000L)
        assertEquals("VPN connected", VpnSessionNotice.content(session, "VPN connected").title)
    }

    @Test
    fun `the switch is on until turned off and remembered`() {
        val store = InMemorySettingsStore()
        assertTrue(VpnSessionNoticeSettings(store).isEnabled.value)
        VpnSessionNoticeSettings(store).setEnabled(false)
        assertFalse(VpnSessionNoticeSettings(store).isEnabled.value)
    }

    @Test
    fun `a protocol carries the users own name where set and kept`() {
        val store = InMemorySettingsStore()
        val session = VpnTunnel.Session("", ServiceID.XRAY_REALITY, 1_000L)
        VpnSessionNoticeSettings(store).setLabel(ServiceID.XRAY_REALITY, "VR")
        VpnSessionNoticeSettings(store).setLabel(ServiceID.SHADOWSOCKS, "  ")
        val labels = VpnSessionNoticeSettings(store).labels.value
        assertEquals(mapOf("xray-reality" to "VR"), labels)
        assertEquals("VR", VpnSessionNotice.content(session, "VPN connected", labels).body)
        val other = VpnTunnel.Session("", ServiceID.SHADOWSOCKS, 1_000L)
        assertEquals(VpnSessionNotice.protocolName(ServiceID.SHADOWSOCKS), VpnSessionNotice.content(other, "c", labels).body)
        VpnSessionNoticeSettings(store).setLabel(ServiceID.XRAY_REALITY, "HOMETUNNEL")
        assertEquals("HOMETUNN", VpnSessionNoticeSettings(store).labels.value["xray-reality"])
    }
}
