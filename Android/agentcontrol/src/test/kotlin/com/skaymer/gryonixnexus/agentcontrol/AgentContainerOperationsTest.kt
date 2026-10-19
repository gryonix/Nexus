package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import gryonixnexusd.v1.ContainerDatabaseEngine
import gryonixnexusd.v1.ContainerDetail
import gryonixnexusd.v1.ContainerEnvVar
import gryonixnexusd.v1.ContainerGroupKind
import gryonixnexusd.v1.ContainerMount
import gryonixnexusd.v1.ContainerOperationEvent
import gryonixnexusd.v1.ContainerRemovalPreview
import gryonixnexusd.v1.PreviewContainerGroupRemovalRequest
import gryonixnexusd.v1.ServiceAction
import gryonixnexusd.v1.ServiceOperationPhase
import gryonixnexusd.v1.ServiceStatus
import gryonixnexusd.v1.SetContainerBackupPlanRequest
import gryonixnexusd.v1.SetContainerBackupScheduleRequest
import gryonixnexusd.v1.SetContainerGroupNameRequest
import java.time.Instant
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentContainerOperationsTests` and `ContainerDestructiveVerbTests` */
class AgentContainerOperationsTest {
    private fun ops(transport: FakeAgentTransport) = AgentContainerOperations(AgentClient(transport))

    private fun group(
        key: String,
        name: String,
        kind: ContainerGroupKind = ContainerGroupKind.CONTAINER_GROUP_KIND_COMPOSE_PROJECT,
        status: ServiceStatus = ServiceStatus.SERVICE_STATUS_RUNNING,
        serviceID: String = "",
        renamed: Boolean = false,
        derivedName: String = name,
        containers: List<gryonixnexusd.v1.Container> = emptyList(),
    ) = gryonixnexusd.v1.ContainerGroup(
        key = key,
        kind = kind,
        display_name = name,
        derived_name = derivedName,
        renamed = renamed,
        service_id = serviceID,
        status = status,
        containers = containers,
    )

    private fun inventory(vararg groups: gryonixnexusd.v1.ContainerGroup, unavailable: String = "") =
        gryonixnexusd.v1.ContainerInventory(groups = groups.toList(), unavailable_reason = unavailable)

    // --------------------------------------------------------- The listing

    @Test
    fun `an unreachable engine is not an empty machine`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Containers/ListContainers", inventory(unavailable = "docker: command not found"))

        val result = ops(transport).inventory()

        assertEquals(listOf("/gryonixnexusd.v1.Containers/ListContainers"), transport.paths)
        assertEquals(
            "docker: command not found",
            result.unavailableReason,
            "the reason has to survive, or the screen can only draw an empty list",
        )
        assertTrue(result.groups.isEmpty())
    }

    @Test
    fun `a healthy empty host reports no reason at all`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Containers/ListContainers", inventory())

        val result = ops(transport).inventory()

        assertNull(
            result.unavailableReason,
            "an empty string is the wire's way of saying nothing is wrong",
        )
        assertTrue(result.groups.isEmpty())
    }

    @Test
    fun `a stranger's stack and one of ours are told apart`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Containers/ListContainers",
            inventory(
                group(key = "mailcowdockerized", name = "mailcow", serviceID = "mailcow"),
                group(
                    key = "someone-else",
                    name = "someone-else",
                    kind = ContainerGroupKind.CONTAINER_GROUP_KIND_STANDALONE,
                    status = ServiceStatus.SERVICE_STATUS_PARTIAL,
                ),
            ),
        )

        val result = ops(transport).inventory()

        assertEquals("mailcow", result.groups.first().serviceID)
        assertTrue(result.groups.first().isComposeProject)
        assertNull(
            result.groups.last().serviceID,
            "an empty service id means a stranger, not a service called \"\"",
        )
        assertFalse(result.groups.last().isComposeProject)
        assertEquals(
            ContainerGroupStatus.PARTIAL,
            result.groups.last().status,
            "partial is the state that matters most on a stack",
        )
    }

    @Test
    fun `every status crosses over including ones we have not seen`() = runTest {
        val cases = listOf(
            ServiceStatus.SERVICE_STATUS_RUNNING to ContainerGroupStatus.RUNNING,
            ServiceStatus.SERVICE_STATUS_STOPPED to ContainerGroupStatus.STOPPED,
            ServiceStatus.SERVICE_STATUS_PARTIAL to ContainerGroupStatus.PARTIAL,
            ServiceStatus.SERVICE_STATUS_ERROR to ContainerGroupStatus.ERROR,
            ServiceStatus.SERVICE_STATUS_UNSPECIFIED to ContainerGroupStatus.UNKNOWN,
        )
        for ((wire, expected) in cases) {
            val transport = FakeAgentTransport()
            transport.reply("Containers/ListContainers", inventory(group("k", "n", status = wire)))
            assertEquals(expected, ops(transport).inventory().groups.first().status, "$wire")
        }
    }

    // ---------------------------------------------------------- Renaming

    @Test
    fun `renaming sends the key and trims the name and believes the server`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Containers/SetContainerGroupName",
            inventory(group(key = "k", name = "Owner's name", derivedName = "k", renamed = true)),
        )

        val result = ops(transport).rename("k", to = "  Owner's name \n")

        assertEquals(listOf("/gryonixnexusd.v1.Containers/SetContainerGroupName"), transport.paths)
        val sent = SetContainerGroupNameRequest.ADAPTER.decode(transport.calls.first().second)
        assertEquals("k", sent.key)
        assertEquals(
            "Owner's name",
            sent.display_name,
            "a pasted name arrives with whitespace; the server should not store it",
        )
        // The answer is the server's listing, not the request echoed back.
        assertEquals("Owner's name", result.groups.first().displayName)
        assertEquals(
            "k",
            result.groups.first().derivedName,
            "the derived name always travels, so \"back to detected\" needs no second call",
        )
        assertTrue(result.groups.first().isRenamed)
    }

    @Test
    fun `clearing a name is the same call with an empty string`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Containers/SetContainerGroupName", inventory(group("k", "k")))

        ops(transport).rename("k", to = "   ")

        assertTrue(
            SetContainerGroupNameRequest.ADAPTER.decode(transport.calls.first().second)
                .display_name.isEmpty(),
        )
    }

    // ----------------------------------------------------------- Inspect

    @Test
    fun `a read-only mount is not reported as writable`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Containers/InspectContainer",
            ContainerDetail(
                mounts = listOf(
                    ContainerMount(source = "/srv/media", destination = "/media", mode = "ro", kind = "bind"),
                    ContainerMount(
                        source = "/var/lib/docker/volumes/app_data/_data",
                        destination = "/data",
                        mode = "rw",
                        kind = "volume",
                        name = "app_data",
                    ),
                ),
            ),
        )

        val read = ops(transport).inspect("c")

        assertEquals(listOf("/gryonixnexusd.v1.Containers/InspectContainer"), transport.paths)
        assertTrue(read.mounts.first().isReadOnly, "\"ro\" is the only read-only word here")
        assertFalse(read.mounts.last().isReadOnly)
        assertEquals(
            "bind",
            read.mounts.first().kind,
            "bind vs volume decides whether the source path means anything to a reader",
        )
        // A volume is known by its NAME — `docker volume rm` takes that and
        // rejects the path, which on a live host was the difference between
        // "also delete its data" working and quietly leaving the volume behind.
        assertEquals("app_data", read.mounts.last().displaySource)
        assertEquals("/srv/media", read.mounts.first().displaySource)
    }

    /**
     * The flag is the SERVER's judgement, and losing it in translation is a
     * password on screen.
     */
    @Test
    fun `the sensitive verdict survives the crossing`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Containers/InspectContainer",
            ContainerDetail(
                env = listOf(
                    ContainerEnvVar(key = "DB_PASSWORD", value_ = "hunter2", sensitive = true),
                    ContainerEnvVar(key = "TZ", value_ = "Europe/Berlin"),
                ),
            ),
        )

        val read = ops(transport).inspect("c")

        assertTrue(
            read.environment.first().isSensitive,
            "a credential that loses its flag is a credential drawn in the open",
        )
        assertFalse(read.environment.last().isSensitive)
        assertEquals("DB_PASSWORD", read.environment.first().key)
    }

    // ------------------------------------------------------- The backup plan

    @Test
    fun `clearing a correction and archiving nothing are different requests`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Containers/SetContainerBackupPlan", gryonixnexusd.v1.ContainerBackupPlan(key = "k"))
        transport.reply("Containers/SetContainerBackupPlan", gryonixnexusd.v1.ContainerBackupPlan(key = "k"))
        val operations = ops(transport)

        operations.setBackupPlan("k", plan = null)
        operations.setBackupPlan(
            "k",
            ContainerBackupPlan(
                key = "k",
                paths = emptyList(),
                volumes = emptyList(),
                databases = emptyList(),
                stopWhileArchiving = false,
                isDetected = false,
                notes = emptyList(),
            ),
        )

        val sawPlan = transport.calls.map {
            SetContainerBackupPlanRequest.ADAPTER.decode(it.second).plan != null
        }
        assertEquals(
            listOf(false, true),
            sawPlan,
            "null must clear the correction; an empty plan must be sent as a plan",
        )
    }

    @Test
    fun `correcting a plan keeps its databases exactly`() = runTest {
        val wire = gryonixnexusd.v1.ContainerBackupPlan(
            key = "k",
            paths = listOf("/srv/app", "/srv/cache"),
            databases = listOf(
                gryonixnexusd.v1.ContainerDatabaseDump(
                    container = "app-db-1",
                    engine = ContainerDatabaseEngine.CONTAINER_DATABASE_ENGINE_POSTGRES,
                    database = "app",
                    user = "app",
                    password_env = "POSTGRES_PASSWORD",
                ),
            ),
            detected = true,
            notes = listOf("postgres image detected"),
        )

        val read = FakeAgentTransport()
        read.reply("Containers/GetContainerBackupPlan", wire)
        val plan = ops(read).backupPlan("k")

        assertEquals(listOf("/gryonixnexusd.v1.Containers/GetContainerBackupPlan"), read.paths)
        assertEquals(
            "POSTGRES_PASSWORD",
            plan.databases.first().passwordEnvName,
            "the NAME travels; the value never does",
        )
        assertEquals("postgres", plan.databases.first().engine)
        assertTrue(plan.isDetected)
        assertEquals(listOf("postgres image detected"), plan.notes)

        val write = FakeAgentTransport()
        write.reply("Containers/SetContainerBackupPlan", wire)
        ops(write).setBackupPlan(
            "k",
            plan.copy(paths = listOf("/srv/app"), isDetected = false, notes = emptyList()),
        )

        val sent = SetContainerBackupPlanRequest.ADAPTER.decode(write.calls.first().second).plan
        assertEquals(listOf("/srv/app"), sent?.paths)
        assertEquals(1, sent?.databases?.size)
        assertEquals(
            ContainerDatabaseEngine.CONTAINER_DATABASE_ENGINE_POSTGRES,
            sent?.databases?.first()?.engine,
            "the engine round-trips as the enum, not through its display name",
        )
        assertEquals("POSTGRES_PASSWORD", sent?.databases?.first()?.password_env)
    }

    @Test
    fun `a correction does not send back the server's own verdict`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Containers/SetContainerBackupPlan", gryonixnexusd.v1.ContainerBackupPlan(key = "k"))

        ops(transport).setBackupPlan(
            "k",
            ContainerBackupPlan(
                key = "k",
                paths = listOf("/a"),
                volumes = emptyList(),
                databases = emptyList(),
                stopWhileArchiving = false,
                isDetected = true,
                notes = listOf("invented by the client"),
            ),
        )

        val sent = SetContainerBackupPlanRequest.ADAPTER.decode(transport.calls.first().second).plan
        assertTrue(sent?.notes.orEmpty().isEmpty(), "notes are the agent's words about its own detection")
        assertFalse(sent?.detected ?: true)
    }

    /**
     * The key comes from the CALL, never from the plan: a plan carrying a stale
     * key would be a correction filed against another group.
     */
    @Test
    fun `the corrected plan is addressed by the call's key not the plan's`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Containers/SetContainerBackupPlan", gryonixnexusd.v1.ContainerBackupPlan(key = "right"))

        ops(transport).setBackupPlan(
            "right",
            ContainerBackupPlan(
                key = "stale-and-wrong",
                paths = listOf("/a"),
                volumes = emptyList(),
                databases = emptyList(),
                stopWhileArchiving = false,
                isDetected = false,
                notes = emptyList(),
            ),
        )

        val request = SetContainerBackupPlanRequest.ADAPTER.decode(transport.calls.first().second)
        assertEquals("right", request.key)
        assertEquals("right", request.plan?.key)
    }

    // ------------------------------------------------------------- Ports

    @Test
    fun `the published ports survive as the engine wrote them`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Containers/ListContainers",
            inventory(
                group(
                    "k",
                    "n",
                    containers = listOf(
                        gryonixnexusd.v1.Container(
                            name = "web-1",
                            ports = "0.0.0.0:8080->80/tcp, [::]:8080->80/tcp",
                        ),
                    ),
                ),
            ),
        )

        assertEquals(
            "0.0.0.0:8080->80/tcp, [::]:8080->80/tcp",
            ops(transport).inventory().groups.first().containers.first().ports,
            "kept verbatim: a parser that dropped a form docker prints is worse than the line",
        )
    }

    // ----------------------------------------------------------- Actions

    @Test
    fun `the three verbs map onto the agent's own enum rather than a second one`() {
        assertEquals(ServiceAction.SERVICE_ACTION_START, ContainerAction.START.wire)
        assertEquals(ServiceAction.SERVICE_ACTION_STOP, ContainerAction.STOP.wire)
        assertEquals(ServiceAction.SERVICE_ACTION_RESTART, ContainerAction.RESTART.wire)
    }

    // ----------------------------------------------------- The removal preview

    /**
     * **Nothing removed and everything removed must not look the same.** The
     * toggles are independent and both default to keeping; a preview that
     * dropped one of them would answer a question nobody asked, and the answer is
     * what the confirmation sheet lists.
     */
    @Test
    fun `the removal preview carries each list separately`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Containers/PreviewContainerGroupRemoval",
            ContainerRemovalPreview(
                key = "mystack",
                containers = listOf("mystack-app-1", "mystack-db-1"),
                volumes = listOf("mystack_db"),
                paths = listOf("/opt/mystack/data"),
                backup_paths = listOf("/opt/backups/containers/mystack"),
                notes = listOf("/etc is left alone: it is a system directory"),
            ),
        )

        val preview = ops(transport).removalPreview("mystack", purgeData = true, purgeBackups = true)

        val sent = PreviewContainerGroupRemovalRequest.ADAPTER.decode(transport.calls.first().second)
        assertEquals("mystack", sent.key)
        assertTrue(sent.purge_data)
        assertTrue(sent.purge_backups)

        assertEquals(listOf("mystack-app-1", "mystack-db-1"), preview.containers)
        assertEquals(listOf("mystack_db"), preview.volumes)
        assertEquals(listOf("/opt/mystack/data"), preview.paths)
        assertEquals(listOf("/opt/backups/containers/mystack"), preview.backupPaths)
        // A path the server refused to touch is NAMED rather than dropped: a path
        // silently skipped is a removal that half happened and reported that it
        // finished.
        assertEquals(1, preview.notes.size)
        assertFalse(preview.isEmpty)
    }

    // ---------------------------------------------------------- Schedules

    /**
     * A group scheduled and a group never scheduled are different answers, and
     * "never" must not read as "daily".
     */
    @Test
    fun `a schedule that is off is not a schedule at all`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Containers/GetContainerBackupSchedule",
            gryonixnexusd.v1.ContainerBackupSchedule(key = "mystack", schedule = "", enabled = false),
        )

        val schedule = ops(transport).backupSchedule("mystack")

        assertNull(schedule.cadence)
        assertFalse(schedule.isEnabled)
        assertNull(schedule.lastRun)
    }

    @Test
    fun `each cadence survives the crossing`() = runTest {
        for (cadence in ContainerBackupCadence.entries) {
            val transport = FakeAgentTransport()
            transport.reply(
                "Containers/GetContainerBackupSchedule",
                gryonixnexusd.v1.ContainerBackupSchedule(
                    key = "mystack",
                    schedule = cadence.wire,
                    enabled = true,
                    last_outcome = "ok /opt/backups/containers/mystack/x.tar.gz",
                    last_run = "1750000000",
                ),
            )

            val schedule = ops(transport).backupSchedule("mystack")

            assertEquals(cadence, schedule.cadence)
            assertTrue(schedule.isEnabled)
            // SECONDS as a string here, unlike the archive's milliseconds — and
            // either unit read as the other still yields a plausible date.
            assertEquals(Instant.ofEpochSecond(1_750_000_000), schedule.lastRun)
        }
    }

    /**
     * A cadence this build does not know must not silently become a working one
     * — an older server could name anything.
     */
    @Test
    fun `an unknown cadence reads as off rather than as something else`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Containers/GetContainerBackupSchedule",
            gryonixnexusd.v1.ContainerBackupSchedule(key = "mystack", schedule = "fortnightly", enabled = true),
        )

        assertNull(ops(transport).backupSchedule("mystack").cadence)
    }

    /**
     * Switching a schedule off sends an EMPTY string — the same "empty clears it"
     * verb the name and the plan already use. A second verb for clearing is a
     * second thing to keep in step.
     */
    @Test
    fun `switching a schedule off is the same call with an empty string`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Containers/SetContainerBackupSchedule", gryonixnexusd.v1.ContainerBackupSchedule(key = "mystack"))
        transport.reply("Containers/SetContainerBackupSchedule", gryonixnexusd.v1.ContainerBackupSchedule(key = "mystack"))
        val operations = ops(transport)

        operations.setBackupSchedule("mystack", every = null)
        assertEquals(
            "",
            SetContainerBackupScheduleRequest.ADAPTER.decode(transport.calls.first().second).schedule,
        )

        operations.setBackupSchedule("mystack", every = ContainerBackupCadence.WEEKLY)
        assertEquals(
            "weekly",
            SetContainerBackupScheduleRequest.ADAPTER.decode(transport.calls.last().second).schedule,
        )
    }

    // ------------------------------------------------------------- Streams

    /**
     * Not in the Swift twin, which tests no stream here at all — and the streamed
     * verbs are where the same mistranslation risk sits: four events, one phase
     * mapping, and three optional messages whose PRESENCE is the answer. A group
     * that arrives as absent when it was sent is "the stack is gone" instead of
     * "the stack survived", which is the opposite conclusion.
     */
    @Test
    fun `a control run carries its phases and the re-read group`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream(
            "Containers/ControlContainerGroup",
            ContainerOperationEvent(
                phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_STARTED,
                key = "mystack",
                containers = listOf("mystack-app-1"),
            ),
            ContainerOperationEvent(
                phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS,
                key = "mystack",
                text = "Stopping mystack-app-1",
            ),
            ContainerOperationEvent(
                phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                key = "mystack",
                group = group("mystack", "mystack", status = ServiceStatus.SERVICE_STATUS_STOPPED),
            ),
        )

        val events = ops(transport).control("mystack", ContainerAction.STOP).toList()

        assertEquals(listOf("/gryonixnexusd.v1.Containers/ControlContainerGroup"), transport.paths)
        assertEquals(
            listOf(
                ContainerEventPhase.STARTED,
                ContainerEventPhase.PROGRESS,
                ContainerEventPhase.COMPLETED,
            ),
            events.map { it.phase },
        )
        assertEquals(listOf("mystack-app-1"), events.first().containers)
        // STARTED names what is about to be touched and carries no group; only
        // COMPLETED does. Reading either the wrong way round is a screen that
        // reports a state before anything happened.
        assertNull(events.first().group)
        assertEquals(ContainerGroupStatus.STOPPED, events.last().group?.status)
    }

    /**
     * **Absent means the group is gone**, which is the successful outcome;
     * present means containers survived, and that is what a half-finished removal
     * looks like. The two are one nullable field apart.
     */
    @Test
    fun `a finished removal answers with no group and a half-finished one with the survivors`() = runTest {
        val gone = FakeAgentTransport()
        gone.stream(
            "Containers/RemoveContainerGroup",
            gryonixnexusd.v1.ContainerRemovalEvent(
                phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_STARTED,
                key = "mystack",
                removing = ContainerRemovalPreview(key = "mystack", containers = listOf("mystack-app-1")),
            ),
            gryonixnexusd.v1.ContainerRemovalEvent(
                phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                key = "mystack",
            ),
        )

        val finished = ops(gone).remove("mystack", purgeData = true, purgeBackups = false).toList()
        assertEquals(listOf("mystack-app-1"), finished.first().removing?.containers)
        assertNull(finished.last().group, "no group at COMPLETED is what success looks like")

        val survived = FakeAgentTransport()
        survived.stream(
            "Containers/RemoveContainerGroup",
            gryonixnexusd.v1.ContainerRemovalEvent(
                phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                key = "mystack",
                group = group("mystack", "mystack", status = ServiceStatus.SERVICE_STATUS_PARTIAL),
            ),
        )

        val halfway = ops(survived).remove("mystack", purgeData = true, purgeBackups = false).toList()
        assertEquals(ContainerGroupStatus.PARTIAL, halfway.last().group?.status)
    }

    /**
     * The previous-image map is the only thing that makes a rollback possible —
     * `docker pull` moves the tag, so after it there is nobody left to ask what
     * was running. It travels on STARTED, and an empty one is not the same
     * answer as a missing one.
     */
    @Test
    fun `an update carries what was running before the pull and how it ended`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream(
            "Containers/UpdateContainerGroup",
            gryonixnexusd.v1.ContainerUpdateEvent(
                phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_STARTED,
                key = "mystack",
                previous_images = mapOf("nginx:latest" to "sha256:aaa"),
            ),
            gryonixnexusd.v1.ContainerUpdateEvent(
                phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                key = "mystack",
                rolled_back = true,
                already_current = false,
                group = group("mystack", "mystack"),
            ),
        )

        val events = ops(transport).update("mystack", skipBackup = true).toList()

        assertEquals(mapOf("nginx:latest" to "sha256:aaa"), events.first().previousImages)
        assertTrue(events.last().didRollBack)
        assertFalse(events.last().wasAlreadyCurrent)
        assertEquals("mystack", events.last().group?.key)
    }

    /**
     * A backup run's COMPLETED is sent even on FAILURE and before the error,
     * because a backup that stopped a stack and then failed leaves "is it running
     * again?" as the first question. The archive is the half that is absent when
     * nothing was written.
     */
    @Test
    fun `a backup run carries its plan its archive and the group afterwards`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream(
            "Containers/RunContainerGroupBackup",
            gryonixnexusd.v1.ContainerBackupEvent(
                phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_STARTED,
                key = "mystack",
                plan = gryonixnexusd.v1.ContainerBackupPlan(key = "mystack", paths = listOf("/opt/mystack")),
            ),
            gryonixnexusd.v1.ContainerBackupEvent(
                phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                key = "mystack",
                archive = gryonixnexusd.v1.BackupArchive(
                    name = "mystack-20260826.tar.gz",
                    path = "/opt/backups/containers/mystack/mystack-20260826.tar.gz",
                    size_bytes = 4096,
                    modified_at = 1_754_400_000_000,
                ),
                group = group("mystack", "mystack"),
            ),
        )

        val events = ops(transport).runBackup("mystack").toList()

        assertEquals(listOf("/opt/mystack"), events.first().plan?.paths)
        assertNull(events.first().archive)
        assertEquals("mystack-20260826.tar.gz", events.last().archive?.name)
        assertEquals(4096, events.last().archive?.sizeBytes)
        // MILLISECONDS on this field, unlike the schedule's seconds.
        assertEquals(Instant.ofEpochMilli(1_754_400_000_000), events.last().archive?.modifiedAt)
        assertEquals("mystack", events.last().group?.key)
    }

    /** A run that wrote nothing says so with an absent archive, not a zero one. */
    @Test
    fun `an archive that was never written is absent rather than empty`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream(
            "Containers/RunContainerGroupBackup",
            gryonixnexusd.v1.ContainerBackupEvent(
                phase = ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED,
                key = "mystack",
                group = group("mystack", "mystack"),
            ),
        )

        assertNull(ops(transport).runBackup("mystack").toList().last().archive)
    }

    /**
     * A stack's log is several logs, and an untagged merge of them is
     * unreadable — so each line names the container it came from and which pipe
     * it arrived on.
     */
    @Test
    fun `each log line keeps its container and its stream`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream(
            "Containers/ContainerGroupLogs",
            gryonixnexusd.v1.LogLine(container = "mystack-app-1", text = "listening on 8080", stream = "stdout"),
            gryonixnexusd.v1.LogLine(container = "mystack-db-1", text = "FATAL: no pg_hba entry", stream = "stderr"),
        )

        val lines = ops(transport).logs("mystack", tail = 100).toList()

        assertEquals(listOf("mystack-app-1", "mystack-db-1"), lines.map { it.container })
        assertEquals(listOf("stdout", "stderr"), lines.map { it.stream })
        assertEquals("FATAL: no pg_hba entry", lines.last().text)
    }

    // ------------------------------------------- A foreign group's backups

    /**
     * **The listing that did not exist.** Runs have been writing these archives
     * since container backups landed and no verb returned them, so the app
     * could start a backup for a stranger's stack and then never show it.
     * `backups(serviceID)` cannot stand in: it resolves a CATALOG id through
     * the wrapper the installer generated, and a foreign group has neither.
     */
    @Test
    fun `a foreign group's archives come back with the directory the agent resolved`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Containers/ListContainerGroupBackups",
            gryonixnexusd.v1.ContainerBackupList(
                key = "acme-stack",
                directory = "/opt/backups/containers/acme-stack",
                archives = listOf(
                    gryonixnexusd.v1.BackupArchive(
                        name = "newer.tar.gz",
                        path = "/opt/backups/containers/acme-stack/newer.tar.gz",
                        size_bytes = 2048,
                        modified_at = 1_700_000_000_000,
                    ),
                    gryonixnexusd.v1.BackupArchive(name = "older.tar.gz"),
                ),
            ),
        )

        val listing = ops(transport).backups("acme-stack")

        // **The path is the AGENT's.** A client that built it would be a second
        // implementation of something only one side owns.
        assertEquals("/opt/backups/containers/acme-stack", listing.directory)
        assertEquals(listOf("newer.tar.gz", "older.tar.gz"), listing.archives.map { it.name })
        assertEquals(2048L, listing.archives.first().sizeBytes)
        assertNotNull(listing.archives.first().modifiedAt)
    }

    /**
     * A group nobody has backed up yet is an empty list AND a directory: the
     * screen needs the path to say where they would go, and an empty list is
     * the ordinary state of every stranger's stack.
     */
    @Test
    fun `a group with no backups answers empty and still names the directory`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Containers/ListContainerGroupBackups",
            gryonixnexusd.v1.ContainerBackupList(
                key = "fresh",
                directory = "/opt/backups/containers/fresh",
            ),
        )

        val listing = ops(transport).backups("fresh")

        assertTrue(listing.archives.isEmpty())
        assertEquals("/opt/backups/containers/fresh", listing.directory)
    }

    /**
     * An archive the agent could not date comes back WITHOUT a date rather than
     * with the epoch — "1 January 1970" beside a real backup is a screen
     * inventing a fact.
     */
    @Test
    fun `an archive with no time has no date`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply(
            "Containers/ListContainerGroupBackups",
            gryonixnexusd.v1.ContainerBackupList(
                archives = listOf(gryonixnexusd.v1.BackupArchive(name = "undated.tar.gz")),
            ),
        )

        assertNull(ops(transport).backups("acme-stack").archives.first().modifiedAt)
    }
}
