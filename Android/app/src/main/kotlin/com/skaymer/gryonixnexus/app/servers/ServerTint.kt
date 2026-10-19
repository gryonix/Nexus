package com.skaymer.gryonixnexus.app.servers

/** The accent a server's card is drawn in */
enum class ServerTint(val raw: String) {
    BLUE("blue"),
    TEAL("teal"),
    GREEN("green"),
    ORANGE("orange"),
    PINK("pink"),
    PURPLE("purple"),
    RED("red"),
    GRAY("gray");

    companion object {
        fun of(raw: String?): ServerTint? = entries.firstOrNull { it.raw == raw }
    }
}
