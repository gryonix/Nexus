package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.agentcontrol.ContainerGroup
import com.skaymer.gryonixnexus.agentcontrol.ContainerGroupStatus
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.servercontrol.AudioHubState
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class PendingSettingsTests {
    private val hub = AudioHubState(
        outputs = listOf(
            AudioHubState.Output("hdmi", "HDMI", 0.5, false, true),
            AudioHubState.Output("usb", "USB", 0.5, false, false),
        ),
        services = listOf(AudioHubState.Service("mpd.service", "Music Player Daemon", false)),
        bluetoothPowered = false,
    )

    @Test
    fun `hub settings equal to the hub make no calls`() {
        val draft = AudioHubDraft(output = "hdmi", players = mapOf("mpd.service" to false), bluetooth = false)
        assertTrue(draft.calls(hub).isEmpty())
        assertTrue(AudioHubDraft().calls(hub).isEmpty())
    }

    @Test
    fun `hub settings that differ become calls, in a fixed order`() {
        val draft = AudioHubDraft(
            output = "usb",
            players = mapOf("mpd.service" to true, "gone.service" to true),
            bluetooth = true,
        )
        assertEquals(
            listOf("/audio/outputs/usb/default", "/services/user/mpd.service/start", "/bluetooth/power_up"),
            draft.calls(hub),
        )
        assertEquals(listOf("/bluetooth/power_down"), AudioHubDraft(bluetooth = false).calls(hub.copy(bluetoothPowered = true)))
    }

    private fun group(renamed: Boolean, serviceID: String?) = ContainerGroup(
        key = "k",
        isComposeProject = true,
        displayName = if (renamed) "Mine" else "Vaultwarden",
        derivedName = "Vaultwarden",
        isRenamed = renamed,
        serviceID = serviceID,
        status = ContainerGroupStatus.RUNNING,
        containers = emptyList(),
        configFiles = emptyList(),
    )

    @Test
    fun `a container group takes the service's given name unless it has its own`() {
        val given: (ManagedService) -> String = { if (it.id.rawValue == "vaultwarden") "Passwords" else it.displayName }
        val plain: (ManagedService) -> String = { it.displayName }
        assertEquals("Passwords", groupTitle(group(renamed = false, serviceID = "vaultwarden"), given))
        assertEquals("Mine", groupTitle(group(renamed = true, serviceID = "vaultwarden"), given))
        assertEquals("Vaultwarden", groupTitle(group(renamed = false, serviceID = null), given))
        assertEquals("Vaultwarden", groupTitle(group(renamed = false, serviceID = "vaultwarden"), plain))
    }
}
