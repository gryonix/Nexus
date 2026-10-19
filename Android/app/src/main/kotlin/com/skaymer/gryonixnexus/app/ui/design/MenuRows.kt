package com.skaymer.gryonixnexus.app.ui.design

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** The chevron that says a row opens a popup menu */
@Composable
fun PopupChevron() {
    Icon(
        Icons.Filled.UnfoldMore,
        contentDescription = null,
        tint = Gryonix.colors.tertiaryLabel,
        modifier = Modifier.size(18.dp),
    )
}

/** A value row whose tap opens a popup menu */
@Composable
fun MenuValueRow(
    title: String,
    value: String,
    enabled: Boolean = true,
    showDivider: Boolean = true,
    menu: @Composable ColumnScope.(close: () -> Unit) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        ValueRow(
            title = title,
            value = value,
            onClick = { if (enabled) open = true },
            showDivider = showDivider,
            chevron = { PopupChevron() },
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            menu { open = false }
        }
    }
}

/** A small heading between groups of menu items */
@Composable
fun MenuHeader(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelSmall,
        color = Gryonix.colors.secondaryLabel,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
    )
}

/** A menu item ticked when it is the current choice */
@Composable
fun MenuCheckItem(text: String, checked: Boolean, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(text) },
        onClick = onClick,
        leadingIcon = {
            if (checked) Icon(Icons.Filled.Check, contentDescription = null) else Box(Modifier.size(24.dp))
        },
    )
}
