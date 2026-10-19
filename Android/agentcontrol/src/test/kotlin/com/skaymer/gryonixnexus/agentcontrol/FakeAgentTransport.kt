package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.agentclient.AgentTransport
import com.squareup.wire.Message
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/** The agent, scripted */
class FakeAgentTransport : AgentTransport {
    /** One scripted reply: some messages, then optionally an error */
    class Reply(val payloads: List<ByteArray>, val error: Throwable?)

    private val queued = mutableMapOf<String, ArrayDeque<Reply>>()
    private val recorded = mutableListOf<Pair<String, ByteArray>>()

    val calls: List<Pair<String, ByteArray>> get() = recorded

    val paths: List<String> get() = recorded.map { it.first }

    fun reply(path: String, message: Message<*, *>) {
        queue(path, Reply(listOf(message.encode()), null))
    }

    fun stream(path: String, vararg messages: Message<*, *>) {
        queue(path, Reply(messages.map { it.encode() }, null))
    }

    fun streamThenFail(path: String, error: Throwable, vararg messages: Message<*, *>) {
        queue(path, Reply(messages.map { it.encode() }, error))
    }

    /** Fails the next call on [path] before anything is delivered */
    fun fail(path: String, error: Throwable) {
        queue(path, Reply(emptyList(), error))
    }

    fun refuse(path: String, code: String = "failed_precondition", text: String) {
        fail(path, AgentError.Rpc(code, text))
    }

    private fun queue(path: String, reply: Reply) {
        queued.getOrPut(path) { ArrayDeque() }.addLast(reply)
    }

    private fun next(path: String): Reply {
        val key = queued.keys.firstOrNull { path.endsWith(it) && queued[it]?.isNotEmpty() == true }
        checkNotNull(key) { "no scripted reply for $path" }
        return queued.getValue(key).removeFirst()
    }

    override suspend fun unary(path: String, request: ByteArray): ByteArray {
        recorded += path to request
        val reply = next(path)
        reply.error?.let { throw it }
        return reply.payloads.firstOrNull()
            ?: error("$path was scripted with no message to return")
    }

    override fun serverStream(path: String, request: ByteArray): Flow<ByteArray> {
        recorded += path to request
        val reply = next(path)
        return flow {
            for (payload in reply.payloads) emit(payload)
            reply.error?.let { throw it }
        }
    }
}
