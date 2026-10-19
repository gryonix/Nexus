package com.skaymer.gryonixnexus.agentclient

import kotlinx.coroutines.flow.Flow

/** A failure talking to the agent */
sealed class AgentError(message: String) : Exception(message) {
    data class Rpc(val code: String, val text: String) : AgentError(text)

    data class Transport(val detail: String) : AgentError(detail)

    /** A response message could not be decoded against the schema */
    data class Decode(val detail: String) : AgentError(detail)
}

interface AgentByteStream {
    suspend fun write(data: ByteArray)
    suspend fun read(): ByteArray
    suspend fun close()
}

/** Opens a fresh byte stream per RPC */
interface AgentStreamFactory {
    suspend fun open(): AgentByteStream
}

/** The RPC transport the typed client sits on */
interface AgentTransport {
    suspend fun unary(path: String, request: ByteArray): ByteArray
    fun serverStream(path: String, request: ByteArray): Flow<ByteArray>
}
