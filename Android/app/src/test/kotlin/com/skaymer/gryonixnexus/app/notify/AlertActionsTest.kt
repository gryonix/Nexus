package com.skaymer.gryonixnexus.app.notify

import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class AlertActionsTest {
    private val login = """{"server_id":"srv","kind":"gnx.alert.ssh_login","args":["gvps","root","1.2.3.4 by key"],"address":"1.2.3.4"}"""

    @Test
    fun blockReadsTheAddressAndTheMachineName() {
        val action = AlertAction.from(AlertAction.Verb.BLOCK, AlertAction.data(login)!!)
        assertEquals(AlertAction(AlertAction.Verb.BLOCK, "srv", "gvps", "1.2.3.4"), action)
    }

    @Test
    fun restartReadsTheContainerFromTheArguments() {
        val data = AlertAction.data("""{"server_id":"srv","args":["orion","vaultwarden","unhealthy"]}""")!!
        assertEquals("vaultwarden", AlertAction.from(AlertAction.Verb.RESTART, data)?.target)
    }

    @Test
    fun anAlertWithoutATargetOffersNothingToDo() {
        val data = AlertAction.data("""{"server_id":"srv","args":["gvps"]}""")!!
        assertNull(AlertAction.from(AlertAction.Verb.BLOCK, data))
        assertNull(AlertAction.from(AlertAction.Verb.RESTART, data))
        assertNull(AlertAction.data("not json"))
    }

    @Test
    fun onlySignInsAndServicesCarryButtons() {
        assertEquals(listOf(AlertAction.Verb.BLOCK), AlertAction.verbs("gnx.alert.ssh_login"))
        assertEquals(listOf(AlertAction.Verb.RESTART), AlertAction.verbs("gnx.alert.service"))
        assertEquals(emptyList(), AlertAction.verbs("gnx.alert.service.ok"))
    }

    @Test
    fun aRelayIdRemembersTheMachine() {
        val store = InMemorySettingsStore()
        RelayServers.remember(store, "a", "d1", SSHHostID.HOME)
        RelayServers.remember(store, "b", "d1", SSHHostID.node("n1"))
        assertEquals("d1" to SSHHostID.HOME, RelayServers.target(store, "a"))
        assertEquals("d1" to SSHHostID.node("n1"), RelayServers.target(store, "b"))
        assertNull(RelayServers.target(store, "c"))
    }

    @Test
    fun aRelayIdNoServerKnowsIsSaidPlainly() = runBlocking {
        val runner = AlertActionRunner(InMemorySettingsStore(), { emptyList() }, { _, _ -> error("not reached") })
        val action = AlertAction(AlertAction.Verb.BLOCK, "srv", "gvps", "1.2.3.4")
        assertEquals(AlertOutcome.UnknownServer, runner.run(action))
    }
}
