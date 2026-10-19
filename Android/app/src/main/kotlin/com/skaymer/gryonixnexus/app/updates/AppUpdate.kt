package com.skaymer.gryonixnexus.app.updates

import com.skaymer.gryonixnexus.app.shell.SettingsStore
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

object AppUpdate {
    /** Where the published version is written down */
    const val FEED_URL = "https://gryonix.com/nexus/android/latest.json"

    const val HOST = "gryonix.com"

    /** What the file says */
    @Serializable
    data class Release(
        @SerialName("versionCode") val versionCode: Long,
        @SerialName("versionName") val versionName: String,
        @SerialName("url") val url: String,
        /** What changed, if the file bothers to say */
        @SerialName("notes") val notes: String? = null,
        @SerialName("sha256") val sha256: String? = null,
    )

    private val json = Json { ignoreUnknownKeys = true }

    fun release(from: String): Release? {
        val release = runCatching { json.decodeFromString<Release>(from) }.getOrNull() ?: return null
        if (release.versionCode <= 0) return null
        if (release.versionName.isBlank()) return null
        if (!isOurDownload(release.url)) return null
        return release
    }

    /** Whether a URL may be offered as the download */
    fun isOurDownload(url: String): Boolean {
        val parsed = runCatching { java.net.URI(url) }.getOrNull() ?: return false
        return parsed.scheme == "https" && parsed.host == HOST
    }

    /** Is this release worth telling somebody about? */
    fun isNewer(release: Release, installed: Long): Boolean = release.versionCode > installed

    // ---------------------------------------------------------------- settings

    /** Whether the app asks the site at all */
    const val AUTO_CHECK_KEY = "app.updates.autoCheck"

    const val LAST_CHECK_KEY = "app.updates.lastCheck"

    /** Once a day */
    const val INTERVAL_MS = 24L * 60 * 60 * 1000

    /** Automatic checks are on unless somebody turned them off */
    fun autoCheckEnabled(store: SettingsStore): Boolean = store.boolean(AUTO_CHECK_KEY) ?: true

    fun setAutoCheck(store: SettingsStore, enabled: Boolean) =
        store.setBoolean(AUTO_CHECK_KEY, enabled)

    fun lastCheck(store: SettingsStore): Long = store.string(LAST_CHECK_KEY)?.toLongOrNull() ?: 0

    fun recordCheck(store: SettingsStore, at: Long) = store.setString(LAST_CHECK_KEY, at.toString())

    /** Whether the automatic check is due */
    fun isDue(now: Long, last: Long): Boolean = now < last || now - last >= INTERVAL_MS
}
