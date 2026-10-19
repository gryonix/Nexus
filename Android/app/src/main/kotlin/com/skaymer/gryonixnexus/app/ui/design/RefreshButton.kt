package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp

/** Small circular arrow that re-reads one row's state */
@Composable
fun RefreshButton(
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    busy: Boolean = false,
) {
    Box(
        modifier
            .size(InfoNoteMetrics.target)
            .clip(CircleShape)
            .clickable(enabled = !busy, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (busy) {
            CircularProgressIndicator(
                Modifier.size(16.dp),
                strokeWidth = 2.dp,
                color = Gryonix.colors.tertiaryLabel,
            )
        } else {
            Icon(
                Icons.Filled.Refresh,
                contentDescription = contentDescription,
                tint = Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(InfoNoteMetrics.inset),
            )
        }
    }
}
