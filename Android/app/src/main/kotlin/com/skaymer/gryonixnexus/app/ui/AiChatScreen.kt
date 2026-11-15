package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.aiassistant.AIBudgetState
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.ui.design.AppTopBar
import com.skaymer.gryonixnexus.app.ui.design.Gryonix

/** One AI conversation: bubbles, typing dots and a floating input */
@Composable
fun AiChatScreen(chatId: String, onBack: () -> Unit) {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val store = app.aiChats
    val history by store.history.collectAsState()
    val streaming by store.streamingChatId.collectAsState()
    val failure by store.failure.collectAsState()
    val config by app.aiSettings.config.collectAsState()
    val messages = history.chats.firstOrNull { it.id == chatId }?.messages.orEmpty()
    val isStreaming = streaming == chatId
    var draft by remember { mutableStateOf("") }
    var attachments by remember { mutableStateOf(emptyList<ByteArray>()) }
    val send: (String) -> Unit = { text ->
        if ((text.isNotBlank() || attachments.isNotEmpty()) && streaming == null) {
            store.send(text.trim(), chatId, attachments)
            draft = ""
            attachments = emptyList()
        }
    }
    Box(Modifier.fillMaxSize()) {
        AiChatBackdrop()
        ChatColumn(app, chatId, messages, isStreaming, !config.isLocal, streaming == null, draft, { draft = it },
            attachments, { attachments = it }, failure, config.budget, send, onBack)
    }
}

@Composable
private fun ChatColumn(
    app: GryonixApplication,
    chatId: String,
    messages: List<com.skaymer.gryonixnexus.aiassistant.AIChatMessage>,
    isStreaming: Boolean,
    showsTokens: Boolean,
    idle: Boolean,
    draft: String,
    onDraft: (String) -> Unit,
    attachments: List<ByteArray>,
    onAttachments: (List<ByteArray>) -> Unit,
    failure: String?,
    budget: AIBudgetState,
    send: (String) -> Unit,
    onBack: () -> Unit,
) {
    val store = app.aiChats
    val history by store.history.collectAsState()
    Column(Modifier.fillMaxSize().imePadding()) {
        AppTopBar(history.chats.firstOrNull { it.id == chatId }?.title.orEmpty(), onBack = onBack)
        if (messages.isEmpty()) {
            AiChatWelcome(Modifier.weight(1f)) { send(it) }
        } else {
            ChatThread(Modifier.weight(1f), messages, isStreaming, showsTokens, idle, app.aiImages::bytes,
                { store.regenerate(chatId) }) { Banner(failure, budget) }
        }
        AiChatInputBar(draft, onDraft, attachments, onAttachments, isStreaming, onStop = store::stop) { send(draft) }
    }
}

@Composable
private fun ChatThread(
    modifier: Modifier,
    messages: List<com.skaymer.gryonixnexus.aiassistant.AIChatMessage>,
    isStreaming: Boolean,
    showsTokens: Boolean,
    idle: Boolean,
    picture: (String) -> ByteArray?,
    regenerate: () -> Unit,
    banner: @Composable () -> Unit,
) {
    val list = rememberLazyListState()
    val typing = isStreaming && messages.lastOrNull()?.role != "assistant"
    LaunchedEffect(messages.size, messages.lastOrNull()?.text?.length, typing) {
        list.animateScrollToItem(messages.size + 1)
    }
    LazyColumn(
        modifier.fillMaxWidth(), state = list,
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        items(messages, key = { it.id }) { message ->
            val last = message.id == messages.last().id
            AiMessageBubble(message, showsTokens, last && idle && message.role == "assistant", picture, regenerate)
        }
        item { if (typing) AiTypingBubble() }
        item { banner() }
    }
}

@Composable
private fun Banner(failure: String?, budget: AIBudgetState) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        failure?.let { Notice(it) }
        if (budget == AIBudgetState.NEAR_LIMIT) Notice(stringResource(R.string.ai_near_limit))
        if (budget == AIBudgetState.REACHED) Notice(stringResource(R.string.ai_limit_reached))
    }
}

@Composable
private fun Notice(text: String) {
    Text(
        text, color = Gryonix.colors.warning, style = MaterialTheme.typography.bodySmall,
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
            .background(Gryonix.colors.warning.copy(alpha = 0.12f)).padding(10.dp),
    )
}
