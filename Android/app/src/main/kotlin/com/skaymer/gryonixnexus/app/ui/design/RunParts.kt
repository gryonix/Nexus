package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp

/** A spinner beside what a running job is doing. */
@Composable
fun RunProgressRow(text: String) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CircularProgressIndicator(
            Modifier.size(16.dp),
            strokeWidth = 2.dp,
            color = Gryonix.colors.tertiaryLabel,
        )
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            color = Gryonix.colors.secondaryLabel,
        )
    }
}

/** A job's output, selectable and scrollable; nothing when empty. */
@Composable
fun RunLog(log: String) {
    if (log.isEmpty()) return
    SelectionContainer {
        Column(Modifier.heightIn(max = 240.dp).verticalScroll(rememberScrollState())) {
            Text(
                log,
                style = MaterialTheme.typography.labelSmall,
                fontFamily = FontFamily.Monospace,
                color = Gryonix.colors.secondaryLabel,
            )
        }
    }
}
