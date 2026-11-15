package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R

/** True while fields sit on a sheet */
internal val LocalOnSheet = compositionLocalOf { false }

private fun List<AlertAction>.cancelling() = firstOrNull { !it.preferred && !it.destructive }

private fun List<AlertAction>.confirming(): AlertAction? =
    firstOrNull { it.preferred } ?: lastOrNull { it !== cancelling() }

/** A form sheet; its main action waits in the bar */
@Composable
fun FormSheet(
    title: String,
    onDismiss: () -> Unit,
    actions: List<AlertAction>,
    message: String? = null,
    content: (@Composable ColumnScope.() -> Unit)? = null,
) {
    val cancel = actions.cancelling()
    val main = actions.confirming()
    val extras = actions.filter { it !== cancel && it !== main }
    IOSSheet(
        title = title,
        onClose = onDismiss,
        closeLabel = stringResource(R.string.close),
        bottomBar = {
            if (main != null) ApplyPendingBar(
                visible = main.enabled,
                apply = main.title,
                cancel = cancel?.title ?: stringResource(R.string.pending_changes_cancel),
                onApply = main.onSelect,
                onRevert = cancel?.onSelect ?: onDismiss,
            )
        },
    ) {
        message?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }
        CompositionLocalProvider(LocalOnSheet provides true) {
            Column16(content)
        }
        if (extras.isNotEmpty()) GroupedSection {
            extras.forEachIndexed { index, action ->
                ActionRow(action.title, action.onSelect, enabled = action.enabled, danger = action.destructive,
                    showDivider = index < extras.lastIndex)
            }
        }
    }
}

@Composable
private fun Column16(content: (@Composable ColumnScope.() -> Unit)?) {
    androidx.compose.foundation.layout.Column(
        Modifier.padding(horizontal = 16.dp),
        content = content ?: {},
    )
}
