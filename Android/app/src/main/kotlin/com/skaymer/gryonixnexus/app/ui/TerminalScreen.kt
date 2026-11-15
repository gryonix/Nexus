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
import com.skaymer.gryonixnexus.app.terminal.AccessoryKey
import com.skaymer.gryonixnexus.app.terminal.AccessoryLayoutStore
import com.skaymer.gryonixnexus.app.terminal.CellStyle
import com.skaymer.gryonixnexus.app.terminal.TerminalKeys
import com.skaymer.gryonixnexus.app.terminal.TerminalAppearance
import com.skaymer.gryonixnexus.app.terminal.TerminalCursorShape
import com.skaymer.gryonixnexus.app.terminal.TerminalPalette
import com.skaymer.gryonixnexus.app.terminal.TerminalTheme
import com.skaymer.gryonixnexus.app.terminal.TerminalThemes
import kotlinx.coroutines.delay
import com.skaymer.gryonixnexus.app.terminal.TerminalViewModel
import com.skaymer.gryonixnexus.transport.TerminalEndpoint

/** A live shell, drawn */
@Composable
fun TerminalScreen(
    terminal: TerminalViewModel,
    onOpen: (columns: Int, rows: Int) -> Unit,
    modifier: Modifier = Modifier,
    look: TerminalAppearance = TerminalAppearance(),
    keys: AccessoryLayoutStore = AccessoryLayoutStore(null),
    theme: TerminalTheme = TerminalThemes.builtIn.first(),
    onZoom: (Double) -> Unit = {},
    onDesign: () -> Unit = {},
    /** Shown under the shell, such as the VPN offer */
    footer: @Composable () -> Unit = {},
) {
    val state by terminal.state.collectAsState()
    val density = LocalDensity.current
    val focus = remember { FocusRequester() }
    var typed by remember { mutableStateOf(KEYBOARD_MARK) }
    var control by remember { mutableStateOf(false) }

    val fontSize = look.fontSize.sp
    val ink = remember(theme) { TerminalInk.of(theme) }
    var blinkOn by remember { mutableStateOf(true) }
    LaunchedEffect(look.cursorBlink) {
        blinkOn = true
        while (look.cursorBlink) {
            delay(CURSOR_BLINK_MS)
            blinkOn = !blinkOn
        }
    }
    val cell = remember(density, fontSize) {
        with(density) { CharacterBox(width = (fontSize.toPx() * 0.6f), height = fontSize.toPx() * 1.3f) }
    }

    Box(modifier.fillMaxSize().background(ink.background.copy(alpha = look.opacity.toFloat()))) {
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.weight(1f).fillMaxWidth()) {
                androidx.compose.foundation.layout.BoxWithConstraints(
                    Modifier.fillMaxSize().pinchToZoom(onZoom),
                ) {
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
                            PulseDot(Modifier.padding(4.dp))
                            Text(
                                stringResource(R.string.terminal_connecting),
                                color = ink.foreground,
                            )
                        }
                        else -> Grid(terminal, state.revision, fontSize, ink, look, blinkOn)
                    }
                    state.route?.takeIf { state.isOpen }?.let { route ->
                        RouteBadge(route, ink, Modifier.align(Alignment.TopEnd))
                    }
                    DesignButton(ink, onDesign, Modifier.align(Alignment.BottomEnd))
                    AiTerminalButton(terminal, Modifier.align(Alignment.TopStart))
                }
            }

            if (state.reconnectAttempt > 0) {
                Text(
                    stringResource(R.string.terminal_reconnecting, state.reconnectAttempt),
                    style = MaterialTheme.typography.bodySmall,
                    color = ink.foreground,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                )
            }

            state.errorMessage?.let { message ->
                Text(
                    message,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp).shakeOn(message),
                )
            }

            footer()

            if (state.isOpen) {
                KeyBar(terminal, focus, keys, control, onControlUsed = { control = false }) { control = !control }
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

/** Which way the shell went */
@Composable
private fun RouteBadge(route: TerminalEndpoint.Kind, ink: TerminalInk, modifier: Modifier) {
    val title = com.skaymer.gryonixnexus.app.terminal.TerminalRoutes.titleRes(route)
    Text(
        stringResource(title),
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.SemiBold,
        color = ink.background,
        modifier = modifier
            .padding(6.dp)
            .background(ink.foreground.copy(alpha = 0.7f), androidx.compose.foundation.shape.RoundedCornerShape(50))
            .padding(horizontal = 8.dp, vertical = 2.dp),
    )
}

private const val CURSOR_BLINK_MS = 530L

private val KEYBOARD_MARK = TextFieldValue(" ", selection = androidx.compose.ui.text.TextRange(1))

private data class CharacterBox(val width: Float, val height: Float)

/** The screen, as one annotated string per row */
@Composable
private fun Grid(
    terminal: TerminalViewModel,
    revision: Long,
    fontSize: androidx.compose.ui.unit.TextUnit,
    ink: TerminalInk,
    look: TerminalAppearance,
    blinkOn: Boolean,
) {
    val lines = remember(revision) { terminal.emulator.screen }
    val cursor = remember(revision) { terminal.emulator.cursor }
    val shown = cursor.visible && (!look.cursorBlink || blinkOn)
    val family = remember(look.fontName) { TerminalFonts.family(look.fontName) }

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
                        val onCursor = shown && cursor.row == row && cursor.column == column
                        appendCell(cell.char, cell.style, if (onCursor) look.cursorShape else null, ink)
                    }
                },
                fontFamily = family,
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
    cursor: TerminalCursorShape?,
    ink: TerminalInk,
) {
    val text = if (char == '\u0000') ' ' else char
    val block = cursor == TerminalCursorShape.BLOCK
    val inverse = style.inverse != block
    val foreground = TerminalPalette.colour(style.foreground, ink.foreground, ink.ansi)
    val background = style.background?.let { TerminalPalette.colour(it, ink.background, ink.ansi) }
    val paper = when {
        block -> ink.cursor
        inverse -> foreground
        else -> background ?: Color.Transparent
    }
    val color = when {
        block -> ink.background
        inverse -> background ?: ink.background
        cursor != null -> ink.cursor
        else -> foreground
    }
    withStyle(
        SpanStyle(
            color = color,
            background = paper,
            fontWeight = if (style.bold) FontWeight.Bold else FontWeight.Normal,
            textDecoration = if (style.underline || cursor == TerminalCursorShape.UNDERLINE) TextDecoration.Underline else null,
        )
    ) {
        append(if (cursor == TerminalCursorShape.BAR && text == ' ') '\u258F' else text)
    }
}

/** The keys a phone keyboard does not have */
@Composable
private fun KeyBar(
    terminal: TerminalViewModel,
    focus: FocusRequester,
    keys: AccessoryLayoutStore,
    control: Boolean,
    onControlUsed: () -> Unit,
    onControl: () -> Unit,
) {
    val layout by keys.layout.collectAsState()
    Surface(color = MaterialTheme.colorScheme.surfaceVariant) {
        Row(
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            layout.keys.forEach { key ->
                val armed = control && key.action == AccessoryKey.Action.ControlToggle
                KeyButton(if (armed) key.label + "*" else key.label) {
                    when (val action = key.action) {
                        AccessoryKey.Action.ControlToggle -> onControl()
                        is AccessoryKey.Action.Bytes -> terminal.send(action.bytes)
                        is AccessoryKey.Action.Text -> {
                            terminal.send(TerminalKeys.typed(action.text, control))
                            onControlUsed()
                        }
                    }
                }
            }
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
