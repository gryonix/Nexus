package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.AlertCard
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert

/** A tapped alert with its advice, over the server */
@Composable
fun AlertCardDialog(card: AlertCard, onClose: () -> Unit) {
    IOSAlert(
        title = card.title,
        message = card.body.ifEmpty { null },
        onDismiss = onClose,
        actions = listOf(AlertAction(stringResource(R.string.close), preferred = true, onSelect = onClose)),
    ) {
        val advice = card.advice ?: return@IOSAlert
        Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(stringResource(R.string.refusal_what_to_do), fontWeight = FontWeight.SemiBold, color = Gryonix.colors.label)
            val text = card.screen?.let { stringResource(advice, stringResource(it)) } ?: stringResource(advice)
            Text(text, style = MaterialTheme.typography.bodyMedium, color = Gryonix.colors.secondaryLabel)
        }
    }
}
