package com.skaymer.gryonixnexus.app.terminal

/** How one character is drawn */
data class CellStyle(
    val foreground: Int? = null,
    val background: Int? = null,
    val bold: Boolean = false,
    val underline: Boolean = false,
    val inverse: Boolean = false,
) {
    companion object {
        val PLAIN = CellStyle()
    }
}

/** One character cell of the screen */
data class Cell(val char: Char = ' ', val style: CellStyle = CellStyle.PLAIN)

/** Where the caret is, counted from zero */
data class Cursor(val row: Int = 0, val column: Int = 0, val visible: Boolean = true)

/** A terminal screen, and the parser that writes to it */
class TerminalEmulator(
    columns: Int = 80,
    rows: Int = 24,
    /** How many scrolled-off lines are kept */
    private val scrollbackLimit: Int = 2000,
) {
    var columns: Int = columns.coerceAtLeast(1)
        private set
    var rows: Int = rows.coerceAtLeast(1)
        private set

    private var lines: MutableList<MutableList<Cell>> = blank(this.rows, this.columns)
    private val history: ArrayDeque<List<Cell>> = ArrayDeque()

    private var row = 0
    private var column = 0
    private var cursorVisible = true
    private var style = CellStyle.PLAIN

    private var pendingWrap = false

    /** The scrolling region, inclusive, as DECSTBM sets it */
    private var scrollTop = 0
    private var scrollBottom = this.rows - 1

    /** Saved by the alternate-screen switch, restored when it is left */
    private var savedLines: MutableList<MutableList<Cell>>? = null
    private var savedRow = 0
    private var savedColumn = 0
    private var savedStyle = CellStyle.PLAIN

    val isAlternateScreen: Boolean get() = savedLines != null

    /** What the screen shows now */
    val screen: List<List<Cell>> get() = lines.map { it.toList() }

    /** The lines that have scrolled off, oldest first */
    val scrollback: List<List<Cell>> get() = history.toList()

    val cursor: Cursor get() = Cursor(row, column, cursorVisible)

    // ------------------------------------------------------------ The input

    private val decoder = UTF8Decoder()
    private var state = State.GROUND
    private val parameters = StringBuilder()
    private var privateMarker: Char? = null

    private enum class State {
        GROUND,
        ESCAPE,
        CSI,
        OSC,

        ESCAPE_CONSUME,

        /** Inside a string, having just seen ESC: `ESC \` ends it */
        OSC_ESCAPE,
    }

    /** Feed bytes exactly as they arrived */
    fun feed(bytes: ByteArray) {
        for (byte in bytes) {
            when (state) {
                State.GROUND -> ground(byte)
                State.ESCAPE -> escape(byte)
                State.CSI -> csi(byte)
                State.OSC -> osc(byte)
                State.ESCAPE_CONSUME -> state = State.GROUND
                State.OSC_ESCAPE -> state = if ((byte.toInt() and 0xFF) == '\\'.code) {
                    State.GROUND
                } else {
                    State.OSC
                }
            }
        }
    }

    private fun ground(byte: Byte) {
        val value = byte.toInt() and 0xFF
        when (value) {
            0x1B -> { state = State.ESCAPE; decoder.reset() }
            0x07 -> Unit // BEL: a sound this app does not make.
            0x08 -> { pendingWrap = false; column = (column - 1).coerceAtLeast(0) }
            0x09 -> tab()
            0x0A, 0x0B, 0x0C -> lineFeed()
            0x0D -> { pendingWrap = false; column = 0 }
            else -> decoder.decode(byte) { put(it) }
        }
    }

    private fun escape(byte: Byte) {
        when (val value = byte.toInt() and 0xFF) {
            '['.code -> { state = State.CSI; parameters.setLength(0); privateMarker = null }
            ']'.code -> { state = State.OSC; parameters.setLength(0) }
            'D'.code -> { lineFeed(); state = State.GROUND }
            'M'.code -> { reverseLineFeed(); state = State.GROUND }
            'E'.code -> { lineFeed(); column = 0; state = State.GROUND }
            'c'.code -> { reset(); state = State.GROUND }
            '('.code, ')'.code, '*'.code, '+'.code, '#'.code, '%'.code ->
                state = State.ESCAPE_CONSUME
            else -> state = if (value in 0x20..0x2F) State.ESCAPE else State.GROUND
        }
    }

    private fun csi(byte: Byte) {
        val value = byte.toInt() and 0xFF
        when {
            value == '?'.code || value == '>'.code || value == '!'.code ->
                privateMarker = value.toChar()
            value in 0x30..0x3B -> parameters.append(value.toChar())
            value in 0x40..0x7E -> {
                dispatch(value.toChar())
                state = State.GROUND
            }
            else -> Unit
        }
    }

    private fun osc(byte: Byte) {
        val value = byte.toInt() and 0xFF
        if (value == 0x07) {
            state = State.GROUND
        } else if (value == 0x1B) {
            state = State.OSC_ESCAPE
        }
    }

    // ------------------------------------------------------------ The verbs

    private fun dispatch(final: Char) {
        val values = parameters.toString().split(';').map { it.toIntOrNull() }
        fun at(index: Int, fallback: Int = 1): Int =
            values.getOrNull(index)?.takeIf { it > 0 } ?: fallback

        when (final) {
            'A' -> { pendingWrap = false; row = (row - at(0)).coerceAtLeast(scrollTop) }
            'B' -> { pendingWrap = false; row = (row + at(0)).coerceAtMost(scrollBottom) }
            'C' -> { pendingWrap = false; column = (column + at(0)).coerceAtMost(columns - 1) }
            'D' -> { pendingWrap = false; column = (column - at(0)).coerceAtLeast(0) }
            'E' -> { row = (row + at(0)).coerceAtMost(scrollBottom); column = 0 }
            'F' -> { row = (row - at(0)).coerceAtLeast(scrollTop); column = 0 }
            'G' -> { pendingWrap = false; column = (at(0) - 1).coerceIn(0, columns - 1) }
            'H', 'f' -> {
                pendingWrap = false
                row = (at(0) - 1).coerceIn(0, rows - 1)
                column = (at(1) - 1).coerceIn(0, columns - 1)
            }
            'J' -> eraseInDisplay(values.getOrNull(0) ?: 0)
            'K' -> eraseInLine(values.getOrNull(0) ?: 0)
            'L' -> insertLines(at(0))
            'M' -> deleteLines(at(0))
            'P' -> deleteCharacters(at(0))
            '@' -> insertCharacters(at(0))
            'X' -> eraseCharacters(at(0))
            'S' -> repeat(at(0)) { scrollUp() }
            'T' -> repeat(at(0)) { scrollDown() }
            'd' -> { pendingWrap = false; row = (at(0) - 1).coerceIn(0, rows - 1) }
            'm' -> applyStyle(values)
            'r' -> {
                val top = (at(0) - 1).coerceIn(0, rows - 1)
                val bottom = (values.getOrNull(1)?.takeIf { it > 0 } ?: rows) - 1
                val end = bottom.coerceIn(0, rows - 1)
                if (top < end) {
                    scrollTop = top
                    scrollBottom = end
                } else {
                    scrollTop = 0
                    scrollBottom = rows - 1
                }
                row = scrollTop
                column = 0
            }
            'h' -> setMode(values, enabled = true)
            'l' -> setMode(values, enabled = false)
            's' -> { savedRow = row; savedColumn = column }
            'u' -> { row = savedRow; column = savedColumn }
            else -> Unit
        }
    }

    private fun setMode(values: List<Int?>, enabled: Boolean) {
        if (privateMarker != '?') return
        for (value in values) {
            when (value) {
                25 -> cursorVisible = enabled
                1049, 1047, 47 -> if (enabled) enterAlternateScreen() else leaveAlternateScreen()
                else -> Unit
            }
        }
    }

    private fun applyStyle(values: List<Int?>) {
        if (values.isEmpty() || (values.size == 1 && values[0] == null)) {
            style = CellStyle.PLAIN
            return
        }
        var index = 0
        while (index < values.size) {
            when (val code = values[index] ?: 0) {
                0 -> style = CellStyle.PLAIN
                1 -> style = style.copy(bold = true)
                4 -> style = style.copy(underline = true)
                7 -> style = style.copy(inverse = true)
                22 -> style = style.copy(bold = false)
                24 -> style = style.copy(underline = false)
                27 -> style = style.copy(inverse = false)
                39 -> style = style.copy(foreground = null)
                49 -> style = style.copy(background = null)
                in 30..37 -> style = style.copy(foreground = code - 30)
                in 40..47 -> style = style.copy(background = code - 40)
                in 90..97 -> style = style.copy(foreground = code - 90 + 8)
                in 100..107 -> style = style.copy(background = code - 100 + 8)
                38, 48 -> {
                    val kind = values.getOrNull(index + 1)
                    if (kind == 5) {
                        val colour = values.getOrNull(index + 2)
                        if (code == 38) style = style.copy(foreground = colour)
                        else style = style.copy(background = colour)
                        index += 2
                    } else if (kind == 2) {
                        index += 4
                    }
                }
                else -> Unit
            }
            index += 1
        }
    }

    // ----------------------------------------------------------- The screen

    private fun put(char: Char) {
        if (pendingWrap) {
            column = 0
            lineFeed()
            pendingWrap = false
        }
        lines[row][column] = Cell(char, style)
        if (column == columns - 1) pendingWrap = true else column += 1
    }

    private fun tab() {
        pendingWrap = false
        val next = ((column / 8) + 1) * 8
        column = next.coerceAtMost(columns - 1)
    }

    private fun lineFeed() {
        pendingWrap = false
        if (row == scrollBottom) scrollUp() else row = (row + 1).coerceAtMost(rows - 1)
    }

    private fun reverseLineFeed() {
        pendingWrap = false
        if (row == scrollTop) scrollDown() else row = (row - 1).coerceAtLeast(0)
    }

    private fun scrollUp() {
        val leaving = lines.removeAt(scrollTop)
        if (scrollTop == 0 && scrollBottom == rows - 1 && !isAlternateScreen) {
            history.addLast(leaving.toList())
            while (history.size > scrollbackLimit) history.removeFirst()
        }
        lines.add(scrollBottom, blankLine())
    }

    private fun scrollDown() {
        lines.removeAt(scrollBottom)
        lines.add(scrollTop, blankLine())
    }

    private fun eraseInDisplay(mode: Int) {
        when (mode) {
            0 -> {
                eraseInLine(0)
                for (index in row + 1 until rows) lines[index] = blankLine()
            }
            1 -> {
                eraseInLine(1)
                for (index in 0 until row) lines[index] = blankLine()
            }
            else -> {
                for (index in 0 until rows) lines[index] = blankLine()
            }
        }
    }

    private fun eraseInLine(mode: Int) {
        val line = lines[row]
        when (mode) {
            0 -> for (index in column until columns) line[index] = Cell(style = blankStyle())
            1 -> for (index in 0..column.coerceAtMost(columns - 1)) line[index] = Cell(style = blankStyle())
            else -> for (index in 0 until columns) line[index] = Cell(style = blankStyle())
        }
    }

    private fun eraseCharacters(count: Int) {
        val line = lines[row]
        for (index in column until (column + count).coerceAtMost(columns)) {
            line[index] = Cell(style = blankStyle())
        }
    }

    private fun insertCharacters(count: Int) {
        val line = lines[row]
        repeat(count.coerceAtMost(columns - column)) {
            line.add(column, Cell(style = blankStyle()))
            line.removeAt(line.size - 1)
        }
    }

    private fun deleteCharacters(count: Int) {
        val line = lines[row]
        repeat(count.coerceAtMost(columns - column)) {
            line.removeAt(column)
            line.add(Cell(style = blankStyle()))
        }
    }

    private fun insertLines(count: Int) {
        if (row < scrollTop || row > scrollBottom) return
        repeat(count.coerceAtMost(scrollBottom - row + 1)) {
            lines.removeAt(scrollBottom)
            lines.add(row, blankLine())
        }
    }

    private fun deleteLines(count: Int) {
        if (row < scrollTop || row > scrollBottom) return
        repeat(count.coerceAtMost(scrollBottom - row + 1)) {
            lines.removeAt(row)
            lines.add(scrollBottom, blankLine())
        }
    }

    private fun enterAlternateScreen() {
        if (isAlternateScreen) return
        savedLines = lines
        savedRow = row
        savedColumn = column
        savedStyle = style
        lines = blank(rows, columns)
        row = 0
        column = 0
        style = CellStyle.PLAIN
    }

    private fun leaveAlternateScreen() {
        val restored = savedLines ?: return
        lines = restored
        savedLines = null
        row = savedRow.coerceIn(0, rows - 1)
        column = savedColumn.coerceIn(0, columns - 1)
        style = savedStyle
    }

    /** The window changed shape */
    fun resize(columns: Int, rows: Int) {
        val width = columns.coerceAtLeast(1)
        val height = rows.coerceAtLeast(1)
        if (width == this.columns && height == this.rows) return

        val resized = MutableList(height) { index ->
            val existing = lines.getOrNull(index)
            MutableList(width) { at -> existing?.getOrNull(at) ?: Cell() }
        }
        this.columns = width
        this.rows = height
        lines = resized
        scrollTop = 0
        scrollBottom = height - 1
        row = row.coerceIn(0, height - 1)
        column = column.coerceIn(0, width - 1)
        pendingWrap = false
    }

    /** Back to a screen nothing has been drawn on */
    fun reset() {
        lines = blank(rows, columns)
        history.clear()
        row = 0
        column = 0
        style = CellStyle.PLAIN
        cursorVisible = true
        pendingWrap = false
        scrollTop = 0
        scrollBottom = rows - 1
        savedLines = null
        state = State.GROUND
        decoder.reset()
    }

    fun text(): String = lines.joinToString("\n") { line ->
        line.joinToString("") { it.char.toString() }.trimEnd()
    }

    private fun blankStyle() = CellStyle(background = style.background)

    private fun blankLine() = MutableList(columns) { Cell() }

    private fun blank(rows: Int, columns: Int) =
        MutableList(rows) { MutableList(columns) { Cell() } }
}
