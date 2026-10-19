package com.skaymer.gryonixnexus.app.containers

import com.skaymer.gryonixnexus.agentcontrol.ContainerAction
import com.skaymer.gryonixnexus.agentcontrol.ContainerArchive
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupCadence
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupPlan
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupRunEvent
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupListing
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupSchedule
import com.skaymer.gryonixnexus.agentcontrol.ContainerDetail
import com.skaymer.gryonixnexus.agentcontrol.ContainerEventPhase
import com.skaymer.gryonixnexus.agentcontrol.ContainerLogLine
import com.skaymer.gryonixnexus.agentcontrol.ContainerRemovalEvent
import com.skaymer.gryonixnexus.agentcontrol.ContainerRemovalPreview
import com.skaymer.gryonixnexus.agentcontrol.ContainerUpdateEvent
import com.skaymer.gryonixnexus.agentcontrol.ContainerGroup
import com.skaymer.gryonixnexus.agentcontrol.ContainerGroupStatus
import com.skaymer.gryonixnexus.agentcontrol.ContainerInventory
import com.skaymer.gryonixnexus.agentcontrol.ContainerSummary
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** What the fleet is running, across several servers at once */
class ContainersViewModelTests {
    private fun server(id: String, usesAgent: Boolean = true) = Deployment(
        id = id,
        name = id,
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        usesAgent = usesAgent,
    )

    private fun group(key: String, status: ContainerGroupStatus = ContainerGroupStatus.RUNNING) =
        ContainerGroup(
            key = key,
            isComposeProject = true,
            displayName = key,
            derivedName = key,
            isRenamed = false,
            serviceID = null,
            status = status,
            containers = listOf(
                ContainerSummary(name = "$key-1", image = "img", state = "running", health = "", ports = "")
            ),
            configFiles = emptyList(),
        )

