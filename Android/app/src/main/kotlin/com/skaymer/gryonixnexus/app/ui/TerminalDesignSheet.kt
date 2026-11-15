package com.skaymer.gryonixnexus.app.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.terminal.AccessoryLayoutStore
import com.skaymer.gryonixnexus.app.terminal.ITermColorsImport
import com.skaymer.gryonixnexus.app.terminal.TerminalAppearance
import com.skaymer.gryonixnexus.app.terminal.TerminalAppearanceStore
import com.skaymer.gryonixnexus.app.terminal.TerminalCursorShape
import com.skaymer.gryonixnexus.app.terminal.TerminalTheme
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import java.util.UUID

/** Settings for how terminals look */
@Composable
fun TerminalDesignSheet(
    store: TerminalAppearanceStore,
    keys: AccessoryLayoutStore,
    serverID: String,
    onClose: () -> Unit,
) {
    val look by store.look.collectAsState()
    var editing by remember { mutableStateOf<TerminalTheme?>(null) }
    var importFailed by remember { mutableStateOf(false) }
    var editingKeys by remember { mutableStateOf(false) }
    val importer = importLauncher(store) { importFailed = !it }
    IOSSheet(
        title = stringResource(R.string.terminal_design_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_done),
    ) {
        ThemeSection(store, look)
        ServerThemeSection(store, look, serverID)
        FontSection(store, look)
        CursorSection(store, look)
        GroupedSection(header = stringResource(R.string.terminal_design_background)) {
            Column(Modifier.padding(horizontal = Metrics.listInset)) {
                Text(stringResource(R.string.terminal_design_opacity, (look.opacity * 100).toInt()))
                Slider(
                    value = look.opacity.toFloat(),
                    onValueChange = { value -> store.update { it.copy(opacity = value.toDouble()) } },
                    valueRange = TerminalAppearance.OPACITIES.start.toFloat()..1f,
                )
            }
        }
        GroupedSection {
            ActionRow(stringResource(R.string.terminal_keys_title), onClick = { editingKeys = true }, showDivider = false)
        }
        GroupedSection(
            header = stringResource(R.string.terminal_design_custom),
            footer = if (importFailed) stringResource(R.string.terminal_design_bad_file) else null,
        ) {
            look.custom.forEach { theme -> ActionRow(text = theme.name, onClick = { editing = theme }) }
            ActionRow(stringResource(R.string.terminal_design_new), onClick = { editing = newTheme(look) })
            ActionRow(
                stringResource(R.string.terminal_design_import),
                onClick = { importer.launch(arrayOf("*/*")) },
                showDivider = false,
            )
        }
    }
    if (editingKeys) AccessoryEditorSheet(keys) { editingKeys = false }
    editing?.let { theme ->
        TerminalThemeEditorSheet(
            theme = theme,
            onDelete = if (look.custom.any { it.id == theme.id }) {
                { store.update { it.removingCustom(theme.id) }; editing = null }
            } else null,
            onClose = { editing = null },
        ) { saved -> store.update { it.saving(saved) }; editing = null }
    }
}

private fun newTheme(look: TerminalAppearance): TerminalTheme =
    look.theme(true, null).copy(id = "custom-" + UUID.randomUUID().toString().lowercase(), name = "New theme")

@Composable
private fun importLauncher(store: TerminalAppearanceStore, done: (Boolean) -> Unit) =
    LocalContext.current.let { context ->
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri == null) return@rememberLauncherForActivityResult
            val text = runCatching {
                context.contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) }
            }.getOrNull()
            val name = uri.lastPathSegment.orEmpty().substringAfterLast('/').substringBeforeLast('.')
            val theme = text?.let { runCatching { ITermColorsImport.theme(it, name.ifBlank { "Imported" }) }.getOrNull() }
            if (theme != null) store.update { it.saving(theme) }
            done(theme != null)
        }
    }

