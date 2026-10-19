package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Surface
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.terminal.CellStyle
import com.skaymer.gryonixnexus.app.terminal.TerminalKeys
import com.skaymer.gryonixnexus.app.terminal.TerminalPalette
import com.skaymer.gryonixnexus.app.terminal.TerminalViewModel

/** A live shell, drawn */
@Composable
fun TerminalScreen(
    terminal: TerminalViewModel,
    onOpen: (columns: Int, rows: Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val state by terminal.state.collectAsState()
    val density = LocalDensity.current
    val focus = remember { FocusRequester() }
    var typed by remember { mutableStateOf(KEYBOARD_MARK) }
    var control by remember { mutableStateOf(false) }

    val fontSize = 13.sp
    val cell = remember(density, fontSize) {
        with(density) { CharacterBox(width = (fontSize.toPx() * 0.6f), height = fontSize.toPx() * 1.3f) }
    }

    Box(modifier.fillMaxSize().background(TerminalPalette.background)) {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f).fillMaxWidth()) {
                androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize()) {
                    val columns = with(density) {
                        ((maxWidth.toPx() - 16f) / cell.width).toInt().coerceIn(20, 400)
                    }
                    val rows = with(density) {
                        (maxHeight.toPx() / cell.height).toInt().coerceIn(4, 200)
                    }

                    LaunchedEffect(columns, rows) {
                        if (!state.isOpen && !state.isConnecting && state.errorMessage == null) {
                            onOpen(columns, rows)
                        } else if (state.isOpen) {
                            terminal.resize(columns, rows)
                        }
                    }

                    when {
                        state.isConnecting -> Row(
                            Modifier.padding(16.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            CircularProgressIndicator(Modifier.padding(4.dp))
                            Text(
                                stringResource(R.string.terminal_connecting),
                                color = TerminalPalette.foreground,
                            )
                        }
                        else -> Grid(terminal, state.revision, fontSize)
                    }
                }
            }

            state.errorMessage?.let { message ->
                Text(
                    message,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                )
            }

            if (state.isOpen) {
                KeyBar(terminal, focus, control) { control = !control }
                BasicTextField(
                    value = typed,
                    onValueChange = { value ->
                        val text = value.text.removePrefix(KEYBOARD_MARK.text)
                        when {
                            value.text.isEmpty() -> terminal.send(TerminalKeys.BACKSPACE)
                            text.isNotEmpty() -> {
                                terminal.send(TerminalKeys.typed(text, control))
                                control = false
                            }
                        }
                        typed = KEYBOARD_MARK
                    },
                    keyboardOptions = KeyboardOptions(
                        autoCorrectEnabled = false,
                        keyboardType = KeyboardType.Ascii,
                        imeAction = ImeAction.None,
                    ),
                    modifier = Modifier
                        .focusRequester(focus)
                        .padding(1.dp)
                        .fillMaxWidth(),
                    textStyle = androidx.compose.ui.text.TextStyle(
                        color = Color.Transparent,
                        fontSize = 1.sp,
                    ),
                    cursorBrush = androidx.compose.ui.graphics.SolidColor(Color.Transparent),
                )
            }
        }
    }

    DisposableEffect(Unit) { onDispose { terminal.close() } }
}

private val KEYBOARD_MARK = TextFieldValue(" ", selection = androidx.compose.ui.text.TextRange(1))

private data class CharacterBox(val width: Float, val height: Float)

/** The screen, as one annotated string per row */
@Composable
private fun Grid(
    terminal: TerminalViewModel,
    revision: Long,
    fontSize: androidx.compose.ui.unit.TextUnit,
) {
    val lines = remember(revision) { terminal.emulator.screen }
    val cursor = remember(revision) { terminal.emulator.cursor }

    Column(
        Modifier
            .fillMaxSize()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 8.dp, vertical = 4.dp),
    ) {
        lines.forEachIndexed { row, cells ->
            Text(
                buildAnnotatedString {
                    cells.forEachIndexed { column, cell ->
                        val onCursor = cursor.visible && cursor.row == row && cursor.column == column
                        appendCell(cell.char, cell.style, onCursor)
                    }
                },
                fontFamily = FontFamily.Monospace,
                fontSize = fontSize,
                lineHeight = fontSize * 1.3f,
                softWrap = false,
                maxLines = 1,
            )
        }
    }
}

private fun androidx.compose.ui.text.AnnotatedString.Builder.appendCell(
    char: Char,
    style: CellStyle,
    onCursor: Boolean,
) {
    val inverse = style.inverse != onCursor
    val ink = TerminalPalette.colour(style.foreground, TerminalPalette.foreground)
    val paper = TerminalPalette.colour(style.background, TerminalPalette.background)
    withStyle(
        SpanStyle(
            color = if (inverse) paper else ink,
            background = if (inverse) ink else paper,
            fontWeight = if (style.bold) FontWeight.Bold else FontWeight.Normal,
            textDecoration = if (style.underline) TextDecoration.Underline else null,
        )
    ) {
        append(if (char == '\u0000') ' ' else char)
    }
}

/** The keys a phone keyboard does not have */
@Composable
private fun KeyBar(terminal: TerminalViewModel, focus: FocusRequester, control: Boolean, onControl: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.surfaceVariant) {
        Row(
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            KeyButton(if (control) "CTRL*" else "CTRL", onControl)
            KeyButton("TAB") { terminal.send(TerminalKeys.TAB) }
            KeyButton("ESC") { terminal.send(TerminalKeys.ESCAPE) }
            KeyButton("↑") { terminal.send(TerminalKeys.UP) }
            KeyButton("↓") { terminal.send(TerminalKeys.DOWN) }
            KeyButton("←") { terminal.send(TerminalKeys.LEFT) }
            KeyButton("→") { terminal.send(TerminalKeys.RIGHT) }
            KeyButton("^C") { terminal.send(TerminalKeys.control('C')!!) }
            KeyButton("^D") { terminal.send(TerminalKeys.control('D')!!) }
            KeyButton("⏎") { terminal.send(TerminalKeys.ENTER) }
            KeyButton("⌫") { terminal.send(TerminalKeys.BACKSPACE) }
            KeyButton(stringResource(R.string.terminal_keyboard)) { focus.requestFocus() }
        }
    }
}

@Composable
private fun KeyButton(label: String, onPress: () -> Unit) {
    TextButton(onClick = onPress) {
        Text(label, style = MaterialTheme.typography.labelMedium)
    }
}
