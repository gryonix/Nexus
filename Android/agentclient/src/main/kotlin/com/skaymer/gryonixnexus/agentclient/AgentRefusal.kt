package com.skaymer.gryonixnexus.agentclient

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Why the agent refused, as a stable id with values */
data class AgentRefusal(val reason: String, val args: List<String>, val message: String)

/** Recent refusals, found again by the text shown */
object AgentRefusals {
    private const val KEPT = 32
    private val recent = ArrayDeque<AgentRefusal>()

    @Synchronized
    fun remember(refusal: AgentRefusal) {
        if (refusal.reason.isEmpty() || refusal.message.isEmpty()) return
        recent.removeAll { it.message == refusal.message }
        recent.addLast(refusal)
        while (recent.size > KEPT) recent.removeFirst()
    }

    /** The newest refusal whose words the text carries */
    @Synchronized
    fun find(text: String): AgentRefusal? = recent.lastOrNull { text.contains(it.message) }

    /** Reads reason and args from an error body */
    internal fun note(body: String) {
        val error = try {
            Json.parseToJsonElement(body) as? JsonObject
        } catch (_: Throwable) {
            null
        } ?: return
        val reason = error["reason"]?.jsonPrimitive?.content ?: return
        val args = (error["args"] as? JsonArray)?.map { it.jsonPrimitive.content }.orEmpty()
        remember(AgentRefusal(reason, args, error["message"]?.jsonPrimitive?.content.orEmpty()))
    }
}