    private class Host(
        var groups: MutableList<ContainerGroup> = mutableListOf(),
        var unavailableReason: String? = null,
        var failWith: Exception? = null,
    ) : ContainerManaging {
        val asked = mutableListOf<String>()
        var backups = ContainerBackupListing(key = "", directory = "", archives = emptyList())

        override suspend fun inventory(): ContainerInventory {
            asked += "inventory"
            failWith?.let { throw it }
            return ContainerInventory(groups.toList(), unavailableReason)
        }

        override suspend fun rename(key: String, to: String): ContainerInventory {
            asked += "rename $key $to"
            failWith?.let { throw it }
            groups = groups.map {
                if (it.key == key) it.copy(displayName = to, isRenamed = true) else it
            }.toMutableList()
            return ContainerInventory(groups.toList(), unavailableReason)
        }

        override suspend fun control(key: String, action: ContainerAction) {
            asked += "control $key ${action.name}"
            failWith?.let { throw it }
            groups = groups.map {
                if (it.key == key) it.copy(status = ContainerGroupStatus.STOPPED) else it
            }.toMutableList()
        }

        override suspend fun inspect(container: String): ContainerDetail {
            asked += "inspect $container"
            failWith?.let { throw it }
            return ContainerDetail(
                container = ContainerSummary(container, "img", "running", "", ""),
                createdAt = "",
                restartPolicy = "",
                composeProject = "",
                composeService = "",
                command = "",
                environment = emptyList(),
                mounts = emptyList(),
            )
        }

        var updateEvents: List<ContainerUpdateEvent> = emptyList()
        var backupEvents: List<ContainerBackupRunEvent> = emptyList()
        var removalEvents: List<ContainerRemovalEvent> = emptyList()
        var trailer: Exception? = null

        var plan = ContainerBackupPlan(
            key = "stack", paths = listOf("/srv/stack"), volumes = emptyList(),
            databases = emptyList(), stopWhileArchiving = false, isDetected = true,
            notes = emptyList(),
        )
        var schedule = ContainerBackupSchedule(
            key = "stack", cadence = null, lastOutcome = "", lastRun = null,
        )
        var preview = ContainerRemovalPreview(
            containers = listOf("stack-1"), volumes = emptyList(), paths = emptyList(),
            backupPaths = emptyList(), notes = emptyList(),
        )

        private fun <T> script(events: List<T>): Flow<T> = flow {
            events.forEach { emit(it) }
            trailer?.let { throw it }
        }

        override fun logs(key: String, tail: Int): Flow<ContainerLogLine> {
            asked += "logs $key $tail"
            return script(listOf(ContainerLogLine("$key-1", "hello", "stdout")))
        }

        override suspend fun backupPlan(key: String): ContainerBackupPlan {
            asked += "plan $key"
            failWith?.let { throw it }
            return plan
        }

        override suspend fun setBackupPlan(key: String, plan: ContainerBackupPlan?): ContainerBackupPlan {
            asked += if (plan == null) "clear-plan $key" else "set-plan $key ${plan.paths.size}"
            failWith?.let { throw it }
            plan?.let { this.plan = it }
            return this.plan
        }

        override suspend fun backupSchedule(key: String): ContainerBackupSchedule {
            asked += "schedule $key"
            failWith?.let { throw it }
            return schedule
        }

        override suspend fun backups(key: String): ContainerBackupListing {
            asked += "backups $key"
            failWith?.let { throw it }
            return backups
        }

        override suspend fun setBackupSchedule(
            key: String,
            every: ContainerBackupCadence?,
        ): ContainerBackupSchedule {
            asked += "set-schedule $key ${every?.wire ?: "off"}"
            failWith?.let { throw it }
            schedule = schedule.copy(cadence = every)
            return schedule
        }

        override suspend fun removalPreview(
            key: String,
            purgeData: Boolean,
            purgeBackups: Boolean,
        ): ContainerRemovalPreview {
            asked += "preview $key data=$purgeData backups=$purgeBackups"
            failWith?.let { throw it }
            return preview
        }

        override fun runBackup(key: String): Flow<ContainerBackupRunEvent> {
            asked += "backup $key"
            return script(backupEvents)
        }

        override fun remove(key: String, purgeData: Boolean, purgeBackups: Boolean):
            Flow<ContainerRemovalEvent> {
            asked += "remove $key data=$purgeData backups=$purgeBackups"
            return script(removalEvents)
        }

        override fun update(key: String, skipBackup: Boolean): Flow<ContainerUpdateEvent> {
            asked += "update $key skipBackup=$skipBackup"
            return script(updateEvents)
        }
    }

