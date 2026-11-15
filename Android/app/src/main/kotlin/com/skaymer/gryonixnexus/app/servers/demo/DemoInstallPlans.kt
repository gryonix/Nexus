package com.skaymer.gryonixnexus.app.servers.demo

import com.skaymer.gryonixnexus.agentclient.AgentError
import gryonixnexusd.v1.InstallPlan
import gryonixnexusd.v1.InstallPlanItem
import gryonixnexusd.v1.InstallPlanItemState
import gryonixnexusd.v1.InstallPlanPurpose
import gryonixnexusd.v1.JobEvent
import gryonixnexusd.v1.JobPhase

/** Demo plans that take time, one service after another */
object DemoInstallPlans {
    private class Plan(val id: String, val services: List<String>, val purpose: InstallPlanPurpose, val started: Long)

    private class Line(val atSeconds: Double, val phase: JobPhase, val text: String)

    private val plans = mutableListOf<Plan>()

    /** Seconds one service takes in the demo */
    private const val SERVICE_SECONDS = 2.5

    @Synchronized
    fun start(services: List<String>, purpose: InstallPlanPurpose): InstallPlan {
        plans.lastOrNull()?.takeIf { !finished(it) }?.let {
            throw AgentError.Rpc("already_exists", "an install plan is already running on this host")
        }
        val plan = Plan("demo-plan-${plans.size + 1}", services, purpose, System.currentTimeMillis())
        plans += plan
        return wire(plan)
    }

    @Synchronized
    fun get(id: String): InstallPlan {
        val found = if (id.isEmpty()) plans.lastOrNull() else plans.firstOrNull { it.id == id }
        return found?.let(::wire) ?: InstallPlan()
    }

    @Synchronized
    fun owns(jobID: String): Boolean = plans.any { it.id == jobID }

    /** The plan's log as timed steps from a sequence on */
    @Synchronized
    fun log(id: String, from: Long): List<DemoAgentStep> {
        val plan = plans.firstOrNull { it.id == id } ?: return emptyList()
        var clock = elapsed(plan)
        return lines(plan).withIndex().filter { it.index >= from }.map { (index, line) ->
            val wait = ((line.atSeconds - clock).coerceAtLeast(0.0) * 1000).toLong()
            clock = maxOf(clock, line.atSeconds)
            JobEvent(
                job_id = plan.id, sequence = index.toLong(), phase = line.phase,
                stream = "agent", text = line.text,
            ).demoStep(delay = wait)
        }
    }

    private fun lines(plan: Plan): List<Line> {
        val count = plan.services.size
        val progress = JobPhase.JOB_PHASE_PROGRESS
        return plan.services.flatMapIndexed { index, id ->
            val begin = index * SERVICE_SECONDS
            listOf(
                Line(begin, progress, "GRYONIXNEXUS_STEP ${index + 1}/$count\n$id"),
                Line(begin + 0.5, progress, "pulling the $id image"),
                Line(begin + 1.2, progress, "starting $id"),
                Line(begin + 1.8, progress, "reloading Caddy"),
            )
        } + Line(count * SERVICE_SECONDS, JobPhase.JOB_PHASE_COMPLETED, "")
    }

    private fun elapsed(plan: Plan): Double = (System.currentTimeMillis() - plan.started) / 1000.0

    private fun finished(plan: Plan): Boolean = elapsed(plan) >= plan.services.size * SERVICE_SECONDS

    private fun wire(plan: Plan): InstallPlan {
        val settled = (elapsed(plan) / SERVICE_SECONDS).toInt()
        return InstallPlan(
            plan_id = plan.id,
            purpose = plan.purpose,
            finished = settled >= plan.services.size,
            items = plan.services.mapIndexed { index, id ->
                InstallPlanItem(
                    service_id = id,
                    job_id = if (index <= settled) "${plan.id}-$index" else "",
                    state = when {
                        index < settled -> InstallPlanItemState.INSTALL_PLAN_ITEM_STATE_DONE
                        index == settled -> InstallPlanItemState.INSTALL_PLAN_ITEM_STATE_RUNNING
                        else -> InstallPlanItemState.INSTALL_PLAN_ITEM_STATE_PENDING
                    },
                )
            },
        )
    }
}
