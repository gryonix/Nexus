package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IOSSheet(
    title: String,
    onClose: () -> Unit,
    /** The word on the left */
    closeLabel: String,
    modifier: Modifier = Modifier,
    /** The optional action on the right — saving, adding, applying */
    action: SheetAction? = null,
    scrollable: Boolean = true,
    /** Replaces [action] with any control, such as a menu */
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = Gryonix.colors
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onClose,
        sheetState = state,
        modifier = modifier,
        containerColor = colors.groupedBackground,
        shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp),
        dragHandle = null,
    ) {
        SheetBar(title = title, closeLabel = closeLabel, onClose = onClose, action = action, trailing = trailing)
        Column(
            Modifier
                .fillMaxWidth()
                .then(if (scrollable) Modifier.verticalScroll(rememberScrollState()) else Modifier)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(Metrics.sectionGap),
            content = content,
        )
    }
}

/** The button on the right of a sheet's bar */
data class SheetAction(
    val title: String,
    val enabled: Boolean = true,
    val destructive: Boolean = false,
    val onSelect: () -> Unit,
)

@Composable
private fun SheetBar(
    title: String,
    closeLabel: String,
    onClose: () -> Unit,
    action: SheetAction?,
    trailing: (@Composable () -> Unit)? = null,
) {
    val colors = Gryonix.colors
    Box(
        Modifier
            .fillMaxWidth()
            .background(colors.barBackground)
            .height(52.dp),
    ) {
        Text(
            title,
            style = MaterialTheme.typography.titleMedium,
            color = colors.label,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .align(Alignment.Center)
                .padding(horizontal = 88.dp),
        )
        PlainButton(
            text = closeLabel,
            onClick = onClose,
            modifier = Modifier.align(Alignment.CenterStart).padding(start = 4.dp),
        )
        if (trailing != null) {
            Box(Modifier.align(Alignment.CenterEnd).padding(end = 4.dp)) { trailing() }
        } else if (action != null) {
            PlainButton(
                text = action.title,
                onClick = action.onSelect,
                enabled = action.enabled,
                danger = action.destructive,
                modifier = Modifier.align(Alignment.CenterEnd).padding(end = 4.dp),
            )
        }
    }
    Separator()
    Box(Modifier.fillMaxWidth().height(16.dp))
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IOSFullSheet(
    title: String,
    onClose: () -> Unit,
    closeLabel: String,
    action: SheetAction? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = Gryonix.colors
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onClose,
        sheetState = state,
        containerColor = colors.groupedBackground,
        shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp),
        dragHandle = null,
    ) {
        SheetBar(title = title, closeLabel = closeLabel, onClose = onClose, action = action)
        Column(Modifier.fillMaxWidth().fillMaxHeight(), content = content)
    }
}