    private fun model(hosts: Map<String, Host>, released: MutableList<String> = mutableListOf()) =
        ContainersViewModel(
            scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Unconfined),
            operations = { hosts.getValue(it.id) },
            release = { released += it.id },
        )

    @Test
    fun `one unreachable server does not blank the others`() = runTest(StandardTestDispatcher()) {
        val hosts = mapOf(
            "up" to Host(mutableListOf(group("forgejo"))),
            "down" to Host(failWith = IllegalStateException("connection refused")),
        )
        val released = mutableListOf<String>()
        val model = ContainersViewModel(
            scope = this,
            operations = { hosts.getValue(it.id) },
            release = { released += it.id },
        )
        model.load(listOf(server("up"), server("down")))
        runCurrent()
        val states = model.states.value
        assertEquals(
            listOf("forgejo"),
            (states["up"] as ServerContainers.Loaded).inventory.groups.map { it.key },
        )
        assertTrue((states["down"] as ServerContainers.Failed).message.contains("connection refused"))
        assertEquals(listOf("down"), released)
    }

    @Test
    fun `a server without an agent is told apart from one that failed`() =
        runTest(StandardTestDispatcher()) {
            val model = ContainersViewModel(scope = this, operations = { error("must not be asked") })
            model.load(listOf(server("plain", usesAgent = false)))
            runCurrent()
            assertEquals(ServerContainers.NeedsAgent, model.states.value["plain"])
        }

    @Test
    fun `a dead engine is not drawn as a tidy server`() = runTest(StandardTestDispatcher()) {
        val hosts = mapOf("h" to Host(unavailableReason = "docker is not running"))
        val model = ContainersViewModel(scope = this, operations = { hosts.getValue(it.id) })
        model.load(listOf(server("h")))
        runCurrent()
        val loaded = model.states.value["h"] as ServerContainers.Loaded
        assertEquals("docker is not running", loaded.inventory.unavailableReason)
        // And the fleet summary refuses to call it zero groups.
        assertEquals("—", model.summary("h"))
    }

    @Test
    fun `the summary counts groups only for a server that really answered`() =
        runTest(StandardTestDispatcher()) {
            val hosts = mapOf(
                "up" to Host(mutableListOf(group("a"), group("b"))),
                "down" to Host(failWith = IllegalStateException("no")),
            )
            val model = ContainersViewModel(scope = this, operations = { hosts.getValue(it.id) })
            model.load(listOf(server("up"), server("down")))
            runCurrent()
            assertEquals("2", model.summary("up"))
            assertEquals("—", model.summary("down"))
            assertEquals("—", model.summary("never-heard-of"))
        }

    @Test
    fun `a server that left the list takes its answer with it`() =
        runTest(StandardTestDispatcher()) {
            val hosts = mapOf("a" to Host(mutableListOf(group("x"))), "b" to Host(mutableListOf(group("y"))))
            val model = ContainersViewModel(scope = this, operations = { hosts.getValue(it.id) })
            model.load(listOf(server("a"), server("b")))
            runCurrent()
            assertEquals(setOf("a", "b"), model.states.value.keys)
            model.load(listOf(server("a")))
            runCurrent()
            assertEquals(setOf("a"), model.states.value.keys)
        }

    @Test
    fun `an action is followed by a re-read, not by patching the row`() =
        runTest(StandardTestDispatcher()) {
            val host = Host(mutableListOf(group("stack")))
            val model = ContainersViewModel(scope = this, operations = { host })
            model.load(listOf(server("s")))
            runCurrent()
            model.control(server("s"), "stack", ContainerAction.STOP)
            runCurrent()
            assertEquals(listOf("inventory", "control stack STOP", "inventory"), host.asked)
            val loaded = model.states.value["s"] as ServerContainers.Loaded
            assertEquals(ContainerGroupStatus.STOPPED, loaded.inventory.groups.single().status)
            assertTrue(model.busy.value.isEmpty())
        }

    @Test
    fun `a failed action leaves no group stuck busy`() = runTest(StandardTestDispatcher()) {
        val host = Host(mutableListOf(group("stack")))
        val model = ContainersViewModel(scope = this, operations = { host })
        model.load(listOf(server("s")))
        runCurrent()
        host.failWith = IllegalStateException("the agent bridge did not start")
        model.control(server("s"), "stack", ContainerAction.RESTART)
        runCurrent()
        assertTrue(model.busy.value.isEmpty())
        assertTrue((model.states.value["s"] as ServerContainers.Failed).message.contains("bridge"))
    }

    // ───────────────── the long verbs: update, backup, removal ─────────────────

    private fun updateEvent(
        phase: ContainerEventPhase,
        text: String = "",
        rolledBack: Boolean = false,
        alreadyCurrent: Boolean = false,
    ) = ContainerUpdateEvent(
        phase = phase, key = "stack", text = text, stream = "stdout",
        previousImages = emptyMap(), didRollBack = rolledBack,
        wasAlreadyCurrent = alreadyCurrent, group = null,
    )

    @Test
    fun `a failure after the completed event is still a failure`() =
        runTest(StandardTestDispatcher()) {
            val host = Host(mutableListOf(group("stack")))
            host.updateEvents = listOf(
                updateEvent(ContainerEventPhase.PROGRESS, "pulling"),
                updateEvent(ContainerEventPhase.COMPLETED),
            )
            host.trailer = IllegalStateException("the group did not come back up")
            val model = ContainersViewModel(scope = this, operations = { host })
            model.load(listOf(server("s")))
            runCurrent()
            model.start(server("s"), "stack", GroupOperationKind.UPDATE)
            runCurrent()
            val run = model.run.value!!
            assertEquals(GroupOutcome.Updated, run.outcome)
            assertTrue(run.failure!!.contains("did not come back up"))
            assertFalse(run.isRunning)
        }

    @Test
    fun `a rolled back update is neither a success nor a plain failure`() =
        runTest(StandardTestDispatcher()) {
            val host = Host(mutableListOf(group("stack")))
            host.updateEvents = listOf(
                updateEvent(ContainerEventPhase.COMPLETED, text = "the new image would not start",
                            rolledBack = true)
            )
            val model = ContainersViewModel(scope = this, operations = { host })
            model.load(listOf(server("s")))
            runCurrent()
            model.start(server("s"), "stack", GroupOperationKind.UPDATE)
            runCurrent()
            val run = model.run.value!!
            assertEquals(GroupOutcome.RolledBack("the new image would not start"), run.outcome)
            assertNull(run.failure)
        }

    @Test
    fun `an update that found nothing new says so rather than claiming work`() =
        runTest(StandardTestDispatcher()) {
            val host = Host(mutableListOf(group("stack")))
            host.updateEvents = listOf(updateEvent(ContainerEventPhase.COMPLETED, alreadyCurrent = true))
            val model = ContainersViewModel(scope = this, operations = { host })
            model.load(listOf(server("s")))
            runCurrent()
            model.start(server("s"), "stack", GroupOperationKind.UPDATE)
            runCurrent()
            assertEquals(GroupOutcome.AlreadyCurrent, model.run.value?.outcome)
        }

    @Test
    fun `the listing is re-read when a run ends, including when it failed`() =
        runTest(StandardTestDispatcher()) {
            val host = Host(mutableListOf(group("stack")))
            host.updateEvents = listOf(updateEvent(ContainerEventPhase.COMPLETED))
            host.trailer = IllegalStateException("half done")
            val model = ContainersViewModel(scope = this, operations = { host })
            model.load(listOf(server("s")))
            runCurrent()
            model.start(server("s"), "stack", GroupOperationKind.UPDATE)
            runCurrent()
            assertEquals(
                listOf("inventory", "update stack skipBackup=false", "inventory"),
                host.asked,
            )
            assertTrue(model.busy.value.isEmpty())
        }

    @Test
    fun `the refused update can be run again without a backup`() = runTest(StandardTestDispatcher()) {
        val host = Host(mutableListOf(group("stack")))
        host.trailer = IllegalStateException(
            "nothing_to_archive: this group stores nothing outside its images")
        val model = ContainersViewModel(scope = this, operations = { host })
        model.load(listOf(server("s")))
        runCurrent()
        model.start(server("s"), "stack", GroupOperationKind.UPDATE)
        runCurrent()
        assertTrue(model.run.value?.mayUpdateWithoutBackup == true, "the offer was not made")

        model.updateWithoutBackup()
        runCurrent()

        assertEquals(
            listOf("inventory", "update stack skipBackup=false", "inventory",
                   "update stack skipBackup=true", "inventory"),
            host.asked,
        )
    }

    @Test
    fun `an update refused for any other reason cannot be run without a backup`() =
        runTest(StandardTestDispatcher()) {
            val host = Host(mutableListOf(group("stack")))
            host.trailer = IllegalStateException(
                "this plan names nothing that exists on the host — nothing was archived")
            val model = ContainersViewModel(scope = this, operations = { host })
            model.load(listOf(server("s")))
            runCurrent()
            model.start(server("s"), "stack", GroupOperationKind.UPDATE)
            runCurrent()
            assertEquals(false, model.run.value?.mayUpdateWithoutBackup)

            model.updateWithoutBackup()
            runCurrent()

            assertEquals(
                listOf("inventory", "update stack skipBackup=false", "inventory"),
                host.asked,
                "a second run went out for a refusal that was never offered one",
            )
        }

    @Test
    fun `a backup names the archive it wrote`() = runTest(StandardTestDispatcher()) {
        val host = Host(mutableListOf(group("stack")))
        host.backupEvents = listOf(
            ContainerBackupRunEvent(
                phase = ContainerEventPhase.COMPLETED, key = "stack", text = "", stream = "stdout",
                plan = null,
                archive = ContainerArchive("stack-2026.tar.zst", "/opt/backups/stack-2026.tar.zst", 12, null),
                group = null,
            )
        )
        val model = ContainersViewModel(scope = this, operations = { host })
        model.load(listOf(server("s")))
        runCurrent()
        model.start(server("s"), "stack", GroupOperationKind.BACKUP)
        runCurrent()
        assertEquals(
            GroupOutcome.BackedUp("/opt/backups/stack-2026.tar.zst"),
            model.run.value?.outcome,
        )
    }

    @Test
    fun `a removal that left containers behind is not called done`() =
        runTest(StandardTestDispatcher()) {
            val host = Host(mutableListOf(group("stack")))
            host.removalEvents = listOf(
                ContainerRemovalEvent(
                    phase = ContainerEventPhase.COMPLETED, key = "stack", text = "", stream = "stdout",
                    removing = null,
                    group = group("stack"),
                )
            )
            val model = ContainersViewModel(scope = this, operations = { host })
            model.load(listOf(server("s")))
            runCurrent()
            model.start(server("s"), "stack", GroupOperationKind.REMOVE, purgeData = true)
            runCurrent()
            val outcome = model.run.value?.outcome as GroupOutcome.Removed
            assertFalse(outcome.isGone)
            assertEquals(listOf("stack-1"), outcome.survivors)
            assertTrue(host.asked.contains("remove stack data=true backups=false"))
        }

    @Test
    fun `a run in flight cannot be dismissed`() = runTest(StandardTestDispatcher()) {
        val host = Host(mutableListOf(group("stack")))
        host.removalEvents = listOf(
            ContainerRemovalEvent(
                phase = ContainerEventPhase.COMPLETED, key = "stack", text = "", stream = "stdout",
                removing = null, group = null,
            )
        )
        val model = ContainersViewModel(scope = this, operations = { host })
        model.load(listOf(server("s")))
        runCurrent()
        model.start(server("s"), "stack", GroupOperationKind.REMOVE)
        model.dismissRun()
        assertTrue(model.run.value!!.isRunning)
        assertFalse(model.run.value!!.canBeDismissed)
        runCurrent()
        model.dismissRun()
        assertNull(model.run.value)
    }

    @Test
    fun `clearing the correction is not the same as an empty plan`() =
        runTest(StandardTestDispatcher()) {
            val host = Host(mutableListOf(group("stack")))
            val model = ContainersViewModel(scope = this, operations = { host })
            model.load(listOf(server("s")))
            runCurrent()
            model.setBackupPlan(server("s"), "stack", null)
            model.setBackupPlan(
                server("s"), "stack",
                host.plan.copy(paths = emptyList(), volumes = emptyList(), isDetected = false),
            )
            assertEquals(listOf("clear-plan stack", "set-plan stack 0"), host.asked.drop(1))
        }

    @Test
    fun `a failed sheet read does not blank the server behind it`() =
        runTest(StandardTestDispatcher()) {
            val host = Host(mutableListOf(group("stack")))
            val model = ContainersViewModel(scope = this, operations = { host })
            model.load(listOf(server("s")))
            runCurrent()
            host.failWith = IllegalStateException("the agent bridge did not start")
            val answer = model.backupPlan(server("s"), "stack")
            assertTrue(answer.exceptionOrNull()!!.message!!.contains("bridge"))
            assertTrue(model.states.value["s"] is ServerContainers.Loaded)
        }
}
