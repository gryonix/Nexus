package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.servercontrol.Deployment

object AgentPresence {
    sealed interface Answer {
        /** It answered and named itself */
        data class Installed(val version: String) : Answer

        data object InstalledUnknownVersion : Answer

        /** Nothing answered, and WHY is carried rather than dropped */
        data class Unreachable(val reason: String) : Answer
    }

    /** What the agent's own reply means */
    fun answered(version: String): Answer {
        val reported = version.trim()
        return if (reported.isEmpty()) Answer.InstalledUnknownVersion
        else Answer.Installed(reported)
    }

    /** What a thrown transport error means, keeping the reason readable */
    fun refused(error: Throwable): Answer =
        Answer.Unreachable(error.message?.takeIf { it.isNotBlank() } ?: error.toString())

    fun repaired(deployment: Deployment, answer: Answer): Deployment? = when (answer) {
        is Answer.Unreachable -> null
        else -> if (deployment.usesAgent) null else deployment.copy(usesAgent = true)
    }
}
