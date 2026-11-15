package com.skaymer.gryonixnexus.app.servers.demo

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.agentclient.AgentTransport
import com.skaymer.gryonixnexus.app.servers.DemoDeployments
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.squareup.wire.Message
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/** The agent a demo server answers with */
object DemoAgent {
    /** A client for a demo server, null otherwise */
    fun client(deployment: Deployment): AgentClient? {
        if (!DemoDeployments.isDemoID(deployment.id)) return null
        return AgentClient(transport = DemoAgentTransport(deployment))
    }
}

/** Answers the agent's RPCs without a server */
class DemoAgentTransport(private val deployment: Deployment) : AgentTransport {
    private val machine: DemoAgentMachine get() = DemoAgentMachine(deployment)

    override suspend fun unary(path: String, request: ByteArray): ByteArray {
        delay(180)
        return DemoAgentState.unary(path, request, machine)
            ?: throw AgentError.Rpc("unimplemented", path)
    }

    override fun serverStream(path: String, request: ByteArray): Flow<ByteArray> = flow {
        val steps = DemoAgentState.stream(path, request, machine)
        for (step in steps) {
            delay(step.delay)
            if (step.drops) throw AgentError.Transport("the demo line dropped")
            emit(step.payload)
        }
    }
}

/** Which demo machine a call is about */
class DemoAgentMachine(val deployment: Deployment) {
    val id: String get() = deployment.id

    /** Catalog ids of this machine's services */
    val containers: List<String> get() = installed.map { it.id.rawValue }

    val installed get() = ServiceRegistry.services(deployment.services)
}

/** One message of a streamed answer */
class DemoAgentStep(val payload: ByteArray, val delay: Long = 260, val drops: Boolean = false)

/** The bytes the transport hands back */
fun Message<*, *>.demoPayload(): ByteArray = encode()

fun Message<*, *>.demoStep(delay: Long = 260): DemoAgentStep = DemoAgentStep(encode(), delay)
