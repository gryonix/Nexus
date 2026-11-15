package com.skaymer.gryonixnexus.aiassistant

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

enum class AIWireFormat { OPEN_AI, ANTHROPIC }

enum class AIRole(val raw: String) { SYSTEM("system"), USER("user"), ASSISTANT("assistant") }

/** A picture attached to a message, base64-encoded */
data class AIImage(val mediaType: String, val base64: String)

data class AIMessage(val role: AIRole, val content: String, val images: List<AIImage> = emptyList())

data class AIHttpRequest(val url: String, val headers: Map<String, String>, val body: String)

/** The provider and model a chat talks to. */
data class AIProviderConfig(val providerId: String, val model: String, val baseUrl: String = defaultBaseUrl(providerId) ?: "") {
    val isLocal: Boolean get() = providerId == OLLAMA_ID
    val format: AIWireFormat get() = if (providerId == "anthropic") AIWireFormat.ANTHROPIC else AIWireFormat.OPEN_AI

    companion object {
        const val OLLAMA_ID = "ollama"

        private val bases = mapOf(
            "openai" to "https://api.openai.com/v1",
            "anthropic" to "https://api.anthropic.com/v1",
            "deepseek" to "https://api.deepseek.com/v1",
            "gemini" to "https://generativelanguage.googleapis.com/v1beta/openai",
            "groq" to "https://api.groq.com/openai/v1",
            "mistral" to "https://api.mistral.ai/v1",
            "openrouter" to "https://openrouter.ai/api/v1",
            "xai" to "https://api.x.ai/v1",
        )

        private val models = mapOf(
            "openai" to "gpt-4o-mini", "anthropic" to "claude-haiku-4-5",
            "deepseek" to "deepseek-chat", "gemini" to "gemini-2.0-flash",
            "groq" to "llama-3.3-70b-versatile", "mistral" to "mistral-small-latest",
            "openrouter" to "openai/gpt-4o-mini", "xai" to "grok-3-mini",
            "ollama" to "llama3.2:3b",
        )

        fun defaultBaseUrl(id: String): String? = bases[id]

        fun suggestedModel(id: String): String = models[id] ?: ""
    }
}

/** Builds the streaming chat request for a provider. */
object AIRequestBuilder {
    const val ANTHROPIC_VERSION = "2023-06-01"
    const val MAX_TOKENS = 2048

    fun build(config: AIProviderConfig, apiKey: String?, system: String, messages: List<AIMessage>): AIHttpRequest {
        val base = config.baseUrl.trimEnd('/')
        return when (config.format) {
            AIWireFormat.ANTHROPIC -> anthropic(config, base, apiKey.orEmpty(), system, messages)
            AIWireFormat.OPEN_AI -> openAi(config, base, apiKey, system, messages)
        }
    }

    private fun openAi(config: AIProviderConfig, base: String, key: String?, system: String, messages: List<AIMessage>): AIHttpRequest {
        val headers = mutableMapOf("Content-Type" to "application/json")
        if (!key.isNullOrEmpty()) headers["Authorization"] = "Bearer $key"
        val body = buildJsonObject {
            put("model", config.model)
            put("stream", true)
            put("stream_options", buildJsonObject { put("include_usage", true) })
            put("messages", wire(listOf(AIMessage(AIRole.SYSTEM, system)) + messages, ::openAiContent))
        }
        return AIHttpRequest("$base/chat/completions", headers, body.toString())
    }

    private fun anthropic(config: AIProviderConfig, base: String, key: String, system: String, messages: List<AIMessage>): AIHttpRequest {
        val headers = mapOf("Content-Type" to "application/json", "x-api-key" to key, "anthropic-version" to ANTHROPIC_VERSION)
        val body = buildJsonObject {
            put("model", config.model)
            put("max_tokens", MAX_TOKENS)
            put("stream", true)
            put("system", system)
            put("messages", wire(messages.filter { it.role != AIRole.SYSTEM }, ::anthropicContent))
        }
        return AIHttpRequest("$base/messages", headers, body.toString())
    }

    private fun wire(messages: List<AIMessage>, content: (AIMessage) -> JsonElement): JsonArray = buildJsonArray {
        messages.forEach { add(buildJsonObject { put("role", it.role.raw); put("content", content(it)) }) }
    }

    /** Plain text, or text plus image_url parts */
    private fun openAiContent(message: AIMessage): JsonElement {
        if (message.images.isEmpty()) return JsonPrimitive(message.content)
        return buildJsonArray {
            add(buildJsonObject { put("type", "text"); put("text", message.content) })
            message.images.forEach { image ->
                add(buildJsonObject {
                    put("type", "image_url")
                    put("image_url", buildJsonObject { put("url", "data:${image.mediaType};base64,${image.base64}") })
                })
            }
        }
    }

    /** Plain text, or image blocks followed by the text */
    private fun anthropicContent(message: AIMessage): JsonElement {
        if (message.images.isEmpty()) return JsonPrimitive(message.content)
        return buildJsonArray {
            message.images.forEach { image ->
                add(buildJsonObject {
                    put("type", "image")
                    put("source", buildJsonObject {
                        put("type", "base64"); put("media_type", image.mediaType); put("data", image.base64)
                    })
                })
            }
            add(buildJsonObject { put("type", "text"); put("text", message.content) })
        }
    }
}

internal fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
