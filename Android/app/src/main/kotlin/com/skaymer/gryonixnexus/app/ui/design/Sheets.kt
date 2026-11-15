package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.layout.width
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.clickable
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IOSSheet(
    title: String,
    onClose: () -> Unit,
    /** Read aloud for the close button */
    closeLabel: String,
    modifier: Modifier = Modifier,
    /** The optional action on the right — saving, adding, applying */
    action: SheetAction? = null,
    scrollable: Boolean = true,
    /** Replaces [action] with any control, such as a menu */
    trailing: (@Composable () -> Unit)? = null,
    /** Floats over the bottom of the content */
    bottomBar: (@Composable () -> Unit)? = null,
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
        Box {
            Column(
                Modifier
                    .fillMaxWidth()
                    .then(if (scrollable) Modifier.verticalScroll(rememberScrollState()) else Modifier)
                    .padding(bottom = if (bottomBar == null) 32.dp else BOTTOM_BAR_ROOM),
                verticalArrangement = Arrangement.spacedBy(Metrics.sectionGap),
                content = content,
            )
            if (bottomBar != null) {
                Box(Modifier.align(Alignment.BottomCenter).padding(horizontal = 16.dp, vertical = 12.dp)) { bottomBar() }
            }
        }
    }
}

private val BOTTOM_BAR_ROOM = 132.dp

/** The button on the right of a sheet's bar */
data class SheetAction(
    val title: String,
    val enabled: Boolean = true,
    val destructive: Boolean = false,
    val onSelect: () -> Unit,
)

@Composable
internal fun SheetBar(
    title: String,
    closeLabel: String,
    onClose: () -> Unit,
    action: SheetAction?,
    trailing: (@Composable () -> Unit)? = null,
) {
    val colors = Gryonix.colors
    Row(
        Modifier.fillMaxWidth().background(colors.groupedBackground).height(68.dp).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SheetCapsule(text = closeLabel, onClick = onClose, color = colors.label)
        Text(
            title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = colors.label,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
            modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
        )
        SheetBarEnd(action, trailing)
    }
}

@Composable
private fun SheetBarEnd(action: SheetAction?, trailing: (@Composable () -> Unit)?) {
    if (trailing == null && action == null) {
        Box(Modifier.width(SIDE_ROOM))
    } else if (trailing != null) {
        Box(Modifier.padding(end = 4.dp)) { trailing() }
    } else if (action != null) {
        SheetCapsule(
            text = action.title,
            onClick = action.onSelect,
            enabled = action.enabled,
            color = if (action.destructive) Gryonix.colors.danger else Gryonix.colors.accent,
        )
    }
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

/** Keeps a lone title in the middle */
private val SIDE_ROOM = 72.dp

/** A round-ended button in a sheet's header, as on iOS */
@Composable
private fun SheetCapsule(text: String, onClick: () -> Unit, color: Color, enabled: Boolean = true) {
    val colors = Gryonix.colors
    Text(
        text,
        style = MaterialTheme.typography.bodyLarge,
        fontWeight = FontWeight.Medium,
        color = if (enabled) color else colors.tertiaryLabel,
        maxLines = 1,
        modifier = Modifier
            .shadow(1.dp, CircleShape, ambientColor = colors.separator, spotColor = colors.separator)
            .clip(CircleShape)
            .background(colors.cardBackground)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 10.dp),
    )
}
