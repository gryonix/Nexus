package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore
import com.skaymer.gryonixnexus.profile.ProxyTunnelText
import com.skaymer.gryonixnexus.profile.advanced.RuleAction
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class AdvancedVpnStoreTests {
    private val link = "trojan://secret@a.example.net:443?sni=a.example.net#A"

    private fun store(secrets: InMemorySecretStore = InMemorySecretStore()) =
        AdvancedVpnStore(secrets, File(System.getProperty("java.io.tmpdir")))

    @Test
    fun importedServersAndChoicesSurviveReload() {
        val secrets = InMemorySecretStore()
        val first = store(secrets)
        first.importText(link)
        first.update { it.copy(finalAction = RuleAction.DIRECT) }
        val again = store(secrets).profile.value
        assertEquals(1, again.servers.size)
        assertEquals(RuleAction.DIRECT, again.finalAction)
    }

    @Test
    fun tunnelTextCarriesTheProfile() {
        val store = store()
        assertNull(store.tunnelText())
        store.importText(link)
        val text = assertNotNull(store.tunnelText())
        assertNotNull(ProxyTunnelText.advancedJson(text))
        assertEquals("advanced", ProxyTunnelText.split(text).first)
    }

    @Test
    fun onlyHttpsAddressesAreFetched() {
        assertTrue(AdvancedVpnStore.isFetchable("https://example.net/list"))
        assertFalse(AdvancedVpnStore.isFetchable("http://example.net/list"))
        assertFalse(AdvancedVpnStore.isFetchable("not a url"))
    }

    @Test
    fun refreshIsDueAfterADay() {
        assertTrue(AdvancedVpnStore.isDue(null))
        assertFalse(AdvancedVpnStore.isDue(1_000, now = 2_000))
        assertTrue(AdvancedVpnStore.isDue(0, now = AdvancedVpnStore.REFRESH_MILLIS))
    }
}
