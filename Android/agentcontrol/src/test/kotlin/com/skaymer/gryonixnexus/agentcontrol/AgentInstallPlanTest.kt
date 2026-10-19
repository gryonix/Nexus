package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.catalog.ServiceID
import gryonixnexusd.v1.InstallPlan
import gryonixnexusd.v1.InstallPlanItem
import gryonixnexusd.v1.InstallPlanItemState
import gryonixnexusd.v1.JobEvent
import gryonixnexusd.v1.JobPhase
import gryonixnexusd.v1.StartInstallPlanRequest
import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import org.junit.jupiter.api.Test

class AgentInstallPlanTest {
    private fun item(id: String, state: InstallPlanItemState, job: String = "", failure: String = "") =
        InstallPlanItem(service_id = id, state = state, job_id = job, failure = failure)

    @Test
    fun `the whole list goes to the agent in one call`() = runTest {
        val transport = FakeAgentTransport()
        transport.reply("Install/StartInstallPlan", InstallPlan(plan_id = "p1"))
        val context = AgentInstallContext(domain = "example.com")
        val plan = AgentInstallOperations(AgentClient(transport))
            .startPlan(listOf(ServiceID.VAULTWARDEN to context, ServiceID.IMMICH to context))
        assertEquals("p1", plan.id)
        val sent = StartInstallPlanRequest.ADAPTER.decode(transport.calls.first().second)
        assertEquals(listOf("vaultwarden", "immich"), sent.services.map { it.service_id })
        assertEquals("example.com", sent.services.first().domain)
    }

    @Test
    fun `a plan already running is joined instead`() = runTest {
        val transport = FakeAgentTransport()
        transport.refuse("Install/StartInstallPlan", "already_exists", "an install plan is already running")
        transport.reply("Install/GetInstallPlan", InstallPlan(plan_id = "running"))
        val plan = AgentInstallOperations(AgentClient(transport))
            .startPlan(listOf(ServiceID.VAULTWARDEN to AgentInstallContext(domain = "example.com")))
        assertEquals("running", plan.id)
    }

    @Test
    fun `following reads the plan's own log and ends with the plan`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream(
            "Jobs/WatchJob",
            JobEvent(sequence = 0, phase = JobPhase.JOB_PHASE_PROGRESS, text = "GRYONIXNEXUS_STEP 1/2\nvaultwarden"),
            JobEvent(sequence = 1, phase = JobPhase.JOB_PHASE_PROGRESS, text = "pulling"),
        )
        transport.reply(
            "Install/GetInstallPlan",
            InstallPlan(
                plan_id = "p1", finished = true,
                items = listOf(
                    item("vaultwarden", InstallPlanItemState.INSTALL_PLAN_ITEM_STATE_DONE, "j1"),
                    item("immich", InstallPlanItemState.INSTALL_PLAN_ITEM_STATE_FAILED, failure = "ports in use"),
                ),
            ),
        )
        val started = AgentInstallPlan(
            "p1",
            listOf(
                AgentInstallPlan.Item("vaultwarden", AgentInstallPlan.State.RUNNING, "j1"),
                AgentInstallPlan.Item("immich", AgentInstallPlan.State.PENDING),
            ),
            finished = false,
        )
        val services = mutableListOf<String>()
        val chunks = mutableListOf<String>()
        val mark = AgentInstallOperations.PlanLogMark()
        val ended = AgentInstallOperations(AgentClient(transport)).followPlan(
            started, onService = { services += it }, onProgress = { _, _ -> }, onChunk = { chunks += it },
            pauseMillis = 0, mark = mark,
        )
        assertEquals(listOf("vaultwarden"), services)
        assertEquals(listOf("pulling\n"), chunks)
        assertEquals(2L, mark.next)
        assertEquals(listOf("immich"), ended.missed.map { it.agentServiceID })
        assertEquals(2, ended.settled)
    }

    @Test
    fun `the step marker names number, total and service`() {
        assertEquals(Triple(2, 5, "nextcloud"), AgentInstallPlan.step("GRYONIXNEXUS_STEP 2/5\nnextcloud"))
        assertEquals(null, AgentInstallPlan.step("pulling the Nextcloud images"))
    }

    @Test
    fun `a plan the agent forgot after a restart ends the wait`() = runTest {
        val transport = FakeAgentTransport()
        transport.stream("Jobs/WatchJob")
        transport.reply("Install/GetInstallPlan", InstallPlan())
        val started = AgentInstallPlan("p1", listOf(AgentInstallPlan.Item("immich", AgentInstallPlan.State.PENDING)), false)
        val error = runCatching {
            AgentInstallOperations(AgentClient(transport)).followPlan(
                started, onService = {}, onProgress = { _, _ -> }, onChunk = {}, pauseMillis = 0,
            )
        }.exceptionOrNull()
        kotlin.test.assertTrue(error is AgentInstallOperations.PlanLost, "got $error")
    }
}
