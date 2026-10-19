package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.Gryonix

/** Blocks the screen until the server answers */
@Composable
fun PleaseWaitDialog(visible: Boolean, detail: String = "") {
    if (!visible) return
    Dialog(
        onDismissRequest = {},
        properties = DialogProperties(dismissOnBackPress = false, dismissOnClickOutside = false),
    ) {
        Column(
            Modifier
                .widthIn(max = 300.dp)
                .background(Gryonix.colors.cardBackground, RoundedCornerShape(22.dp))
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            CircularProgressIndicator(color = Gryonix.colors.tertiaryLabel)
            Text(
                stringResource(R.string.please_wait_title),
                style = MaterialTheme.typography.titleMedium,
                color = Gryonix.colors.label,
            )
            Text(
                stringResource(R.string.please_wait_note),
                style = MaterialTheme.typography.bodyMedium,
                color = Gryonix.colors.secondaryLabel,
                textAlign = TextAlign.Center,
            )
            if (detail.isNotEmpty()) {
                Text(
                    detail,
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.secondaryLabel,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}
