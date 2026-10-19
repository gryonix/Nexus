package com.skaymer.gryonixnexus.app.terminal

/** What a key sends */
object TerminalKeys {
    private const val ESC = "\u001B"

    val ENTER: ByteArray = byteArrayOf(0x0D)
    val BACKSPACE: ByteArray = byteArrayOf(0x7F)
    val TAB: ByteArray = byteArrayOf(0x09)
    val ESCAPE: ByteArray = ESC.toByteArray()

    val UP: ByteArray = "$ESC[A".toByteArray()
    val DOWN: ByteArray = "$ESC[B".toByteArray()
    val RIGHT: ByteArray = "$ESC[C".toByteArray()
    val LEFT: ByteArray = "$ESC[D".toByteArray()
    val HOME: ByteArray = "$ESC[H".toByteArray()
    val END: ByteArray = "$ESC[F".toByteArray()
    val PAGE_UP: ByteArray = "$ESC[5~".toByteArray()
    val PAGE_DOWN: ByteArray = "$ESC[6~".toByteArray()

    fun control(letter: Char): ByteArray? {
        val upper = letter.uppercaseChar()
        if (upper !in 'A'..'Z') return null
        return byteArrayOf((upper - 'A' + 1).toByte())
    }

    fun typed(value: String, control: Boolean): ByteArray {
        if (!control) return text(value)
        return value.fold(ByteArray(0)) { sent, letter ->
            sent + (control(letter) ?: text(letter.toString()))
        }
    }

    /** Typed text, as the far end reads it */
    fun text(value: String): ByteArray = value.toByteArray(Charsets.UTF_8)
}
