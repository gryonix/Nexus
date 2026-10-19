package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import com.skaymer.gryonixnexus.app.vpn.OnDemandPolicy.Network
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class OnDemandPolicyTest {
    @Test
    fun offLeavesTheTunnelAlone() {
        assertNull(OnDemandPolicy().wantsTunnel(Network.Cellular))
    }

    @Test
    fun wiFiOnlyKeepsCellularDown() {
        val policy = OnDemandPolicy(isEnabled = true, scope = OnDemandPolicy.Scope.WIFI)
        assertEquals(true, policy.wantsTunnel(Network.WiFi("Cafe")))
        assertEquals(false, policy.wantsTunnel(Network.Cellular))
    }

    @Test
    fun cellularOnlyKeepsWiFiDown() {
        val policy = OnDemandPolicy(isEnabled = true, scope = OnDemandPolicy.Scope.CELLULAR, networks = listOf("Home"))
        assertEquals(false, policy.wantsTunnel(Network.WiFi("Cafe")))
        assertEquals(true, policy.wantsTunnel(Network.Cellular))
    }

    @Test
    fun exceptListedStaysDownAtHome() {
        val policy = OnDemandPolicy(isEnabled = true, networks = listOf("Home"))
        assertEquals(false, policy.wantsTunnel(Network.WiFi("home")))
        assertEquals(true, policy.wantsTunnel(Network.WiFi("Cafe")))
        assertEquals(true, policy.wantsTunnel(Network.WiFi(null)))
    }

    @Test
    fun onlyListedComesUpOnlyThere() {
        val policy = OnDemandPolicy(
            isEnabled = true,
            mode = OnDemandPolicy.NetworkMode.ONLY_LISTED,
            networks = listOf("Cafe"),
        )
        assertEquals(true, policy.wantsTunnel(Network.WiFi("Cafe")))
        assertEquals(false, policy.wantsTunnel(Network.WiFi("Home")))
        assertEquals(false, policy.wantsTunnel(Network.WiFi(null)))
        assertEquals(true, policy.wantsTunnel(Network.Cellular))
    }

    @Test
    fun settingsSurviveAReload() {
        val store = InMemorySettingsStore()
        OnDemandSettings(store).apply {
            update { it.copy(isEnabled = true, scope = OnDemandPolicy.Scope.WIFI) }
            addNetwork(" Home ")
            addNetwork("home")
        }
        val loaded = OnDemandSettings(store).policy.value
        assertEquals(OnDemandPolicy(true, OnDemandPolicy.Scope.WIFI, networks = listOf("Home")), loaded)
    }
}
