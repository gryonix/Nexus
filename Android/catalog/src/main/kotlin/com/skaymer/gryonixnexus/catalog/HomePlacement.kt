package com.skaymer.gryonixnexus.catalog

/** Whether a deployment's services run inside the house */
object HomePlacement {
    /** Scenario B, LAN-only and dynamic DNS imply home */
    fun isAtHome(topology: Topology, scope: DeploymentScope, machineAtHome: Boolean): Boolean =
        topology == Topology.VPS_RELAY_WITH_HOME_BACKEND || impliesHome(scope) || machineAtHome

    /** Scopes that only make sense for a machine at home */
    fun impliesHome(scope: DeploymentScope): Boolean =
        scope == DeploymentScope.LOCAL_ONLY || scope == DeploymentScope.DYNAMIC_DNS

    /** Whether the configurator must ask about the machine */
    fun needsAnswer(topology: Topology, scope: DeploymentScope): Boolean =
        topology == Topology.SINGLE_HOST && !impliesHome(scope)
}
