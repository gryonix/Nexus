package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.R
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class RefusalAdviceTests {
    private val advised = listOf(
        "install.machine_not_at_home", "install.incompatible", "install.hub_has_player", "install.player_in_hub",
        "install.needs_home_assistant", "install.no_reverse_proxy", "install.zigbee_no_stick", "install.stick_missing",
        "install.site_name_taken", "install.already_running", "install.ports_in_use", "install.docker_unavailable",
        "host.docker_unavailable", "security.not_installed", "mesh.not_installed", "models.no_engine",
        "audio.hub_not_installed", "host.needs_repair", "vpn.no_panel", "vpn.protocol_not_installed",
        "vpn.panel_not_running", "vpn.login_refused", "jobs.cannot_stop", "containers.backup_required",
        "containers.nothing_to_archive", "sites.caddy_refused", "audio.hub_not_answering", "firewall.rules_refused",
        "move.no_space", "backup.unreadable", "security.ssh_unchanged",
    )

    @Test
    fun `every reason the app knows has advice`() {
        for (reason in advised) assertNotNull(refusalAdviceText(reason), reason)
    }

    @Test
    fun `a reason without advice shows only the agent's text`() {
        for (reason in listOf("move.refused", "mcp.change_failed", "history.unreadable", "", "no.such_reason")) {
            assertNull(refusalAdviceText(reason), reason)
        }
    }

    @Test
    fun `Docker not answering reads the same from an install and from a running server`() {
        assertEquals(refusalAdviceText("install.docker_unavailable"), refusalAdviceText("host.docker_unavailable"))
        assertEquals(R.string.refusal_docker_unavailable, refusalAdviceText("host.docker_unavailable"))
    }

    @Test
    fun `advice that points at a screen or a name has one to fill in`() {
        val repair = RefusalAdviceValue.Screen(R.string.repair_server)
        for (reason in listOf("host.docker_unavailable", "host.needs_repair", "firewall.rules_refused")) {
            assertEquals(repair, refusalAdviceValue(reason), reason)
        }
        assertEquals(RefusalAdviceValue.Words("CrowdSec"), refusalAdviceValue("security.not_installed"))
        assertEquals(RefusalAdviceValue.FirstArgument, refusalAdviceValue("install.hub_has_player"))
        assertNull(refusalAdviceValue("sites.caddy_refused"))
    }
}