@Composable
private fun ThemeSection(store: TerminalAppearanceStore, look: TerminalAppearance) {
    GroupedSection {
        ToggleRow(
            title = stringResource(R.string.terminal_design_follow_system),
            checked = look.followSystem,
            onCheckedChange = { value -> store.update { it.copy(followSystem = value) } },
        )
        if (look.followSystem) {
            ThemeChoice(R.string.terminal_design_dark, look.darkThemeID, look) { id -> store.update { it.copy(darkThemeID = id) } }
            ThemeChoice(R.string.terminal_design_light, look.lightThemeID, look, last = true) { id ->
                store.update { it.copy(lightThemeID = id) }
            }
        } else {
            ThemeChoice(R.string.terminal_design_theme, look.fixedThemeID, look, last = true) { id ->
                store.update { it.copy(fixedThemeID = id) }
            }
        }
    }
}

@Composable
private fun ThemeChoice(title: Int, current: String, look: TerminalAppearance, last: Boolean = false, onPick: (String) -> Unit) {
    ChoiceRow(
        title = stringResource(title),
        value = look.allThemes.firstOrNull { it.id == current }?.name.orEmpty(),
        showDivider = !last,
        options = look.allThemes.map { theme -> theme.name to { onPick(theme.id) } },
    )
}

@Composable
private fun ServerThemeSection(store: TerminalAppearanceStore, look: TerminalAppearance, serverID: String) {
    val same = stringResource(R.string.terminal_design_same)
    GroupedSection {
        ChoiceRow(
            title = stringResource(R.string.terminal_design_server_theme),
            value = look.serverThemes[serverID]?.let { id -> look.allThemes.firstOrNull { it.id == id }?.name } ?: same,
            showDivider = false,
            options = listOf(same to { store.update { it.copy(serverThemes = it.serverThemes - serverID) } }) +
                look.allThemes.map { theme ->
                    theme.name to { store.update { it.copy(serverThemes = it.serverThemes + (serverID to theme.id)) } }
                },
        )
    }
}

@Composable
private fun FontSection(store: TerminalAppearanceStore, look: TerminalAppearance) {
    val system = stringResource(R.string.terminal_design_font_system)
    GroupedSection(header = stringResource(R.string.terminal_design_font)) {
        ChoiceRow(
            title = stringResource(R.string.terminal_design_font),
            value = TerminalFonts.title(look.fontName) ?: system,
            options = TerminalFonts.choices.map { name -> (TerminalFonts.title(name) ?: system) to { store.update { it.copy(fontName = name) } } },
        )
        Column(Modifier.padding(horizontal = Metrics.listInset)) {
            Text(stringResource(R.string.terminal_design_font_size, look.fontSize.toInt()))
            Slider(
                value = look.fontSize.toFloat(),
                onValueChange = { value -> store.update { it.copy(fontSize = Math.round(value).toDouble()) } },
                valueRange = TerminalAppearance.FONT_SIZES.start.toFloat()..TerminalAppearance.FONT_SIZES.endInclusive.toFloat(),
            )
        }
    }
}

@Composable
private fun CursorSection(store: TerminalAppearanceStore, look: TerminalAppearance) {
    val titles = mapOf(
        TerminalCursorShape.BLOCK to stringResource(R.string.terminal_design_block),
        TerminalCursorShape.BAR to stringResource(R.string.terminal_design_bar),
        TerminalCursorShape.UNDERLINE to stringResource(R.string.terminal_design_underline),
    )
    GroupedSection(header = stringResource(R.string.terminal_design_cursor)) {
        ChoiceRow(
            title = stringResource(R.string.terminal_design_cursor_shape),
            value = titles.getValue(look.cursorShape),
            options = titles.map { (shape, title) -> title to { store.update { it.copy(cursorShape = shape) } } },
        )
        ToggleRow(
            title = stringResource(R.string.terminal_design_blink),
            checked = look.cursorBlink,
            onCheckedChange = { value -> store.update { it.copy(cursorBlink = value) } },
            showDivider = false,
        )
    }
}
