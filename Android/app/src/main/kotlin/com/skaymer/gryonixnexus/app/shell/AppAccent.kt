package com.skaymer.gryonixnexus.app.shell

enum class AppAccent(val raw: String) {
    /** The palette's own accent — iOS blue */
    APP("app"),
    RED("red"),
    ORANGE("orange"),
    YELLOW("yellow"),
    GREEN("green"),
    TEAL("teal"),
    PURPLE("purple"),
    PINK("pink"),
    GRAPHITE("graphite"),
    /** Ink, not literal black — see `AppAccent.colour` */
    BLACK("black"),
    INDIGO("indigo"),
    BROWN("brown");

    companion object {
        const val KEY = "appearance.accentChoice"

        fun of(raw: String?): AppAccent = entries.firstOrNull { it.raw == raw } ?: APP
    }
}

fun SettingsStore.appAccent(): AppAccent = AppAccent.of(string(AppAccent.KEY))

/** Writes it back in the spelling [AppAccent.of] matches on */
fun SettingsStore.setAppAccent(accent: AppAccent) = setString(AppAccent.KEY, accent.raw)
