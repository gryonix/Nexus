package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.carriesASession
import com.skaymer.gryonixnexus.app.ui.vpnMarkRes
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** When the VPN section's mark closes its shield */
class TunnelMarkStateTests {
    @Test
    fun `the shield and the globe are two different drawables`() {
        assertEquals(R.drawable.tab_icon_logo, vpnMarkRes(tunnelActive = true))
        assertEquals(R.drawable.tab_icon_globe, vpnMarkRes(tunnelActive = false))
        assertNotEquals(
            vpnMarkRes(tunnelActive = true),
            vpnMarkRes(tunnelActive = false),
            "one picture for both states says nothing",
        )
    }

    @Test
    fun `a session that is up carries the shield`() {
        assertTrue(VpnTunnel.State.Up("iPhone").carriesASession())
    }

    @Test
    fun `nothing up is the bare globe`() {
        assertFalse(VpnTunnel.State.Down.carriesASession())
    }

    @Test
    fun `a tunnel in the middle of coming up or going down still carries the shield`() {
        assertTrue(VpnTunnel.State.Working("iPhone").carriesASession())
    }

    @Test
    fun `a failed attempt is the bare globe, not a session`() {
        assertFalse(VpnTunnel.State.Failed("permission denied").carriesASession())
    }
}
