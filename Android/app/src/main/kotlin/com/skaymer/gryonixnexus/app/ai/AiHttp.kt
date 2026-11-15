package com.skaymer.gryonixnexus.app.ai

import com.skaymer.gryonixnexus.aiassistant.AIHttpRequest
import com.skaymer.gryonixnexus.aiassistant.AIStreamEvent
import com.skaymer.gryonixnexus.aiassistant.AIStreamParser
import com.skaymer.gryonixnexus.aiassistant.AIWireFormat
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn

class AiFailure(message: String) : Exception(message)

/** Sends one streaming request and yields its events. */
object AiHttp {
    fun stream(request: AIHttpRequest, format: AIWireFormat): Flow<AIStreamEvent> = flow {
        val connection = URL(request.url).openConnection() as HttpURLConnection
        coroutineContext[Job]?.invokeOnCompletion { connection.disconnect() }
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 20_000
            connection.readTimeout = 120_000
            connection.doOutput = true
            request.headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
            connection.outputStream.use { it.write(request.body.toByteArray()) }
            val status = connection.responseCode
            if (status !in 200..299) throw AiFailure("HTTP $status " + errorText(connection))
            val parser = AIStreamParser(format)
            connection.inputStream.bufferedReader().useLines { lines ->
                for (line in lines) for (event in parser.feed(line)) emitEvent(event)
            }
        } finally {
            connection.disconnect()
        }
    }.flowOn(Dispatchers.IO)

    private suspend fun kotlinx.coroutines.flow.FlowCollector<AIStreamEvent>.emitEvent(event: AIStreamEvent) {
        if (event is AIStreamEvent.Failure) throw AiFailure(event.message)
        emit(event)
    }

    private fun errorText(connection: HttpURLConnection): String =
        runCatching { connection.errorStream?.bufferedReader()?.readText()?.take(300) }.getOrNull().orEmpty()
}
