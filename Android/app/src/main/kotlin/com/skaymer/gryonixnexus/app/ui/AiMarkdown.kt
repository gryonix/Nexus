package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.aiassistant.MarkdownBlock
import com.skaymer.gryonixnexus.aiassistant.MarkdownBlocks
import com.skaymer.gryonixnexus.app.ui.design.Gryonix

@Composable
fun AiMarkdown(text: String, modifier: Modifier = Modifier) {
    SelectionContainer {
        Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            MarkdownBlocks.parse(text).forEach { Block(it) }
        }
    }
}

@Composable
private fun Block(block: MarkdownBlock) {
    when (block) {
        is MarkdownBlock.Paragraph -> Text(inline(block.text), style = MaterialTheme.typography.bodyMedium)
        is MarkdownBlock.Heading -> Text(inline(block.text), style = MaterialTheme.typography.titleSmall)
        is MarkdownBlock.Quote -> Text(inline(block.text), color = Gryonix.colors.secondaryLabel)
        is MarkdownBlock.Bullets -> block.items.forEach { Item("•", it) }
        is MarkdownBlock.Numbered -> block.items.forEachIndexed { index, item -> Item("${index + 1}.", item) }
        is MarkdownBlock.Code -> AiCodeBlock(block.text)
    }
}

@Composable
private fun Item(marker: String, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(marker, style = MaterialTheme.typography.bodyMedium)
        Text(inline(text), style = MaterialTheme.typography.bodyMedium)
    }
}

/** A suggested command: copy it, never run it. */
@Composable
fun AiCodeBlock(code: String) {
    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            code,
            fontFamily = FontFamily.Monospace,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(Gryonix.colors.trackFill)
                .horizontalScroll(rememberScrollState())
                .padding(8.dp),
        )
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.ai_check_before),
                style = MaterialTheme.typography.labelSmall,
                color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = { clipboard.setText(AnnotatedString(code)); copied = true }) {
                Text(stringResource(if (copied) R.string.ai_copied else R.string.ai_copy))
            }
        }
    }
}

private fun inline(text: String): AnnotatedString = buildAnnotatedString {
    var index = 0
    while (index < text.length) {
        val bold = text.startsWith("**", index)
        val code = text[index] == '`'
        val marker = if (bold) "**" else if (code) "`" else null
        val end = marker?.let { text.indexOf(it, index + it.length) } ?: -1
        if (marker == null || end < 0) {
            append(text[index])
            index++
            continue
        }
        val body = text.substring(index + marker.length, end)
        val style = if (bold) SpanStyle(fontWeight = FontWeight.Bold) else SpanStyle(fontFamily = FontFamily.Monospace)
        withStyle(style) { append(body) }
        index = end + marker.length
    }
}
