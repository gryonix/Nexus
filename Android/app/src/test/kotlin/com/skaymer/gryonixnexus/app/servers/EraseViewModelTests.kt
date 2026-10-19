package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.CommandMarkers
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.PurgeOptions
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.UninstallOperations
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class EraseViewModelTests {
    private val server = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
    )

    private val vps = SSHHostID(SSHHostID.Kind.Slot(DeploymentNode.LegacySlot.VPS))
    private val home = SSHHostID(SSHHostID.Kind.Slot(DeploymentNode.LegacySlot.HOME))

    /** A cleanup that plays a script */
    private class Scripted(
        private val events: List<UninstallOperations.Event>,
        private val failAfter: Int? = null,
    ) : HostCleanup {
        var purge: PurgeOptions? = null

        override suspend fun fullCleanup(
            purge: PurgeOptions,
            onEvent: (UninstallOperations.Event) -> Unit,
        ) {
            this.purge = purge
            events.forEachIndexed { index, event ->
                if (failAfter != null && index == failAfter) error("the wrapper never said it was done")
                onEvent(event)
            }
            if (failAfter != null && failAfter >= events.size) {
                error("the wrapper never said it was done")
            }
        }
    }

    private fun model(
        scope: CoroutineScope,
        cleanup: HostCleanup,
        released: MutableList<String> = mutableListOf(),
    ) = EraseViewModel(
        scope = scope,
        cleanups = { cleanup },
        release = { released += it.id },
    )

    @Test
    fun `every machine reporting clean is what makes the card droppable`() =
        runTest(StandardTestDispatcher()) {
            val cleanup = Scripted(
                listOf(
                    UninstallOperations.Event.HostStarted(home),
                    UninstallOperations.Event.Output("home: containers removed\n"),
                    UninstallOperations.Event.HostFinished(home),
                    UninstallOperations.Event.HostStarted(vps),
                    UninstallOperations.Event.HostFinished(vps),
                )
            )
            val model = model(CoroutineScope(coroutineContext), cleanup)

            model.erase(server, PurgeOptions(data = true, backups = false))
            runCurrent()

            val run = assertNotNull(model.run.value)
            assertTrue(run.isFinished)
            assertTrue(run.erased, "no card would be dropped after a clean run")
            assertNull(run.errorMessage)
            assertEquals(listOf(home, vps), run.finished)
            assertNull(run.host, "a machine is still shown as being cleaned")
            // The toggles reach the wrapper, not just the warning sentence.
            assertEquals(PurgeOptions(data = true, backups = false), cleanup.purge)
        }

    /** The expensive half */
    @Test
    fun `a cleanup that fails part-way keeps the server`() = runTest(StandardTestDispatcher()) {
        val released = mutableListOf<String>()
        val cleanup = Scripted(
            listOf(
                UninstallOperations.Event.HostStarted(home),
                UninstallOperations.Event.HostFinished(home),
                UninstallOperations.Event.HostStarted(vps),
            ),
            failAfter = 3,
        )
        val model = model(CoroutineScope(coroutineContext), cleanup, released)

        model.erase(server, PurgeOptions.NONE)
        runCurrent()

        val run = assertNotNull(model.run.value)
        assertTrue(run.isFinished)
        assertFalse(run.erased, "a half-erased server lost its card")
        assertEquals("the wrapper never said it was done", run.errorMessage)
        assertEquals(listOf(home), run.finished)
        assertEquals(listOf("S-1"), released, "a failed run kept the session")
    }

    @Test
    fun `the log a person reads carries no protocol markers`() = runTest(StandardTestDispatcher()) {
        val cleanup = Scripted(
            listOf(
                UninstallOperations.Event.HostStarted(vps),
                UninstallOperations.Event.Output(
                    "Stopping nextcloud\n${CommandMarkers.Uninstall.DONE}\n"
                ),
                UninstallOperations.Event.HostFinished(vps),
            )
        )
        val model = model(CoroutineScope(coroutineContext), cleanup)

        model.erase(server, PurgeOptions.NONE)
        runCurrent()

        val log = assertNotNull(model.run.value).log
        assertTrue("Stopping nextcloud" in log, "the wrapper's own output was dropped: $log")
        assertFalse(CommandMarkers.Uninstall.DONE in log, "the wiring is on screen: $log")
    }

    @Test
    fun `a second erase while one is running is ignored`() = runTest(StandardTestDispatcher()) {
        val first = Scripted(listOf(UninstallOperations.Event.HostStarted(vps)))
        val model = EraseViewModel(
            scope = CoroutineScope(coroutineContext),
            cleanups = { first },
        )

        model.erase(server, PurgeOptions.NONE)
        model.erase(server, PurgeOptions(data = true, backups = true))
        runCurrent()

        assertEquals(PurgeOptions.NONE, first.purge, "the second order reached the wrapper")
    }

    @Test
    fun `a running erase cannot be dismissed`() = runTest(StandardTestDispatcher()) {
        val model = EraseViewModel(
            scope = CoroutineScope(coroutineContext),
            cleanups = {
                HostCleanup { _, onEvent -> onEvent(UninstallOperations.Event.HostStarted(vps)) }
            },
        )

        model.erase(server, PurgeOptions.NONE)
        model.clear()
        assertNotNull(model.run.value, "the log went away while the host was still being cleaned")
    }

    /** The sentence and the flags come from one place */
    @Test
    fun `each pair of toggles has its own warning`() {
        assertEquals(EraseWarning.NOTHING_DELETED, EraseViewModel.warning(PurgeOptions.NONE))
        assertEquals(EraseWarning.DATA, EraseViewModel.warning(PurgeOptions(data = true)))
        assertEquals(EraseWarning.BACKUPS, EraseViewModel.warning(PurgeOptions(backups = true)))
        assertEquals(
            EraseWarning.DATA_AND_BACKUPS,
            EraseViewModel.warning(PurgeOptions(data = true, backups = true)),
        )
    }
}
