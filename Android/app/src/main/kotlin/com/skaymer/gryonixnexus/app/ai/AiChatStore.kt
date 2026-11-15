package com.skaymer.gryonixnexus.app.ai

import com.skaymer.gryonixnexus.aiassistant.AIChat
import com.skaymer.gryonixnexus.aiassistant.AIChatFileStore
import com.skaymer.gryonixnexus.aiassistant.AIChatHistory
import com.skaymer.gryonixnexus.aiassistant.AIChatMessage
import com.skaymer.gryonixnexus.aiassistant.AIContext
import com.skaymer.gryonixnexus.aiassistant.AIBudgetState
import com.skaymer.gryonixnexus.aiassistant.AIHttpRequest
import com.skaymer.gryonixnexus.aiassistant.AIMessage
import com.skaymer.gryonixnexus.aiassistant.AIPrompts
import com.skaymer.gryonixnexus.aiassistant.AIProviderConfig
import com.skaymer.gryonixnexus.aiassistant.AIRequestBuilder
import com.skaymer.gryonixnexus.aiassistant.AIRole
import com.skaymer.gryonixnexus.aiassistant.AIStreamEvent
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Chats of this device and the one answer streaming now. */
class AiChatStore(
    private val file: AIChatFileStore,
    private val images: AiImageStore? = null,
    private val scope: CoroutineScope,
    private val settings: AiSettings,
    private val localBaseUrl: suspend (AiConfig) -> String,
    private val show: () -> Unit,
    private val text: (AiMessageId) -> String,
    private val now: () -> Long = { System.currentTimeMillis() },
) {
    enum class AiMessageId { CHOOSE_FIRST, LIMIT_REACHED }

    private val _history = MutableStateFlow(file.load())
    val history: StateFlow<AIChatHistory> = _history.asStateFlow()
    private val _streaming = MutableStateFlow<String?>(null)
    val streamingChatId: StateFlow<String?> = _streaming.asStateFlow()
    private val _failure = MutableStateFlow<String?>(null)
    val failure: StateFlow<String?> = _failure.asStateFlow()
    private val _open = MutableStateFlow<String?>(null)
    val openChatId: StateFlow<String?> = _open.asStateFlow()
    private var job: Job? = null

    fun chat(id: String): AIChat? = _history.value.chats.firstOrNull { it.id == id }

    fun open(id: String?) { _open.value = id }

    fun delete(id: String) {
        if (_streaming.value == id) stop()
        images?.delete(chat(id)?.messages.orEmpty().flatMap { it.imageIds.orEmpty() })
        save(_history.value.delete(id))
        if (_open.value == id) _open.value = null
    }

    fun newChat(title: String, firstMessage: String? = null): String {
        val messages = firstMessage?.let { listOf(AIChatMessage(role = "user", text = it, createdAt = now())) }.orEmpty()
        val chat = AIChat(title = title, updatedAt = now(), messages = messages)
        save(_history.value.upsert(chat))
        return chat.id
    }

    fun start(context: AIContext) {
        val id = newChat(context.title, AIPrompts.contextMessage(context))
        _open.value = id
        show()
        answer(id)
    }

    fun send(message: String, chatId: String, pictures: List<ByteArray> = emptyList()) {
        val chat = chat(chatId) ?: return
        if (_streaming.value != null) return
        val ids = pictures.mapNotNull { images?.save(it) }.ifEmpty { null }
        val added = chat.copy(
            messages = chat.messages + AIChatMessage(role = "user", text = message, createdAt = now(), imageIds = ids),
            updatedAt = now(),
        )
        save(_history.value.upsert(added))
        answer(chatId)
    }

    fun regenerate(chatId: String) {
        val chat = chat(chatId) ?: return
        if (_streaming.value != null) return
        val trimmed = if (chat.messages.lastOrNull()?.role == "assistant") chat.messages.dropLast(1) else chat.messages
        save(_history.value.upsert(chat.copy(messages = trimmed)))
        answer(chatId)
    }

    fun stop() { job?.cancel() }

    private fun answer(chatId: String) {
        val config = settings.config.value
        if (!config.isConfigured) { _failure.value = text(AiMessageId.CHOOSE_FIRST); return }
        if (config.budget == AIBudgetState.REACHED) { _failure.value = text(AiMessageId.LIMIT_REACHED); return }
        _failure.value = null
        _streaming.value = chatId
        job = scope.launch { run(chatId, config) }
    }

    private suspend fun run(chatId: String, config: AiConfig) {
        val chat = chat(chatId) ?: run { _streaming.value = null; return }
        var reply = AIChatMessage(role = "assistant", text = "", createdAt = now())
        try {
            val request = makeRequest(chat.messages, config)
            val format = AIProviderConfig(config.providerId, config.model).format
            AiHttp.stream(request, format).collect { event ->
                reply = apply(event, reply)
                publish(chatId, reply)
            }
        } catch (cancelled: CancellationException) {
            Unit
        } catch (failure: Exception) {
            _failure.value = failure.message ?: failure::class.simpleName
        } finally {
            _streaming.value = null
            finish(chatId, reply)
        }
    }

    private fun apply(event: AIStreamEvent, reply: AIChatMessage): AIChatMessage = when (event) {
        is AIStreamEvent.Text -> reply.copy(text = reply.text + event.text)
        is AIStreamEvent.Usage -> {
            settings.record(event.input, event.output)
            reply.copy(inputTokens = event.input, outputTokens = event.output)
        }
        else -> reply
    }

    private fun publish(chatId: String, reply: AIChatMessage) {
        val chat = chat(chatId) ?: return
        val kept = chat.messages.filter { it.id != reply.id } + reply
        _history.value = _history.value.upsert(chat.copy(messages = kept, updatedAt = now()))
    }

    private fun finish(chatId: String, reply: AIChatMessage) {
        val chat = chat(chatId) ?: return
        val kept = chat.messages.filter { it.id != reply.id || reply.text.isNotEmpty() }
        save(_history.value.upsert(chat.copy(messages = kept)))
    }

    private suspend fun makeRequest(messages: List<AIChatMessage>, config: AiConfig): AIHttpRequest {
        val base = if (config.isLocal) localBaseUrl(config) else null
        val provider = if (base != null) AIProviderConfig(config.providerId, config.model, base)
        else AIProviderConfig(config.providerId, config.model)
        val wire = messages.map {
            AIMessage(if (it.role == "assistant") AIRole.ASSISTANT else AIRole.USER, it.text, images?.wire(it.imageIds).orEmpty())
        }
        return AIRequestBuilder.build(provider, settings.apiKey(config.providerId), AIPrompts.systemPrompt(languageName()), wire)
    }

    private fun save(history: AIChatHistory) {
        _history.value = history
        file.save(history)
    }

    private fun languageName(): String = Locale.getDefault().getDisplayLanguage(Locale.ENGLISH).ifEmpty { "English" }
}
