package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.app.ui.aiGlass

/** The words of one screen's bar */
data class PendingChangesText(val apply: String, val note: String, val cancel: String)

/** Floating glass bar that applies or drops edits */
@Composable
fun PendingChangesBar(visible: Boolean, text: PendingChangesText, onApply: () -> Unit, onRevert: () -> Unit) {
    AnimatedVisibility(
        visible = visible,
        enter = slideInVertically { it } + fadeIn(),
        exit = slideOutVertically { it } + fadeOut(),
    ) {
        val shape = RoundedCornerShape(26.dp)
        Column(
            Modifier.widthIn(max = 460.dp).fillMaxWidth().shadow(14.dp, shape).aiGlass(shape)
                .padding(horizontal = 14.dp, vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton(onClick = onRevert) { Text(text.cancel, color = Gryonix.colors.label) }
                Button(
                    onClick = onApply,
                    modifier = Modifier.weight(1f),
                    colors = ButtonDefaults.buttonColors(containerColor = Gryonix.colors.accent),
                ) { Text(text.apply, maxLines = 1) }
            }
            if (text.note.isNotEmpty()) Text(
                text.note,
                style = MaterialTheme.typography.labelSmall,
                color = Gryonix.colors.secondaryLabel,
                textAlign = TextAlign.Center,
            )
        }
    }
}

/** The bar under rows whose edits wait */
@Composable
fun ApplyPendingBar(visible: Boolean, apply: String, cancel: String, onApply: () -> Unit, onRevert: () -> Unit) {
    Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), contentAlignment = Alignment.Center) {
        PendingChangesBar(visible, PendingChangesText(apply, "", cancel), onApply, onRevert)
    }
}
