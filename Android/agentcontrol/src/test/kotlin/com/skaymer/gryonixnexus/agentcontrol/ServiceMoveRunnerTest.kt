package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.ServiceMoveRecord
import com.skaymer.gryonixnexus.servercontrol.ServiceMoveStep
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

private class Tape {
    val lines = mutableListOf<String>()
}

private class FakeMachine(val name: String, val tape: Tape, var has: Boolean = false) : ServiceMoveMachine {
    val failing = mutableSetOf<String>()
    var site: ServiceMoveSite = ServiceMoveSite.Local
    var probeAnswer = ServiceMoveProbe(answered = true, unavailable = false, status = 200, detail = "")
    val changes = mutableListOf<ServiceMoveSiteChange>()

    private fun call(what: String) {
        tape.lines += "$name.$what"
        if (what in failing) throw IllegalStateException("$name $what failed")
    }

    override suspend fun hasService(service: ServiceID): Boolean { call("has"); return has }
    override suspend fun estimatedBytes(service: ServiceID): Long { call("estimate"); return 1000 }
    override suspend fun install(service: ServiceID, context: AgentInstallContext, log: (String) -> Unit) = call("install")
    override suspend fun backUp(service: ServiceID, log: (String) -> Unit): ServiceMoveArchive {
        call("backup")
        return ServiceMoveArchive("/b/a.tar.gz", "a.tar.gz", 500)
    }
    override suspend fun start(service: ServiceID, log: (String) -> Unit) = call("start")
    override suspend fun stop(service: ServiceID, log: (String) -> Unit) = call("stop")
    override suspend fun restore(service: ServiceID, archivePath: String, log: (String) -> Unit) = call("restore:$archivePath")
    override suspend fun removeCopy(service: ServiceID, log: (String) -> Unit) = call("removeCopy")
    override suspend fun deleteBackup(service: ServiceID, path: String) = call("deleteBackup:$path")
    override suspend fun prepareSend(transferID: String): String { call("prepareSend"); return "ssh-ed25519 KEY" }
    override suspend fun prepareReceive(transferID: String, service: ServiceID, publicKey: String, expectedBytes: Long): ServiceMoveGrant {
        call("prepareReceive:$publicKey:$expectedBytes")
        return ServiceMoveGrant("LINE", "ssh-ed25519 HOST", 9)
    }
    override suspend fun authorize(grant: ServiceMoveGrant) = call("authorize:${grant.authorizedKeyLine}")
    override suspend fun revoke(transferID: String) = call("revoke")
    override suspend fun send(
        transferID: String, service: ServiceID, archivePath: String, target: ServiceMoveEndpoint,
        hostKeys: String, log: (String) -> Unit,
    ): ServiceMoveSent {
        call("send:$archivePath->${target.host}:$hostKeys")
        return ServiceMoveSent(520, "abc", "a.tar.gz")
    }
    override suspend fun accept(transferID: String, service: ServiceID, sent: ServiceMoveSent, log: (String) -> Unit): String {
        call("accept:${sent.sha256}:${sent.bytes}")
        return "/new/a.tar.gz"
    }
    override suspend fun discard(transferID: String) = call("discard")
    override suspend fun site(change: ServiceMoveSiteChange): ServiceMoveSite {
        call(if (change.dryRun) "siteCheck" else "site:${change.remoteAddress ?: "local"}")
        if (!change.dryRun) changes += change
        return site
    }
    override suspend fun probe(service: ServiceID): ServiceMoveProbe { call("probe"); return probeAnswer }
}

private class Rig(frontIsSource: Boolean = false) {
    val tape = Tape()
    val source = FakeMachine("source", tape, has = true)
    val target = FakeMachine("target", tape)
    val front = if (frontIsSource) source else FakeMachine("front", tape)
    val steps = mutableListOf<ServiceMoveStep>()

    fun plan(sourceAddress: String? = "10.0.0.2", targetAddress: String? = "10.0.0.3") = ServiceMovePlan(
        ServiceID.VAULTWARDEN, ServiceMoveEndpoint("10.0.0.3", 22, "admin"), sourceAddress, targetAddress,
        8222, false, false, AgentInstallContext(domain = "example.com"),
    )

