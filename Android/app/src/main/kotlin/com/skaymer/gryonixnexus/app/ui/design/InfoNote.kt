package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R

@Composable
fun InfoNoteButton(
    title: String,
    note: String,
    modifier: Modifier = Modifier,
) {
    var showing by rememberSaveable { mutableStateOf(false) }
    Icon(
        Icons.Outlined.Info,
        contentDescription = stringResource(R.string.info_note_more),
        tint = Gryonix.colors.secondaryLabel,
        modifier = modifier
            .size(InfoNoteMetrics.target)
            .clip(CircleShape)
            .clickable { showing = true }
            .padding(InfoNoteMetrics.inset),
    )
    if (showing) {
        InfoNoteSheet(title = title, note = note, onClose = { showing = false })
    }
}

@Composable
fun InfoSectionHeader(
    title: String,
    note: String,
    modifier: Modifier = Modifier,
    /** Drawn as a small circular arrow left of the "i" */
    onRefresh: (() -> Unit)? = null,
    refreshDescription: String = "",
    refreshing: Boolean = false,
) {
    Row(
        modifier
            .fillMaxWidth()
            .padding(
                start = Metrics.listInset + 4.dp,
                end = Metrics.listInset,
                bottom = 2.dp,
            ),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            title.uppercase(),
            style = MaterialTheme.typography.bodySmall,
            color = Gryonix.colors.secondaryLabel,
            modifier = Modifier.weight(1f),
        )
        if (onRefresh != null) {
            RefreshButton(
                contentDescription = refreshDescription,
                onClick = onRefresh,
                busy = refreshing,
            )
        }
        InfoNoteButton(title = title, note = note)
    }
}

/** The note itself */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun InfoNoteSheet(
    title: String,
    note: String,
    onClose: () -> Unit,
) {
    val colors = Gryonix.colors
    val state = rememberModalBottomSheetState()
    ModalBottomSheet(
        onDismissRequest = onClose,
        sheetState = state,
        containerColor = colors.groupedBackground,
        shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(start = 20.dp, end = 20.dp, bottom = 40.dp),
        ) {
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                color = colors.label,
                modifier = Modifier.padding(bottom = 12.dp),
            )
            Text(
                note,
                style = MaterialTheme.typography.bodyMedium,
                color = colors.label,
            )
        }
    }
}

internal object InfoNoteMetrics {
    val target = 36.dp
    val inset = 8.dp
}
