package com.skaymer.gryonixnexus.aiassistant

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class ProviderTest {
    private fun body(request: AIHttpRequest): JsonObject = Json.parseToJsonElement(request.body).jsonObject

    @Test fun openAiRequest() {
        val request = AIRequestBuilder.build(AIProviderConfig("openai", "gpt-x"), "k1", "sys", listOf(AIMessage(AIRole.USER, "hi")))
        assertEquals("https://api.openai.com/v1/chat/completions", request.url)
        assertEquals("Bearer k1", request.headers["Authorization"])
        val json = body(request)
        assertEquals("true", json["stream"]?.jsonPrimitive?.content)
        val messages = json["messages"] as JsonArray
        assertEquals("system", messages.first().jsonObject["role"]?.jsonPrimitive?.content)
        assertEquals("hi", messages.last().jsonObject["content"]?.jsonPrimitive?.content)
    }

    @Test fun anthropicRequest() {
        val request = AIRequestBuilder.build(AIProviderConfig("anthropic", "m"), "k2", "sys", listOf(AIMessage(AIRole.USER, "hi")))
        assertEquals("https://api.anthropic.com/v1/messages", request.url)
        assertEquals("k2", request.headers["x-api-key"])
        assertNull(request.headers["Authorization"])
        val json = body(request)
        assertEquals("sys", json["system"]?.jsonPrimitive?.content)
        assertEquals(1, (json["messages"] as JsonArray).size)
        assertTrue(json.containsKey("max_tokens"))
    }

    @Test fun openAiImageBecomesDataUrlPart() {
        val message = AIMessage(AIRole.USER, "what is this", listOf(AIImage("image/jpeg", "QUJD")))
        val request = AIRequestBuilder.build(AIProviderConfig("openai", "gpt-x"), "k", "s", listOf(message))
        val parts = (body(request)["messages"] as JsonArray).last().jsonObject["content"] as JsonArray
        assertEquals("what is this", parts.first().jsonObject["text"]?.jsonPrimitive?.content)
        val url = parts.last().jsonObject["image_url"]?.jsonObject?.get("url")?.jsonPrimitive?.content
        assertEquals("data:image/jpeg;base64,QUJD", url)
    }

    @Test fun anthropicImageBecomesBase64Block() {
        val message = AIMessage(AIRole.USER, "look", listOf(AIImage("image/png", "QUJD")))
        val request = AIRequestBuilder.build(AIProviderConfig("anthropic", "m"), "k", "s", listOf(message))
        val parts = (body(request)["messages"] as JsonArray).first().jsonObject["content"] as JsonArray
        val source = parts.first().jsonObject["source"]!!.jsonObject
        assertEquals("image/png", source["media_type"]?.jsonPrimitive?.content)
        assertEquals("QUJD", source["data"]?.jsonPrimitive?.content)
        assertEquals("look", parts.last().jsonObject["text"]?.jsonPrimitive?.content)
    }

    @Test fun ollamaNeedsNoKeyAndTrimsSlash() {
        val config = AIProviderConfig("ollama", "llama3.2:3b", "http://127.0.0.1:21434/v1/")
        val request = AIRequestBuilder.build(config, null, "s", emptyList())
        assertEquals("http://127.0.0.1:21434/v1/chat/completions", request.url)
        assertNull(request.headers["Authorization"])
        assertTrue(config.isLocal)
    }

    @Test fun openAiStream() {
        val parser = AIStreamParser(AIWireFormat.OPEN_AI)
        assertEquals(listOf(AIStreamEvent.Text("Hel")), parser.feed("data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}"))
        assertEquals(listOf(AIStreamEvent.Usage(5, 7)), parser.feed("data: {\"choices\":[],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":7}}"))
        assertEquals(listOf(AIStreamEvent.Done), parser.feed("data: [DONE]"))
        assertEquals(emptyList(), parser.feed(": keepalive"))
    }

    @Test fun anthropicStream() {
        val parser = AIStreamParser(AIWireFormat.ANTHROPIC)
        assertEquals(emptyList(), parser.feed("data: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":11}}}"))
        assertEquals(listOf(AIStreamEvent.Text("Yo")), parser.feed("data: {\"type\":\"content_block_delta\",\"delta\":{\"text\":\"Yo\"}}"))
        assertEquals(listOf(AIStreamEvent.Usage(11, 3)), parser.feed("data: {\"type\":\"message_delta\",\"usage\":{\"output_tokens\":3}}"))
        assertEquals(listOf(AIStreamEvent.Done), parser.feed("data: {\"type\":\"message_stop\"}"))
    }

    @Test fun streamError() {
        val parser = AIStreamParser(AIWireFormat.OPEN_AI)
        assertEquals(listOf(AIStreamEvent.Failure("bad key")), parser.feed("data: {\"error\":{\"message\":\"bad key\"}}"))
    }
}
