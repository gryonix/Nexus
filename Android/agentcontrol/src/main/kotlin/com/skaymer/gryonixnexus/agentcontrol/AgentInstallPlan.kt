package com.skaymer.gryonixnexus.agentcontrol

import gryonixnexusd.v1.InstallPlan
import gryonixnexusd.v1.InstallPlanItemState
import gryonixnexusd.v1.InstallPlanPurpose

/** Why an install plan runs */
enum class AgentPlanPurpose(val wire: InstallPlanPurpose) {
    ADD(InstallPlanPurpose.INSTALL_PLAN_PURPOSE_ADD),
    SETUP(InstallPlanPurpose.INSTALL_PLAN_PURPOSE_SETUP),
    REPAIR(InstallPlanPurpose.INSTALL_PLAN_PURPOSE_REPAIR),
    REINSTALL(InstallPlanPurpose.INSTALL_PLAN_PURPOSE_REINSTALL);

    companion object {
        fun of(wire: InstallPlanPurpose): AgentPlanPurpose = entries.firstOrNull { it.wire == wire } ?: ADD
    }
}

/** Services an agent installs one by one on its own */
data class AgentInstallPlan(
    val id: String,
    val items: List<Item>,
    val finished: Boolean,
    val cancelled: Boolean = false,
    val purpose: AgentPlanPurpose = AgentPlanPurpose.ADD,
) {
    enum class State { PENDING, RUNNING, DONE, FAILED, SKIPPED }

    data class Item(
        val agentServiceID: String,
        val state: State,
        val jobID: String = "",
        val failure: String = "",
    )

    /** Whether a plan exists and still has work left */
    val isRunning: Boolean get() = id.isNotEmpty() && !finished

    /** Items with an outcome */
    val settled: Int get() = items.count { it.state in setOf(State.DONE, State.FAILED, State.SKIPPED) }

    /** Items the plan left uninstalled */
    val missed: List<Item> get() = items.filter { it.state == State.FAILED || it.state == State.SKIPPED }

    companion object {
        fun of(wire: InstallPlan): AgentInstallPlan = AgentInstallPlan(
            id = wire.plan_id,
            items = wire.items.map { Item(it.service_id, state(it.state), it.job_id, it.failure) },
            finished = wire.finished,
            cancelled = wire.cancelled,
            purpose = AgentPlanPurpose.of(wire.purpose),
        )

        /** The agent's step marker: number, total and service */
        fun step(text: String): Triple<Int, Int, String>? {
            if (!text.startsWith(STEP)) return null
            val lines = text.removePrefix(STEP).split("\n", limit = 2)
            val counts = lines.first().split("/").mapNotNull { it.trim().toIntOrNull() }
            if (counts.size != 2 || lines.size != 2) return null
            return Triple(counts[0], counts[1], lines[1].trim())
        }

        private const val STEP = "GRYONIXNEXUS_STEP "

        private fun state(wire: InstallPlanItemState): State = when (wire) {
            InstallPlanItemState.INSTALL_PLAN_ITEM_STATE_RUNNING -> State.RUNNING
            InstallPlanItemState.INSTALL_PLAN_ITEM_STATE_DONE -> State.DONE
            InstallPlanItemState.INSTALL_PLAN_ITEM_STATE_FAILED -> State.FAILED
            InstallPlanItemState.INSTALL_PLAN_ITEM_STATE_SKIPPED -> State.SKIPPED
            else -> State.PENDING
        }
    }
}
