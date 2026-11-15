package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.shell.ServerSection
import com.skaymer.gryonixnexus.app.shell.ServerSectionSettings
import com.skaymer.gryonixnexus.app.ui.design.Gryonix

@Composable
fun ServerSectionsStrip(
    sections: List<ServerSection>,
    available: List<ServerSection>,
    current: ServerSection,
    settings: ServerSectionSettings,
    deploymentID: String,
    onSelect: (ServerSection) -> Unit,
    onArrange: () -> Unit,
    icons: Boolean = false,
    tunnelActive: Boolean = false,
) {
    if (sections.size <= 1) return
    var menuFor by remember { mutableStateOf<ServerSection?>(null) }

    Box(Modifier.fillMaxWidth().background(Gryonix.colors.groupedBackground)) {
        val selectedIndex = sections.indexOf(current).coerceAtLeast(0)
        SectionCapsule(sections.size, selectedIndex, evenly = icons) { index ->
            val section = sections[index]
            SectionTab(
                title = stringResource(section.titleRes),
                icon = if (icons) section.icon(tunnelActive) else null,
                selected = section == current,
                onClick = { onSelect(section) },
                onLongClick = { menuFor = section },
            )
        }
        val held = menuFor
        DropdownMenu(expanded = held != null, onDismissRequest = { menuFor = null }) {
            if (held != null && settings.canHide(held, deploymentID, available)) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.section_hide)) },
                    onClick = {
                        menuFor = null
                        settings.setVisible(false, held, deploymentID, available)
                    },
                )
            }
            DropdownMenuItem(
                text = { Text(stringResource(R.string.section_arrange)) },
                onClick = {
                    menuFor = null
                    onArrange()
                },
            )
        }
    }
}

/** The rounded strip the sections sit in, as on iOS */
@Composable
private fun SectionCapsule(count: Int, selected: Int, evenly: Boolean, tab: @Composable (Int) -> Unit) {
    val colors = Gryonix.colors
    val shape = RoundedCornerShape(percent = 50)
    val strip = Modifier
        .padding(horizontal = 16.dp, vertical = 8.dp)
        .fillMaxWidth()
        .shadow(1.dp, shape, ambientColor = colors.separator, spotColor = colors.separator)
        .clip(shape)
        .background(colors.cardBackground.copy(alpha = 0.7f))
        .border(0.5.dp, colors.separator.copy(alpha = 0.2f), shape)
        .padding(4.dp)
    if (evenly) {
        Row(strip) { repeat(count) { index -> Box(Modifier.weight(1f)) { tab(index) } } }
        return
    }
    val list = rememberLazyListState()
    LaunchedEffect(selected) { list.animateScrollToItem((selected - 1).coerceAtLeast(0)) }
    LazyRow(strip, state = list) { items(count) { index -> tab(index) } }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SectionTab(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector?,
    selected: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val colors = Gryonix.colors
    val shape = RoundedCornerShape(percent = 50)
    Box(
        Modifier
            .fillMaxWidth()
            .height(40.dp)
            .then(if (selected) Modifier.shadow(2.dp, shape) else Modifier)
            .clip(shape)
            .background(if (selected) colors.cardBackground else Color.Transparent)
            .combinedClickable(role = Role.Tab, onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        val tint = if (selected) colors.label else colors.secondaryLabel
        if (icon != null) {
            Icon(icon, contentDescription = title, tint = if (selected) colors.accent else tint, modifier = Modifier.size(22.dp))
        } else {
            Text(
                title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                color = tint,
                maxLines = 1,
            )
        }
    }
}
