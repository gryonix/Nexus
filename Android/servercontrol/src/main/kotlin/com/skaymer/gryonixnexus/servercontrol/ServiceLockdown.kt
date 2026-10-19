package com.skaymer.gryonixnexus.servercontrol

interface AdminLockdownManaging {
    suspend fun status(): AdminLockdownState

    suspend fun set(enabled: Boolean): AdminLockdownState

    /** Guards only the given vhosts */
    suspend fun set(hosts: List<String>): AdminLockdownState
}

/** Applies a state that status returned */
suspend fun AdminLockdownManaging.restore(state: AdminLockdownState): AdminLockdownState = when (state) {
    is AdminLockdownState.Off -> set(false)
    is AdminLockdownState.All -> set(true)
    is AdminLockdownState.Only -> set(state.hosts.sorted())
}

/** Which implementation a deployment's admin-guard toggle goes through */
object LockdownRouting {
    fun route(usesAgent: Boolean, agentTransportAvailable: Boolean): ServiceControlRoute =
        ServiceControlRouting.route(usesAgent, agentTransportAvailable)
}

/** The SSH implementation: [StatusOperations]'s existing three lockdown methods, unchanged */
class SSHAdminLockdown(
    private val runner: SSHCommandRunner,
    private val config: DashboardConfig,
    private val host: SSHHostID,
) : AdminLockdownManaging {
    private fun operations() = StatusOperations(runner, config)

    override suspend fun status(): AdminLockdownState = operations().adminLockdownStatus(host)

    override suspend fun set(enabled: Boolean): AdminLockdownState =
        operations().setAdminLockdown(enabled, host)

    override suspend fun set(hosts: List<String>): AdminLockdownState =
        operations().setAdminLockdown(hosts, host)
}
