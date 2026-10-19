package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.agentcontrol.AgentJob
import com.skaymer.gryonixnexus.agentcontrol.AgentJobKind
import com.skaymer.gryonixnexus.agentcontrol.AgentJobOutcome
import com.skaymer.gryonixnexus.app.servers.WrapperLogText
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.DetachedJobs
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.NodeCapability
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import java.time.Instant
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class RunningJobsTests {
    private fun deployment(name: String = "vps-middle") = Deployment(
        id = name,
        name = name,
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.10", user = "root"),
        usesAgent = true,
    )

    private fun pair() = Deployment(
        id = "22222222-2222-2222-2222-222222222222",
        name = "pair",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.10", user = "root"),
        homeWGAddress = "10.8.0.2",
        usesAgent = true,
    )

    private fun job(kind: AgentJobKind, subject: String) = AgentJob(
        id = "job-1",
        kind = kind,
        subject = subject,
        started = Instant.ofEpochSecond(1_000),
        finished = null,
        outcome = AgentJobOutcome.RUNNING,
        failure = "",
        events = 3,
    )

    @Test
    fun theTitleNamesTheVerbAndTheServiceByItsCatalogName() {
        val update = RunningJobs.title(job(AgentJobKind.UPDATE, "nextcloud"), deployment())
        assertTrue(update.contains("Nextcloud"), "the catalog's name, not the agent's id: $update")
        val backup = RunningJobs.title(job(AgentJobKind.BACKUP, "nextcloud"), deployment())
        assertFalse(update == backup, "an update and a backup of one service read differently")
    }

    @Test
    fun aContainerGroupKeepsTheNameTheHostGaveIt() {
        val title = RunningJobs.title(job(AgentJobKind.CONTAINER_BACKUP, "immich-stack"), deployment())
        assertTrue(title.contains("immich-stack"), title)
    }

    /** A verb this build predates still gets a line */
    @Test
    fun anUnknownKindStillNamesTheServer() {
        val title = RunningJobs.title(job(AgentJobKind.UNKNOWN, "whatever"), deployment("orion"))
        assertTrue(title.contains("orion"), title)
    }

    @Test
    fun theStripPrintsTheHostsWordsAndNotTheProtocol() {
        val tail = " Container adguardhome Running\n" +
            "GRYONIXNEXUS_UPDATE_DONE adguard-home\n" +
            "GRYONIXNEXUS_UPDATE_CTL_DONE"
        val readable = WrapperLogText.readable(tail)
        assertTrue(readable.contains("Container adguardhome Running"), readable)
        assertFalse(readable.contains("GRYONIXNEXUS"), readable)
    }

    /** A detached SSH run reads like an agent run */
    @Test
    fun aDetachedRunIsNamedLikeAnAgentRun() {
        val job = DetachedJobs.Job(
            id = "backup-adguard-home-1", kind = DetachedJobs.Kind.BACKUP,
            subject = "adguard-home", startedUnix = 1, exitCode = null,
        )
        val title = RunningJobs.title(job, deployment())
        assertTrue(title.contains("AdGuard Home"), title)
        assertFalse(title.contains("$"), "an unsubstituted placeholder is what a live run showed: $title")
        // And the two routes agree about one host's work.
        val viaAgent = RunningJobs.title(job(AgentJobKind.BACKUP, "adguard-home"), deployment())
        assertEquals(viaAgent, title)
    }

    /** The strip reads EVERY worker's journal, not the default host's */
    @Test
    fun theStripReadsEveryWorkersJournal() {
        val base = pair()
        val third = DeploymentNode(
            id = "33333333-3333-3333-3333-333333333333",
            endpoint = HostEndpoint(host = "10.8.0.3", user = "root"),
            capabilities = setOf(NodeCapability.WORKER),
            routedThrough = base.ingressNode?.id,
        )
        val grown = base.copy(storedNodes = base.derivedNodes + third)

        val hosts = RunningJobs.journalHosts(grown)
        assertTrue(SSHHostID.node(third.id) in hosts, "a placed worker is never asked: $hosts")
        assertTrue(grown.servicesHost in hosts, "the default worker is still asked: $hosts")
    }

    @Test
    fun theRelayIsNotAskedForAJournalItCannotHave() {
        val deployment = pair()
        val relay = deployment.ingressNode!!
        assertFalse(relay.runsServices, "the fixture stopped being a relay pair")
        assertFalse(
            relay.sshHost in RunningJobs.journalHosts(deployment),
            "the relay runs nothing and has no journal — asking it is a round trip for a certain nothing",
        )
    }

    @Test
    fun `two machines running the same verb in the same second are two rows`() {
        val id = DetachedJobs.jobID(DetachedJobs.Kind.BACKUP, "nextcloud", 1_759_000_000)
        val one = RunningJob(id = id, deploymentID = "d", title = "Backing up Nextcloud", host = SSHHostID.HOME)
        val two = one.copy(host = SSHHostID.node("33333333-3333-3333-3333-333333333333"))
        assertEquals(one.id, two.id, "the fixture stopped being the collision it is about")
        assertNotEquals(one.key, two.key, "one machine's run would hide the other")
        assertNotEquals(one.key, one.copy(host = null).key)
    }

    @Test
    fun everyKindHasAWording() {
        for (kind in AgentJobKind.entries) {
            val title = RunningJobs.title(job(kind, "nextcloud"), deployment())
            assertFalse(title.isBlank(), "$kind has no wording")
        }
    }

    @Test
    fun `a model fetch names the model rather than the engine`() {
        val title = RunningJobs.title(job(AgentJobKind.MODEL_PULL, "llama3.2:3b"), deployment())
        assertTrue(title.contains("llama3.2:3b"))
        assertFalse(title.lowercase().contains("ollama"))
    }

    @Test
    fun `a service run inside a plan is not shown on its own`() {
        assertTrue(RunningJobs.shownAlone(job(AgentJobKind.INSTALL, "nextcloud")))
        assertFalse(RunningJobs.shownAlone(job(AgentJobKind.INSTALL, "nextcloud").copy(partOf = "plan-1")))
    }

    @Test
    fun `a repair plan is named after the server and a plan names each service`() {
        assertEquals("Repairing vps-middle", RunningJobs.title(job(AgentJobKind.REPAIR, "mailcow, vaultwarden +5"), deployment()))
        val install = RunningJobs.title(job(AgentJobKind.INSTALL, "mailcow, vaultwarden +5"), deployment())
        assertTrue(install.contains("Vaultwarden") && install.endsWith("+5"), install)
    }
}
