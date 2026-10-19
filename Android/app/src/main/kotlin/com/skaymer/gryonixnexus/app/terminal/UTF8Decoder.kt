package com.skaymer.gryonixnexus.app.terminal

/** UTF-8, decoded ACROSS reads rather than per read */
class UTF8Decoder {
    private var pending = 0
    private var remaining = 0
    private var expected = 0

    fun reset() {
        pending = 0
        remaining = 0
        expected = 0
    }

    /** Feeds one byte, emitting whole characters as they complete */
    inline fun decode(byte: Byte, emit: (Char) -> Unit) {
        val value = byte.toInt() and 0xFF
        for (code in accept(value)) {
            if (code > 0xFFFF) {
                val offset = code - 0x10000
                emit(((offset shr 10) + 0xD800).toChar())
                emit(((offset and 0x3FF) + 0xDC00).toChar())
            } else {
                emit(code.toChar())
            }
        }
    }

    fun accept(value: Int): IntArray = when {
        remaining > 0 && (value and 0xC0) == 0x80 -> {
            pending = (pending shl 6) or (value and 0x3F)
            remaining -= 1
            if (remaining == 0) {
                val code = pending
                val spent = expected
                reset()
                if (code > 0x10FFFF || code in 0xD800..0xDFFF || spent > shortestLength(code)) {
                    intArrayOf(0xFFFD)
                } else {
                    intArrayOf(code)
                }
            } else {
                EMPTY
            }
        }
        remaining > 0 -> {
            reset()
            if ((value and 0x80) == 0) intArrayOf(0xFFFD, value) else intArrayOf(0xFFFD)
        }
        value < 0x80 -> intArrayOf(value)
        (value and 0xE0) == 0xC0 -> { pending = value and 0x1F; remaining = 1; expected = 2; EMPTY }
        (value and 0xF0) == 0xE0 -> { pending = value and 0x0F; remaining = 2; expected = 3; EMPTY }
        (value and 0xF8) == 0xF0 -> { pending = value and 0x07; remaining = 3; expected = 4; EMPTY }
        else -> intArrayOf(0xFFFD)
    }

    private fun shortestLength(code: Int): Int = when {
        code < 0x80 -> 1
        code < 0x800 -> 2
        code < 0x10000 -> 3
        else -> 4
    }

    private companion object {
        val EMPTY = IntArray(0)
    }
}
