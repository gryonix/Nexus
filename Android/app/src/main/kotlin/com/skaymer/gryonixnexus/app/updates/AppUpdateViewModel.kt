package com.skaymer.gryonixnexus.app.updates

import android.content.Context
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class AppUpdateViewModel(
    private val store: SettingsStore,
    /** The version code of the APK actually installed — see [installedVersion] */
    private val installed: Long,
    private val installedName: String,
    private val fetch: suspend (String) -> String? = ::httpGet,
    private val now: () -> Long = System::currentTimeMillis,
) {
    /** Three outcomes and no fourth */
    sealed interface State {
        data object Idle : State
        data object Checking : State
        data object UpToDate : State
        data class Available(val release: AppUpdate.Release) : State
        data object Failed : State
    }

    private val _state = MutableStateFlow<State>(State.Idle)
    val state: StateFlow<State> = _state.asStateFlow()

    val version: String get() = installedName

    fun autoCheckEnabled(): Boolean = AppUpdate.autoCheckEnabled(store)

    fun setAutoCheck(enabled: Boolean) = AppUpdate.setAutoCheck(store, enabled)

    /** The check the app makes by itself */
    fun checkIfDue(scope: CoroutineScope) {
        if (!autoCheckEnabled()) return
        if (!AppUpdate.isDue(now(), AppUpdate.lastCheck(store))) return
        scope.launch { check(record = true) }
    }

    fun checkNow(scope: CoroutineScope) {
        scope.launch { check(record = false) }
    }

    private suspend fun check(record: Boolean) {
        _state.value = State.Checking
        val body = fetch(AppUpdate.FEED_URL)
        if (body != null && record) AppUpdate.recordCheck(store, now())
        val release = body?.let { AppUpdate.release(it) }
        _state.value = when {
            body == null -> State.Failed
            release == null -> State.Failed
            AppUpdate.isNewer(release, installed) -> State.Available(release)
            else -> State.UpToDate
        }
    }

    companion object {
        fun installedVersion(context: Context): Pair<Long, String> = runCatching {
            val info = context.packageManager.getPackageInfo(context.packageName, 0)
            info.longVersionCode to (info.versionName ?: "—")
        }.getOrElse { _: Throwable -> 0L to "—" }
    }
}

private const val MAX_BYTES = 64 * 1024

internal fun readAtMost(stream: java.io.InputStream, limit: Int): ByteArray {
    val out = java.io.ByteArrayOutputStream()
    val chunk = ByteArray(8 * 1024)
    while (out.size() < limit) {
        val read = stream.read(chunk, 0, minOf(chunk.size, limit - out.size()))
        if (read < 0) break
        out.write(chunk, 0, read)
    }
    return out.toByteArray()
}

internal suspend fun httpGet(url: String): String? = withContext(Dispatchers.IO) {
    runCatching {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        connection.instanceFollowRedirects = false
        connection.requestMethod = "GET"
        try {
            if (connection.responseCode != HttpURLConnection.HTTP_OK) return@runCatching null
            connection.inputStream.use { stream ->
                String(readAtMost(stream, MAX_BYTES), Charsets.UTF_8)
            }
        } finally {
            connection.disconnect()
        }
    }.getOrNull()
}
