package com.skaymer.gryonixnexus.catalog

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.Locale

@Serializable
enum class AppLanguage(val code: String, val nativeName: String) {
    @SerialName("en") EN("en", "English"),
    @SerialName("de") DE("de", "Deutsch"),
    @SerialName("fr") FR("fr", "Français"),
    @SerialName("es") ES("es", "Español"),
    @SerialName("ru") RU("ru", "Русский"),
    @SerialName("uk") UK("uk", "Українська"),
    @SerialName("it") IT("it", "Italiano"),
    @SerialName("ja") JA("ja", "日本語"),
    @SerialName("zh") ZH("zh", "中文");

    val locale: Locale get() = Locale.forLanguageTag(code)

    /** Resolves a translation table, falling back to English */
    fun pick(table: Map<AppLanguage, String>): String =
        table[this] ?: table[EN] ?: ""

    companion object {
        fun from(code: String): AppLanguage? =
            entries.firstOrNull { it.code == code }

        fun matching(locale: Locale): AppLanguage =
            from(locale.language) ?: EN
    }
}