    fun record(step: ServiceMoveStep = ServiceMoveStep.CHECK) = ServiceMoveRecord(
        deployment = "d", service = "vaultwarden", source = "s", target = "t",
        transferID = "0123456789abcdef0123456789abcdef", step = step,
    )

    fun runner(plan: ServiceMovePlan = plan(), record: ServiceMoveRecord = record()) = ServiceMoveRunner(
        plan, record, source, target, front, onRecord = {},
        onEvent = { event -> if (event is ServiceMoveEvent.Step) steps += event.step },
    )
}

class ServiceMoveRunnerTest {
    @Test
    fun `a move runs every stage in order and leaves nothing behind`() = runTest {
        val rig = Rig()
        rig.front.site = ServiceMoveSite.Remote("10.0.0.2")
        rig.runner().run()
        assertEquals(ServiceMoveStep.entries.toList(), rig.steps.toList())
        val calls = rig.tape.lines
        fun index(call: String) = calls.indexOf(call)
        assertTrue(index("source.has") < index("target.install"))
        assertTrue(index("target.install") < index("source.backup"))
        assertTrue(index("source.backup") < index("source.stop"))
        assertTrue(index("source.stop") < index("source.prepareSend"))
        assertTrue(index("target.authorize:LINE") < index("source.send:/b/a.tar.gz->10.0.0.3:ssh-ed25519 HOST"))
        assertTrue(index("target.revoke") < index("target.accept:abc:520"))
        assertTrue(index("target.accept:abc:520") < index("target.restore:/new/a.tar.gz"))
        assertTrue(index("target.restore:/new/a.tar.gz") < index("front.site:10.0.0.3"))
        assertTrue(index("front.site:10.0.0.3") < index("front.probe"))
        assertContains(calls, "target.prepareReceive:ssh-ed25519 KEY:500")
        assertContains(calls, "target.deleteBackup:/new/a.tar.gz")
        assertFalse("source.start" in calls || "target.removeCopy" in calls)
    }

    @Test
    fun `bringing the service onto the front points the site back at itself`() = runTest {
        val rig = Rig()
        rig.front.site = ServiceMoveSite.Remote("10.0.0.2")
        rig.runner(rig.plan(targetAddress = null)).run()
        assertEquals(listOf<String?>(null), rig.front.changes.map { it.remoteAddress })
    }

    @Test
    fun `the front being the old machine sends the site away`() = runTest {
        val rig = Rig(frontIsSource = true)
        rig.runner(rig.plan(sourceAddress = null)).run()
        assertEquals(listOf<String?>("10.0.0.3"), rig.source.changes.map { it.remoteAddress })
    }

    @Test
    fun `a failure before the old machine is stopped touches nothing there`() = runTest {
        val rig = Rig()
        rig.front.site = ServiceMoveSite.Remote("10.0.0.2")
        rig.source.failing += "backup"
        val failure = assertFailsWith<ServiceMoveFailure> { rig.runner().run() }
        assertEquals(ServiceMoveStep.BACKUP, failure.step)
        assertFalse(failure.undone.sourceStarted)
        assertTrue(failure.undone.targetCopyRemoved)
        assertEquals(emptyList(), failure.undone.problems)
        assertFalse("source.stop" in rig.tape.lines || "source.start" in rig.tape.lines)
    }

    @Test
    fun `a failed copy revokes the key starts the old copy and removes the new one`() = runTest {
        val rig = Rig()
        rig.front.site = ServiceMoveSite.Remote("10.0.0.2")
        rig.source.failing += "send:/b/a.tar.gz->10.0.0.3:ssh-ed25519 HOST"
        val failure = assertFailsWith<ServiceMoveFailure> { rig.runner().run() }
        assertEquals(ServiceMoveStep.SEND, failure.step)
        assertTrue(failure.undone.sourceStarted && failure.undone.targetCopyRemoved)
        assertFalse(failure.undone.entryRestored)
        assertContains(rig.tape.lines, "target.revoke")
        assertFalse(rig.tape.lines.any { it.startsWith("front.site:") })
    }

