package com.skaymer.gryonixnexus.app.ui

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.StartOffset
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.aiassistant.AIChatMessage
import com.skaymer.gryonixnexus.app.ui.design.Gryonix

private val BigCorner = 18.dp
private val SmallCorner = 6.dp

/** Bubble with a tighter corner toward its sender */
internal fun bubbleShape(fromUser: Boolean) = RoundedCornerShape(
    topStart = if (fromUser) BigCorner else SmallCorner,
    topEnd = if (fromUser) SmallCorner else BigCorner,
    bottomEnd = BigCorner,
    bottomStart = BigCorner,
)

/** A user or assistant message bubble */
@Composable
internal fun AiMessageBubble(
    message: AIChatMessage,
    showsTokens: Boolean,
    canRegenerate: Boolean,
    picture: (String) -> ByteArray?,
    regenerate: () -> Unit,
) {
    if (message.role == "user") UserBubble(message, picture) else AssistantBubble(message, showsTokens, canRegenerate, regenerate)
}

@Composable
private fun UserBubble(message: AIChatMessage, picture: (String) -> ByteArray?) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
        Spacer(Modifier.size(48.dp))
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            message.imageIds?.takeIf { it.isNotEmpty() }?.let { ids -> MessagePictures(ids, picture) }
            if (message.text.isNotEmpty()) {
                SelectionContainer {
                    Text(
                        message.text, color = Color.White, style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.aiGlass(bubbleShape(true), Gryonix.colors.accent)
                            .padding(horizontal = 14.dp, vertical = 10.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun MessagePictures(ids: List<String>, picture: (String) -> ByteArray?) {
    val side = if (ids.size == 1) 200.dp else 96.dp
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        ids.forEach { id ->
            val bytes = androidx.compose.runtime.remember(id) { picture(id) }
            if (bytes != null) AiPicture(bytes, Modifier.size(side).clip(RoundedCornerShape(16.dp)))
        }
    }
}

@Composable
private fun AssistantBubble(message: AIChatMessage, showsTokens: Boolean, canRegenerate: Boolean, regenerate: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(end = 24.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        AiAvatar()
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            SelectionContainer {
                Box(Modifier.aiGlass(bubbleShape(false)).padding(horizontal = 14.dp, vertical = 10.dp)) {
                    AiMarkdown(message.text)
                }
            }
            MessageActions(message, showsTokens, canRegenerate, regenerate)
        }
    }
}

@Composable
private fun MessageActions(message: AIChatMessage, showsTokens: Boolean, canRegenerate: Boolean, regenerate: () -> Unit) {
    val clipboard = LocalClipboardManager.current
    val tint = Gryonix.colors.secondaryLabel
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { clipboard.setText(AnnotatedString(message.text)) }, modifier = Modifier.size(32.dp)) {
            Icon(Icons.Outlined.ContentCopy, stringResource(R.string.ai_copy), tint = tint, modifier = Modifier.size(16.dp))
        }
        if (canRegenerate) {
            IconButton(onClick = regenerate, modifier = Modifier.size(32.dp)) {
                Icon(Icons.Outlined.Refresh, stringResource(R.string.ai_regenerate), tint = tint, modifier = Modifier.size(18.dp))
            }
        }
        val input = message.inputTokens
        val output = message.outputTokens
        if (showsTokens && input != null && output != null) {
            Text(stringResource(R.string.ai_tokens_n, input + output), style = MaterialTheme.typography.labelSmall, color = tint)
        }
    }
}

/** Round sparkle badge beside the assistant's messages */
@Composable
internal fun AiAvatar(size: Dp = 30.dp) {
    Box(
        Modifier.size(size).clip(CircleShape)
            .background(Brush.linearGradient(listOf(Gryonix.colors.accent, Color(0xFFAF52DE)))),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Filled.AutoAwesome, null, tint = Color.White, modifier = Modifier.size(size * 0.5f))
    }
}

/** Three pulsing dots while the answer is on its way */
@Composable
internal fun AiTypingBubble() {
    val transition = rememberInfiniteTransition(label = "typing")
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        AiAvatar()
        Row(
            Modifier.aiGlass(bubbleShape(false)).padding(horizontal = 16.dp, vertical = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            repeat(3) { index ->
                val alpha by transition.animateFloat(
                    0.3f, 1f,
                    infiniteRepeatable(tween(600), RepeatMode.Reverse, StartOffset(index * 200)),
                    label = "dot$index",
                )
                Box(Modifier.size(7.dp).alpha(alpha).clip(CircleShape).background(Gryonix.colors.secondaryLabel))
            }
        }
    }
}

/** Empty chat: greeting and ready-made questions */
@Composable
internal fun AiChatWelcome(modifier: Modifier, ask: (String) -> Unit) {
    val suggestions = listOf(
        stringResource(R.string.ai_suggest_unreachable),
        stringResource(R.string.ai_suggest_disk),
        stringResource(R.string.ai_suggest_attention),
        stringResource(R.string.ai_suggest_safer),
    )
    Column(
        modifier.fillMaxWidth().padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
    ) {
        AiAvatar(56.dp)
        Text(stringResource(R.string.ai_welcome_title), style = MaterialTheme.typography.titleLarge, color = Gryonix.colors.label)
        Text(stringResource(R.string.ai_welcome_body), style = MaterialTheme.typography.bodyMedium,
            color = Gryonix.colors.secondaryLabel, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        Column(Modifier.widthIn(max = 520.dp).padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            suggestions.forEach { text ->
                Text(
                    text, style = MaterialTheme.typography.bodyMedium, color = Gryonix.colors.label,
                    modifier = Modifier.fillMaxWidth().aiGlass(RoundedCornerShape(16.dp))
                        .clickable { ask(text) }
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                )
            }
        }
    }
}
