package com.skaymer.gryonixnexus.aiassistant

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject

sealed interface AIStreamEvent {
    data class Text(val text: String) : AIStreamEvent
    data class Usage(val input: Int, val output: Int) : AIStreamEvent
    data object Done : AIStreamEvent
    data class Failure(val message: String) : AIStreamEvent
}

/** Turns server-sent-event lines into events. */
class AIStreamParser(private val format: AIWireFormat) {
    private var input = 0

    fun feed(line: String): List<AIStreamEvent> {
        if (!line.startsWith("data:")) return emptyList()
        val payload = line.removePrefix("data:").trim()
        if (payload == "[DONE]") return listOf(AIStreamEvent.Done)
        val json = runCatching { Json.parseToJsonElement(payload) as? JsonObject }.getOrNull() ?: return emptyList()
        (json["error"] as? JsonObject)?.let { return listOf(AIStreamEvent.Failure(it.string("message") ?: "error")) }
        return if (format == AIWireFormat.OPEN_AI) openAi(json) else anthropic(json)
    }

    private fun openAi(json: JsonObject): List<AIStreamEvent> {
        val events = mutableListOf<AIStreamEvent>()
        val choice = (json["choices"] as? JsonArray)?.firstOrNull() as? JsonObject
        val text = (choice?.get("delta") as? JsonObject)?.string("content")
        if (!text.isNullOrEmpty()) events += AIStreamEvent.Text(text)
        val usage = json["usage"] as? JsonObject
        val output = (usage?.get("completion_tokens") as? JsonPrimitive)?.intOrNull
        if (output != null) {
            events += AIStreamEvent.Usage((usage["prompt_tokens"] as? JsonPrimitive)?.intOrNull ?: 0, output)
        }
        return events
    }

    private fun anthropic(json: JsonObject): List<AIStreamEvent> = when (json.string("type")) {
        "content_block_delta" -> listOfNotNull(
            (json["delta"] as? JsonObject)?.string("text")?.takeIf { it.isNotEmpty() }?.let { AIStreamEvent.Text(it) },
        )
        "message_start" -> {
            val usage = (json["message"] as? JsonObject)?.get("usage") as? JsonObject
            input = (usage?.get("input_tokens") as? JsonPrimitive)?.intOrNull ?: 0
            emptyList()
        }
        "message_delta" -> {
            val output = ((json["usage"] as? JsonObject)?.get("output_tokens") as? JsonPrimitive)?.intOrNull ?: 0
            listOf(AIStreamEvent.Usage(input, output))
        }
        "message_stop" -> listOf(AIStreamEvent.Done)
        "error" -> listOf(AIStreamEvent.Failure((json["error"] as? JsonObject)?.string("message") ?: "error"))
        else -> emptyList()
    }
}
