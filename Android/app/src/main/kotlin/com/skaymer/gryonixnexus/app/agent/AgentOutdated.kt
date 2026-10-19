package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.agentclient.AgentError

/** Recognises what an older agent answers to newer requests */
object AgentOutdated {
    /** Replies of agents that predate the request */
    private val MARKERS = listOf(
        "unknown service '", "has no installer for '", "unknown method",
        "choose a disk task", "choose a channel",
    )

    fun matches(error: Throwable): Boolean =
        error is AgentError.Rpc && MARKERS.any { error.text.contains(it) }
}
