package com.skaymer.gryonixnexus.app.notify

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class AlertCardTests {
    @Test
    fun `every problem kind has a card with advice`() {
        for (kind in listOf("raid", "smart", "space", "backup", "drive_stale", "drive_readonly", "load", "memory")) {
            val card = assertNotNull(AlertCard.from("gnx.alert.$kind", "Title", "Body"), kind)
            assertNotNull(card.advice, kind)
        }
    }

    @Test
    fun `the card keeps the alert's own words`() {
        val card = AlertCard.from("gnx.alert.space", "Disk almost full on orion", null)
        assertEquals(AlertCard("Disk almost full on orion", "", "gnx.alert.space"), card)
    }

    @Test
    fun `recoveries, sign-ins, runs and services get no card`() {
        val kinds = listOf(
            "gnx.alert.space.ok", "gnx.alert.ssh_login", "gnx.alert.agent_update", "gnx.alert.test",
            "gnx.alert.operation.failed", "gnx.alert.service", "",
        )
        for (kind in kinds) assertNull(AlertCard.from(kind, "Title", "Body"), kind)
    }

    @Test
    fun `an alert without a title gets no card`() {
        assertNull(AlertCard.from("gnx.alert.space", null, "Body"))
        assertNull(AlertCard.from("gnx.alert.space", "", "Body"))
    }

    @Test
    fun `advice that names a screen has one to name`() {
        assertNotNull(AlertCard("t", "", "gnx.alert.raid").screen)
        assertNotNull(AlertCard("t", "", "gnx.alert.backup").screen)
        assertNull(AlertCard("t", "", "gnx.alert.space").screen)
    }

    @Test
    fun `the kind is read from the alert's data`() {
        val gnx = kotlinx.serialization.json.buildJsonObject {
            put("kind", kotlinx.serialization.json.JsonPrimitive("gnx.alert.space"))
        }
        assertEquals("gnx.alert.space", AlertDestination.kind(gnx))
        assertEquals("", AlertDestination.kind(null))
    }

    @Test
    fun `a card asked for a server is handed over once`() {
        val navigator = com.skaymer.gryonixnexus.app.shell.AppNavigator()
        val card = AlertCard("Disk almost full", "", "gnx.alert.space")
        navigator.open("S-1", com.skaymer.gryonixnexus.app.shell.ServerSection.GENERAL, service = "vaultwarden", card = card)
        assertNull(navigator.takeAlert("S-2"))
        assertEquals(card, navigator.takeAlert("S-1"))
        assertNull(navigator.takeAlert("S-1"))
        assertNull(navigator.takeService("S-1"), "a card opens instead of the service log")
    }
}
