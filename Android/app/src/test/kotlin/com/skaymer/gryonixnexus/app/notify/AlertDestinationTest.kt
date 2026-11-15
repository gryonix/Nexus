package com.skaymer.gryonixnexus.app.notify

import com.skaymer.gryonixnexus.app.shell.ServerSection
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class AlertDestinationTest {
    private fun destination(kind: String, server: String = "srv") =
        AlertDestination.from(AlertAction.data("""{"server_id":"$server","kind":"$kind"}""")) {
            if (it == "srv") "deployment-1" else null
        }

    @Test
    fun aServiceOrBackupAlertOpensApps() {
        assertEquals(AlertDestination("deployment-1", ServerSection.APPS), destination("gnx.alert.service"))
        assertEquals(ServerSection.APPS, destination("gnx.alert.service.ok")?.section)
        assertEquals(ServerSection.APPS, destination("gnx.alert.backup")?.section)
        assertEquals(ServerSection.APPS, destination("gnx.alert.drive_readonly")?.section)
    }

    @Test
    fun diskAgentAndSignInAlertsOpenGeneral() {
        listOf("gnx.alert.raid", "gnx.alert.smart", "gnx.alert.space", "gnx.alert.agent_update", "gnx.alert.ssh_login")
            .forEach { assertEquals(ServerSection.GENERAL, destination(it)?.section, it) }
    }

    @Test
    fun anUnknownServerOpensNothing() {
        assertNull(destination("gnx.alert.service", server = "gone"))
        assertNull(AlertDestination.from(AlertAction.data("""{"kind":"gnx.alert.service"}""")) { "x" })
    }
}
