package com.skaymer.gryonixnexus.transport

import com.skaymer.gryonixnexus.agentclient.AgentByteStream
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.agentclient.AgentTransport
import com.skaymer.gryonixnexus.agentclient.ByteReader
import com.skaymer.gryonixnexus.agentclient.ConnectEnvelope
import com.skaymer.gryonixnexus.agentclient.HTTPWire
import com.skaymer.gryonixnexus.agentclient.parseConnectError
import com.skaymer.gryonixnexus.agentclient.parseConnectTrailer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext

interface BridgeChannelFactory {
    /** Open a channel running [command]; the caller closes it */
    suspend fun open(command: String): BridgeChannel
}

interface BridgeChannel {
    val stream: AgentByteStream

    val stderrText: String
    suspend fun close()
}

class SSHAgentTransport(
    private val channels: BridgeChannelFactory,
    private val bridgeCommand: String = DEFAULT_BRIDGE_COMMAND,
    /** Which INSTALLATION of the app is calling */
    private val deviceUID: String = "",
) : AgentTransport {
    companion object {
        const val DEFAULT_BRIDGE_COMMAND = "sudo -n /usr/local/bin/gryonixnexusd bridge"
    }

    override suspend fun unary(path: String, request: ByteArray): ByteArray {
        val channel = channels.open(bridgeCommand)
        try {
            val reader = ByteReader(channel.stream)
            try {
                channel.stream.write(HTTPWire.request(path, "application/proto", request, deviceUID))
                val head = HTTPWire.readHead(reader)
                val body = HTTPWire.readBody(reader, head)
                if (head.status != 200) throw parseConnectError(body, head.status)
                return body
            } catch (error: Throwable) {
                throw explained(error, channel)
            }
        } finally {
            channel.close()
        }
    }

    override fun serverStream(path: String, request: ByteArray): Flow<ByteArray> = flow {
        val channel = channels.open(bridgeCommand)
        try {
            val reader = ByteReader(channel.stream)
            try {
                val enveloped = ConnectEnvelope.encode(request)
                channel.stream.write(HTTPWire.request(path, "application/connect+proto", enveloped, deviceUID))
                val head = HTTPWire.readHead(reader)
                if (head.status != 200) {
                    throw parseConnectError(HTTPWire.readBody(reader, head), head.status)
                }
                val decoder = ConnectEnvelope.Decoder()
                var ended = false
                HTTPWire.readChunks(reader, head) { chunk ->
                    decoder.append(chunk)
                    var keepGoing = true
                    while (keepGoing) {
                        val frame = decoder.next() ?: break
                        if (frame.isEndOfStream) {
                            parseConnectTrailer(frame.payload)?.let { throw it }
                            ended = true
                            keepGoing = false
                        } else {
                            emit(frame.payload)
                        }
                    }
                    keepGoing
                }
                if (!ended) throw AgentError.Transport(ConnectEnvelope.CUT_OFF_MESSAGE)
            } catch (error: Throwable) {
                throw explained(error, channel)
            }
        } finally {
            channel.close()
        }
    }

    private fun explained(error: Throwable, channel: BridgeChannel): Throwable {
        if (error is AgentError.Rpc) return error
        val said = channel.stderrText
        if (said.isEmpty()) return error
        return AgentError.Transport("the agent bridge did not start: $said")
    }
}

/** The sshj-backed factory: one exec session per RPC */
class SshjBridgeChannelFactory(
    private val connection: net.schmizz.sshj.SSHClient,
) : BridgeChannelFactory {
    override suspend fun open(command: String): BridgeChannel = withContext(Dispatchers.IO) {
        val session = connection.startSession()
        val exec = session.exec(command)
        object : BridgeChannel {
            private val bytes = ExecByteStream(exec.outputStream, exec.inputStream, exec.errorStream)
            override val stream: AgentByteStream get() = bytes
            override val stderrText: String get() = bytes.stderrText
            override suspend fun close() = withContext(Dispatchers.IO) {
                runCatching { exec.close() }
                runCatching { session.close() }
                Unit
            }
        }
    }
}
