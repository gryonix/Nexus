package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentTransport
import com.squareup.wire.Message
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow

class GatedTransport(private val answer: Message<*, *>, private val holdMillis: Long = 20) :
    AgentTransport {
    private val current = AtomicInteger(0)
    private val peak = AtomicInteger(0)

    val highest: Int get() = peak.get()

    override suspend fun unary(path: String, request: ByteArray): ByteArray {
        val now = current.incrementAndGet()
        peak.updateAndGet { maxOf(it, now) }
        delay(holdMillis)
        current.decrementAndGet()
        return answer.encode()
    }

    override fun serverStream(path: String, request: ByteArray): Flow<ByteArray> = emptyFlow()
}
