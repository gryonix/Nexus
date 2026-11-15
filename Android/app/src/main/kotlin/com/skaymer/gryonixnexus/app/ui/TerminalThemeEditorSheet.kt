package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.terminal.TerminalTheme
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.SheetAction

/** Edits one custom theme. */
@Composable
fun TerminalThemeEditorSheet(
    theme: TerminalTheme,
    onDelete: (() -> Unit)?,
    onClose: () -> Unit,
    onSave: (TerminalTheme) -> Unit,
) {
    var draft by remember { mutableStateOf(theme) }
    IOSSheet(
        title = stringResource(R.string.terminal_design_edit),
        onClose = onClose,
        closeLabel = stringResource(R.string.access_cancel),
        action = SheetAction(stringResource(R.string.containers_done), enabled = draft.isValid && draft.name.isNotBlank()) {
            onSave(draft)
        },
    ) {
        GroupedSection {
            FieldRow(stringResource(R.string.terminal_design_name), draft.name, { draft = draft.copy(name = it) })
            HexRow(R.string.terminal_design_background, draft.background) { draft = draft.copy(background = it) }
            HexRow(R.string.terminal_design_text, draft.foreground) { draft = draft.copy(foreground = it) }
            HexRow(R.string.terminal_design_cursor, draft.cursor) { draft = draft.copy(cursor = it) }
            HexRow(R.string.terminal_design_selection, draft.selection, last = true) { draft = draft.copy(selection = it) }
        }
        AnsiSection(R.string.terminal_design_normal, draft, 0..7) { draft = it }
        AnsiSection(R.string.terminal_design_bright, draft, 8..15) { draft = it }
        if (onDelete != null) {
            GroupedSection {
                ActionRow(stringResource(R.string.delete_server_confirm), onClick = onDelete, danger = true, showDivider = false)
            }
        }
    }
}

@Composable
private fun AnsiSection(title: Int, draft: TerminalTheme, range: IntRange, onChange: (TerminalTheme) -> Unit) {
    GroupedSection(header = stringResource(title)) {
        for (index in range) {
            FieldRow(
                label = index.toString(),
                value = draft.ansi[index],
                onValueChange = { value -> onChange(draft.copy(ansi = draft.ansi.toMutableList().also { it[index] = value })) },
                showDivider = index != range.last,
            )
        }
    }
}

@Composable
private fun HexRow(label: Int, value: String, last: Boolean = false, onChange: (String) -> Unit) {
    FieldRow(stringResource(label), value, onChange, showDivider = !last)
}
