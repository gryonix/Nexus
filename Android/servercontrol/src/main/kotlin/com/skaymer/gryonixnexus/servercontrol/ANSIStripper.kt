package com.skaymer.gryonixnexus.servercontrol

object ANSIStripper {
    private const val ESC = '\u001B'
    private const val BEL = '\u0007'

    fun strip(input: String): String {
        val result = StringBuilder()
        var i = 0
        while (i < input.length) {
            val scalar = input[i]
            i++
            if (scalar != ESC) {
                result.append(scalar)
                continue
            }
            if (i >= input.length) break
            val next = input[i]
            i++
            if (next == '[') {
                while (i < input.length) {
                    val byte = input[i]
                    i++
                    if (byte.code in 0x40..0x7E) break
                }
            } else if (next == ']') {
                // OSC: terminated by BEL or ESC \.
                while (i < input.length) {
                    val byte = input[i]
                    i++
                    if (byte == BEL) break
                    if (byte == ESC && i < input.length && input[i] == '\\') {
                        i++
                        break
                    }
                }
            }
            // Other two-byte escapes: ESC + single char, already consumed.
        }

        return result.toString()
            .split("\n")
            .joinToString("\n") { line ->
                val lastCR = line.lastIndexOf('\r')
                if (lastCR < 0) line else line.substring(lastCR + 1)
            }
    }
}
