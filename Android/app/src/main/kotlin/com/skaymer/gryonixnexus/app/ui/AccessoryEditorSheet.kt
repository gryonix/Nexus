package com.skaymer.gryonixnexus.app.ui

import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.terminal.AccessoryCatalog
import com.skaymer.gryonixnexus.app.terminal.AccessoryLayoutStore
import com.skaymer.gryonixnexus.app.terminal.KeyGroup
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet

/** Add, remove and reorder the keys above the keyboard */
@Composable
fun AccessoryEditorSheet(store: AccessoryLayoutStore, onClose: () -> Unit) {
    val layout by store.layout.collectAsState()
    IOSSheet(
        title = stringResource(R.string.terminal_keys_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_done),
    ) {
        GroupedSection(footer = stringResource(R.string.terminal_keys_hint)) {
            layout.keys.forEachIndexed { index, key ->
                GroupedRow(
                    showDivider = index != layout.keys.lastIndex,
                    trailing = {
                        KeyEdit("↑", index > 0) { store.update { it.moving(index, index - 1) } }
                        KeyEdit("↓", index < layout.ids.lastIndex) { store.update { it.moving(index, index + 1) } }
                        KeyEdit("✕", true) { store.update { it.removing(index) } }
                    },
                ) { Text(key.label) }
            }
        }
        GroupedSection(header = stringResource(R.string.terminal_keys_add)) {
            KeyGroup.entries.forEach { group ->
                val free = AccessoryCatalog.all.filter { it.group == group && it.id !in layout.ids }
                ChoiceRow(
                    title = stringResource(groupTitle(group)),
                    value = "",
                    options = free.map { key -> key.label to { store.update { it.adding(key.id) } } },
                )
            }
        }
        GroupedSection {
            ActionRow(stringResource(R.string.terminal_keys_reset), onClick = { store.update { it.reset() } }, showDivider = false)
        }
    }
}

@Composable
private fun KeyEdit(symbol: String, enabled: Boolean, onClick: () -> Unit) {
    TextButton(onClick = onClick, enabled = enabled) { Text(symbol) }
}

private fun groupTitle(group: KeyGroup): Int = when (group) {
    KeyGroup.SPECIAL -> R.string.terminal_keys_special
    KeyGroup.SYMBOLS -> R.string.terminal_keys_symbols
    KeyGroup.FUNCTION -> R.string.terminal_keys_function
    KeyGroup.CONTROL -> R.string.terminal_keys_control
}
