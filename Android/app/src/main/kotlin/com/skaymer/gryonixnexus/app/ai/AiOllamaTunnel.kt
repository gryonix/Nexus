package com.skaymer.gryonixnexus.app.ai

import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.servercontrol.PortForward
import com.skaymer.gryonixnexus.servercontrol.PortForwardState

object AiOllamaTunnel {
    const val LOCAL_PORT = 21434

    suspend fun baseUrl(app: GryonixApplication, config: AiConfig): String {
        val server = app.fleet.deployments.value.firstOrNull { it.id == config.ollamaServerId }
        if (server == null) {
            val url = config.ollamaUrl.trim()
            if (url.isEmpty()) throw AiFailure("Ollama address missing")
            return if (url.endsWith("/v1")) url else "$url/v1"
        }
        val forward = PortForward(
            id = "ai-${server.id}", deploymentID = server.id, name = "AI",
            localPort = LOCAL_PORT, remoteHost = "127.0.0.1", remotePort = 11434,
        )
        app.portForwards.start(forward, server)
        val state = app.portForwards.states.value[forward.id]
        if (state is PortForwardState.Failed) throw AiFailure(state.message)
        return "http://127.0.0.1:$LOCAL_PORT/v1"
    }
}