    @Test
    fun `a site that does not answer is pointed back and the old copy started again`() = runTest {
        val rig = Rig()
        rig.front.site = ServiceMoveSite.Remote("10.0.0.2")
        rig.front.probeAnswer = ServiceMoveProbe(false, false, 502, "bad gateway")
        val failure = assertFailsWith<ServiceMoveFailure> { rig.runner().run() }
        assertEquals(ServiceMoveStep.VERIFY, failure.step)
        assertEquals(ServiceMoveProblem.NotAnswering(502, "bad gateway"), failure.underlying)
        assertTrue(failure.undone.entryRestored && failure.undone.sourceStarted && failure.undone.targetCopyRemoved)
        assertEquals(listOf<String?>("10.0.0.3", "10.0.0.2"), rig.front.changes.map { it.remoteAddress })
        val calls = rig.tape.lines
        assertTrue(calls.lastIndexOf("front.site:10.0.0.2") < calls.indexOf("source.start"))
    }

    @Test
    fun `an undo that cannot finish names what it could not do`() = runTest {
        val rig = Rig()
        rig.front.site = ServiceMoveSite.Remote("10.0.0.2")
        rig.target.failing += setOf("restore:/new/a.tar.gz", "removeCopy")
        rig.source.failing += "start"
        val failure = assertFailsWith<ServiceMoveFailure> { rig.runner().run() }
        assertEquals(ServiceMoveStep.RESTORE, failure.step)
        assertFalse(failure.undone.sourceStarted || failure.undone.targetCopyRemoved)
        assertEquals(2, failure.undone.problems.size)
        assertTrue(failure.undone.problems.any { it.contains("starting the old copy") })
    }

    @Test
    fun `the checks refuse before anything is changed`() = runTest {
        val cases: List<Triple<String, (Rig) -> Unit, ServiceMoveProblem>> = listOf(
            Triple("not on the old machine", { it.source.has = false }, ServiceMoveProblem.NotOnSource),
            Triple("already on the new one", { it.target.has = true }, ServiceMoveProblem.AlreadyOnTarget),
            Triple("no site", { it.front.site = ServiceMoveSite.Missing }, ServiceMoveProblem.NoSiteOnFront),
            Triple("front serves it itself", { it.front.site = ServiceMoveSite.Local }, ServiceMoveProblem.FrontDisagrees("local")),
        )
        for ((name, arrange, expected) in cases) {
            val rig = Rig()
            rig.front.site = ServiceMoveSite.Remote("10.0.0.2")
            arrange(rig)
            val failure = assertFailsWith<ServiceMoveFailure>(name) { rig.runner().run() }
            assertEquals(expected, failure.underlying, name)
            assertEquals(ServiceMoveStep.CHECK, failure.step)
            assertFalse("target.install" in rig.tape.lines, name)
            assertFalse(failure.undone.targetCopyRemoved || failure.undone.sourceStarted, name)
        }
    }

    @Test
    fun `a site that cannot be checked does not undo a move that worked`() = runTest {
        val rig = Rig()
        rig.front.site = ServiceMoveSite.Remote("10.0.0.2")
        rig.front.probeAnswer = ServiceMoveProbe(false, true, 0, "no curl")
        rig.runner().run()
        assertFalse("source.start" in rig.tape.lines)
    }

    @Test
    fun `a resumed move skips what already happened`() = runTest {
        val rig = Rig()
        val record = rig.record(ServiceMoveStep.RESTORE).copy(
            installedOnTarget = true, sourceStopped = true,
            archiveName = "a.tar.gz", sha256 = "abc", sentBytes = 520,
        )
        rig.runner(record = record).run()
        assertEquals("target.accept:abc:520", rig.tape.lines.first())
        assertFalse("target.install" in rig.tape.lines || "source.stop" in rig.tape.lines)
    }

    @Test
    fun `undo alone brings the old copy back when the entry was switched`() = runTest {
        val rig = Rig()
        val record = rig.record().copy(installedOnTarget = true, sourceStopped = true, switchedEntry = true)
        val undone = rig.runner(record = record).undo()
        assertTrue(undone.entryRestored && undone.sourceStarted && undone.targetCopyRemoved)
        assertEquals(listOf<String?>("10.0.0.2"), rig.front.changes.map { it.remoteAddress })
    }
}
