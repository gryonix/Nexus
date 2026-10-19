package com.skaymer.gryonixnexus.app.install

/** Where one machine's run is, across its three parts */
data class InstallParts(
    val throughAgent: Boolean = false,
    val scriptDone: Boolean = false,
    val agentLines: Int = 0,
    val agentDone: Boolean = false,
    val servicesTotal: Int = 0,
    val servicesDone: Int = 0,
    /** Services installed by the setup script instead */
    val directServices: Boolean = false,
    val directStep: Double = 0.0,
) {
    /** The whole run's share, never going back */
    fun fraction(script: Double): Double {
        if (!throughAgent) return script
        val setup = if (scriptDone) 1.0 else script
        val agent = when {
            agentDone || directServices -> 1.0
            else -> minOf(agentLines.toDouble() / TYPICAL_BUILD_LINES, BUILD_CEILING)
        }
        val services = when {
            directServices -> directStep
            servicesTotal > 0 -> servicesDone.toDouble() / servicesTotal
            agentDone -> 1.0
            else -> 0.0
        }
        val rest = 1 - SCRIPT_SHARE - AGENT_SHARE
        return SCRIPT_SHARE * setup + AGENT_SHARE * agent + rest * services
    }

    companion object {
        const val SCRIPT_SHARE = 0.45
        const val AGENT_SHARE = 0.25
        /** Lines a clean agent build prints */
        const val TYPICAL_BUILD_LINES = 225
        const val BUILD_CEILING = 0.99
    }
}
