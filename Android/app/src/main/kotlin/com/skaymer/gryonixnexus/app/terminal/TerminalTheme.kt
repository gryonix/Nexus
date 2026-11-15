package com.skaymer.gryonixnexus.app.terminal

/** A terminal colour scheme: 16 ANSI colours plus four more */
data class TerminalTheme(
    val id: String,
    val name: String,
    val background: String,
    val foreground: String,
    val cursor: String,
    val selection: String,
    val ansi: List<String>,
) {
    val isValid: Boolean
        get() = ansi.size == 16 && (listOf(background, foreground, cursor, selection) + ansi).all { rgb(it) != null }

    val isDark: Boolean
        get() {
            val (red, green, blue) = rgb(background) ?: return true
            return 0.299 * red + 0.587 * green + 0.114 * blue < 128
        }

    companion object {
        fun rgb(hex: String): Triple<Int, Int, Int>? {
            val digits = hex.removePrefix("#")
            if (digits.length != 6) return null
            val value = digits.toIntOrNull(16) ?: return null
            return Triple(value shr 16 and 255, value shr 8 and 255, value and 255)
        }

        fun hex(red: Double, green: Double, blue: Double): String {
            fun byte(value: Double) = Math.round(value.coerceIn(0.0, 1.0) * 255).toInt()
            return "#%02X%02X%02X".format(byte(red), byte(green), byte(blue))
        }
    }
}

/** The themes that ship with the app */
object TerminalThemes {
    const val DEFAULT_DARK_ID = "default-dark"
    const val DEFAULT_LIGHT_ID = "default-light"

    fun find(id: String, custom: List<TerminalTheme> = emptyList()): TerminalTheme? =
        (builtIn + custom).firstOrNull { it.id == id }

    private fun make(
        id: String,
        name: String,
        background: String,
        foreground: String,
        cursor: String,
        selection: String,
        ansi: String,
    ) = TerminalTheme(
        id, name, "#$background", "#$foreground", "#$cursor", "#$selection",
        ansi.split(" ").map { "#" + it.uppercase() },
    )

    val builtIn: List<TerminalTheme> = listOf(
        make(DEFAULT_DARK_ID, "Default dark", "10121A", "E6E6E6", "E6E6E6", "2F3446",
            "000000 CD3131 0DBC79 E5E510 2472C8 BC3FBC 11A8CD E5E5E5 666666 F14C4C 23D18B F5F543 3B8EEA D670D6 29B8DB FFFFFF"),
        make(DEFAULT_LIGHT_ID, "Default light", "FFFFFF", "1F2328", "1F2328", "B6D6FD",
            "24292F CF222E 116329 4D2D00 0969DA 8250DF 1B7C83 6E7781 57606A A40E26 1A7F37 633C01 218BFF A475F9 3192AA 8C959F"),
        make("solarized-dark", "Solarized Dark", "002B36", "839496", "93A1A1", "073642",
            "073642 DC322F 859900 B58900 268BD2 D33682 2AA198 EEE8D5 002B36 CB4B16 586E75 657B83 839496 6C71C4 93A1A1 FDF6E3"),
        make("solarized-light", "Solarized Light", "FDF6E3", "657B83", "586E75", "EEE8D5",
            "073642 DC322F 859900 B58900 268BD2 D33682 2AA198 EEE8D5 002B36 CB4B16 586E75 657B83 839496 6C71C4 93A1A1 FDF6E3"),
        make("dracula", "Dracula", "282A36", "F8F8F2", "F8F8F2", "44475A",
            "21222C FF5555 50FA7B F1FA8C BD93F9 FF79C6 8BE9FD F8F8F2 6272A4 FF6E6E 69FF94 FFFFA5 D6ACFF FF92DF A4FFFF FFFFFF"),
        make("nord", "Nord", "2E3440", "D8DEE9", "D8DEE9", "434C5E",
            "3B4252 BF616A A3BE8C EBCB8B 81A1C1 B48EAD 88C0D0 E5E9F0 4C566A BF616A A3BE8C EBCB8B 81A1C1 B48EAD 8FBCBB ECEFF4"),
        make("gruvbox-dark", "Gruvbox Dark", "282828", "EBDBB2", "EBDBB2", "504945",
            "282828 CC241D 98971A D79921 458588 B16286 689D6A A89984 928374 FB4934 B8BB26 FABD2F 83A598 D3869B 8EC07C EBDBB2"),
        make("one-dark", "One Dark", "282C34", "ABB2BF", "528BFF", "3E4451",
            "282C34 E06C75 98C379 E5C07B 61AFEF C678DD 56B6C2 ABB2BF 5C6370 E06C75 98C379 E5C07B 61AFEF C678DD 56B6C2 FFFFFF"),
        make("monokai", "Monokai", "272822", "F8F8F2", "F8F8F0", "49483E",
            "272822 F92672 A6E22E F4BF75 66D9EF AE81FF A1EFE4 F8F8F2 75715E F92672 A6E22E F4BF75 66D9EF AE81FF A1EFE4 F9F8F5"),
        make("tomorrow-night", "Tomorrow Night", "1D1F21", "C5C8C6", "AEAFAD", "373B41",
            "1D1F21 CC6666 B5BD68 F0C674 81A2BE B294BB 8ABEB7 C5C8C6 969896 CC6666 B5BD68 F0C674 81A2BE B294BB 8ABEB7 FFFFFF"),
        make("production-red", "Production red", "1E0C0C", "F2D6D6", "FF6B6B", "5A2020",
            "2A1010 FF5C5C 8FD18F FFC857 7AA7E6 D97BC0 6CCFCF EBCFCF 6B3B3B FF8080 A9E5A9 FFD98A 9DC0F0 E79BD3 8FE0E0 FFFFFF"),
    )
}
