package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.window.DialogProperties
import com.skaymer.gryonixnexus.R

/** One button on an alert */
@Immutable
data class AlertAction(
    val title: String,
    /** Red */
    val destructive: Boolean = false,
    /** Semibold */
    val preferred: Boolean = false,
    val enabled: Boolean = true,
    val onSelect: () -> Unit,
)

@Composable
fun IOSAlert(
    title: String,
    onDismiss: () -> Unit,
    actions: List<AlertAction>,
    message: String? = null,
    content: (@Composable ColumnScope.() -> Unit)? = null,
) {
    val colors = Gryonix.colors
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Column(
            Modifier
                .width(AlertWidth)
                .clip(RoundedCornerShape(AlertCorner))
                .background(colors.cardBackground),
        ) {
            Column(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    title,
                    style = MaterialTheme.typography.titleMedium,
                    color = colors.label,
                    textAlign = TextAlign.Center,
                )
                if (message != null) {
                    Text(
                        message,
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.label,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
                if (content != null) {
                    Column(
                        Modifier.fillMaxWidth().padding(top = 14.dp),
                        content = content,
                    )
                }
            }
            AlertButtons(actions)
        }
    }
}

val AlertWidth = 270.dp
private val AlertCorner = 14.dp
private val AlertButtonHeight = 44.dp

/** The buttons, and the hairlines between them */
@Composable
private fun AlertButtons(actions: List<AlertAction>) {
    if (actions.isEmpty()) return
    Separator()
    if (actions.size == 2) {
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
            AlertButton(actions[0], Modifier.weight(1f))
            Box(
                Modifier
                    .width(0.5.dp)
                    .fillMaxHeight()
                    .background(Gryonix.colors.separator),
            )
            AlertButton(actions[1], Modifier.weight(1f))
        }
    } else {
        actions.forEachIndexed { index, action ->
            AlertButton(action, Modifier.fillMaxWidth())
            if (index != actions.lastIndex) Separator()
        }
    }
}

@Composable
private fun AlertButton(action: AlertAction, modifier: Modifier) {
    val colors = Gryonix.colors
    Box(
        modifier
            .then(
                if (action.enabled) Modifier.clickable(onClick = action.onSelect) else Modifier
            )
            .defaultMinSize(minHeight = AlertButtonHeight)
            .padding(horizontal = 8.dp, vertical = 11.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            action.title,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = if (action.preferred) FontWeight.SemiBold else FontWeight.Normal,
            color = when {
                !action.enabled -> colors.tertiaryLabel
                action.destructive -> colors.danger
                else -> colors.accent
            },
            textAlign = TextAlign.Center,
        )
    }
}

/** A confirmation: a question, and the two answers to it */
@Composable
fun ConfirmAlert(
    title: String,
    confirm: String,
    onConfirm: () -> Unit,
    onCancel: () -> Unit,
    message: String? = null,
    cancel: String = stringResource(R.string.access_cancel),
    destructive: Boolean = false,
) {
    IOSAlert(
        title = title,
        message = message,
        onDismiss = onCancel,
        actions = listOf(
            AlertAction(cancel, onSelect = onCancel),
            AlertAction(
                confirm,
                destructive = destructive,
                preferred = !destructive,
                onSelect = onConfirm,
            ),
        ),
    )
}

/** A grouped plate sized for the inside of an alert */
@Composable
fun AlertFields(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(Gryonix.colors.groupedBackground),
    ) {
        CompositionLocalProvider(LocalRowDividerInset provides 12.dp) {
            Column(Modifier.fillMaxWidth(), content = content)
        }
    }
}
