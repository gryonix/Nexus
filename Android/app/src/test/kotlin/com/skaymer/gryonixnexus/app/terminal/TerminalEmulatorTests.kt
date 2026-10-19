package com.skaymer.gryonixnexus.app.terminal

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The terminal emulator: bytes in, a screen out */
class TerminalEmulatorTests {
    private val esc = "\u001B"

    private fun emulator(columns: Int = 20, rows: Int = 5) =
        TerminalEmulator(columns = columns, rows = rows, scrollbackLimit = 10)

    private fun TerminalEmulator.write(text: String) = feed(text.toByteArray(Charsets.UTF_8))

    private fun TerminalEmulator.line(index: Int) =
        screen[index].joinToString("") { it.char.toString() }.trimEnd()

    private fun TerminalEmulator.historyLines() =
        scrollback.map { row -> row.joinToString("") { it.char.toString() }.trimEnd() }

    // ------------------------------------------------------------- Printing

    @Test
    fun `what is typed lands where the cursor is`() {
        val screen = emulator()
        screen.write("hello")
        assertEquals("hello", screen.line(0))
        assertEquals(Cursor(0, 5), screen.cursor)
    }

    @Test
    fun `a carriage return goes back to the margin and a line feed goes down`() {
        val screen = emulator()
        screen.write("one\r\ntwo")
        assertEquals("one", screen.line(0))
        assertEquals("two", screen.line(1))
    }

    @Test
    fun `a line exactly as wide as the screen does not leave a blank row`() {
        val screen = emulator(columns = 5, rows = 3)
        screen.write("abcde")
        assertEquals("abcde", screen.line(0))
        assertEquals("", screen.line(1))
        screen.write("f")
        assertEquals("f", screen.line(1))
    }

    @Test
    fun `a tab lands on the next eighth column`() {
        val screen = emulator()
        screen.write("a\tb")
        assertEquals(8, screen.line(0).indexOf('b'))
    }

    // ------------------------------------------------------------ Scrolling

    @Test
    fun `the top line becomes history when the screen scrolls`() {
        val screen = emulator(columns = 10, rows = 3)
        screen.write("1\r\n2\r\n3\r\n4")
        assertEquals(listOf("2", "3", "4"), (0..2).map { screen.line(it) })
        assertEquals(listOf("1"), screen.historyLines())
    }

    @Test
    fun `history is bounded, and it is the OLDEST that goes`() {
        val screen = emulator(columns = 10, rows = 2)
        repeat(20) { screen.write("line$it\r\n") }
        assertEquals(10, screen.scrollback.size)
        val kept = screen.historyLines()
        assertEquals("line18", kept.last())
        assertEquals("line9", kept.first())
    }

    @Test
    fun `a line pushed out of a scroll region is not history`() {
        val screen = emulator(columns = 10, rows = 4)
        screen.write("${esc}[1;2r")
        screen.write("a\r\nb\r\nc")
        assertTrue(screen.scrollback.isEmpty())
    }

    // -------------------------------------------------------------- Erasing

    @Test
    fun `erasing to the end of the line leaves what came before it`() {
        val screen = emulator()
        screen.write("keep this")
        screen.write("${esc}[6G")
        screen.write("${esc}[K")
        assertEquals("keep", screen.line(0))
    }

    @Test
    fun `clearing the screen leaves the cursor where it was`() {
        val screen = emulator()
        screen.write("noise\r\nmore")
        screen.write("${esc}[2J")
        assertEquals("", screen.line(0))
        assertEquals("", screen.line(1))
        assertEquals(Cursor(1, 4), screen.cursor)
    }

    @Test
    fun `erasing paints the background but carries no ink`() {
        val screen = emulator()
        screen.write("${esc}[41;32m")
        screen.write("${esc}[K")
        val cell = screen.screen[0][0]
        assertEquals(1, cell.style.background)
        assertEquals(null, cell.style.foreground)
    }

    // --------------------------------------------------------------- Colour

    @Test
    fun `colour applies to what is written after it, and reset ends it`() {
        val screen = emulator()
        screen.write("${esc}[1;31mred${esc}[0mplain")
        val red = screen.screen[0][0]
        assertEquals(1, red.style.foreground)
        assertTrue(red.style.bold)
        assertEquals(CellStyle.PLAIN, screen.screen[0][3].style)
    }

    @Test
    fun `the 256-colour form is an index and the truecolour form is not mistaken for one`() {
        val screen = emulator()
        screen.write("${esc}[38;5;208mX")
        assertEquals(208, screen.screen[0][0].style.foreground)

        val other = emulator()
        other.write("${esc}[38;2;12;34;56mY")
        assertEquals("Y", other.line(0))
        assertEquals(null, other.screen[0][0].style.foreground)
    }

    // ------------------------------------------------------------ Sequences

    @Test
    fun `an escape sequence this build does not know prints nothing`() {
        val screen = emulator()
        screen.write("a${esc}[>4;2mb")
        assertEquals("ab", screen.line(0))
    }

    @Test
    fun `a window title is swallowed rather than printed`() {
        val screen = emulator()
        screen.write("${esc}]0;some titledone")
        assertEquals("done", screen.line(0))
    }

    @Test
    fun `a charset selection does not leave its letter on screen`() {
        val screen = emulator()
        screen.write("${esc}(Bok")
        assertEquals("ok", screen.line(0))
    }

    // ------------------------------------------------------- The alt screen

    @Test
    fun `leaving a full-screen program puts back what was underneath`() {
        val screen = emulator(columns = 10, rows = 3)
        screen.write("my shell")
        screen.write("${esc}[?1049h")
        screen.write("${esc}[2Jhtop")
        assertFalse(screen.line(0).startsWith("my shell"))

        screen.write("${esc}[?1049l")
        assertEquals("my shell", screen.line(0))
    }

    @Test
    fun `what a full-screen program pushes off its own screen is not history`() {
        val screen = emulator(columns = 10, rows = 2)
        screen.write("${esc}[?1049h")
        repeat(6) { screen.write("row$it\r\n") }
        assertTrue(screen.scrollback.isEmpty())
    }

    // ------------------------------------------------------------- Resizing

    @Test
    fun `a resized screen keeps its rows rather than reflowing them`() {
        val screen = emulator(columns = 10, rows = 3)
        screen.write("first\r\nsecond")
        screen.resize(columns = 6, rows = 4)
        assertEquals("first", screen.line(0))
        assertEquals("second", screen.line(1))
        assertEquals(4, screen.screen.size)
        assertEquals(6, screen.screen[0].size)
    }

    // ------------------------------------------------------ Cursor and text

    @Test
    fun `a program can hide the cursor and give it back`() {
        val screen = emulator()
        screen.write("${esc}[?25l")
        assertFalse(screen.cursor.visible)
        screen.write("${esc}[?25h")
        assertTrue(screen.cursor.visible)
    }

    @Test
    fun `text comes back with the padding trimmed off each line`() {
        val screen = emulator(columns = 10, rows = 2)
        screen.write("hi\r\nthere")
        assertEquals("hi\nthere", screen.text())
    }
}
