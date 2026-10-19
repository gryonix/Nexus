package com.skaymer.gryonixnexus.servercontrol

object OutputTail {
    const val DEFAULT_MAX_CHARACTERS = 3000

    fun tail(text: String, maxCharacters: Int = DEFAULT_MAX_CHARACTERS): String =
        if (text.length <= maxCharacters) text else "…" + text.takeLast(maxCharacters)
}
