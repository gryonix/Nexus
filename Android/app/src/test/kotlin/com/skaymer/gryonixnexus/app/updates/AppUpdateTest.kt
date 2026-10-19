package com.skaymer.gryonixnexus.app.updates

import com.skaymer.gryonixnexus.app.shell.SettingsStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class AppUpdateTest {
    @Test
    fun `a download is read up to the limit and no further`() {
        val data = ByteArray(20_000) { (it % 251).toByte() }
        assertEquals(10_000, readAtMost(data.inputStream(), 10_000).size)
        assertEquals(20_000, readAtMost(data.inputStream(), 64 * 1024).size)
    }

    private fun feed(
        code: Long = 5,
        name: String = "1.2",
        url: String = "https://gryonix.com/nexus/android/gryonixnexus-1.2.apk",
    ) = """{"versionCode": $code, "versionName": "$name", "url": "$url"}"""

    @Test
    fun `a well formed file describes a release`() {
        val release = AppUpdate.release(feed())
        assertEquals(5L, release?.versionCode)
        assertEquals("1.2", release?.versionName)
    }

    @Test
    fun `unknown fields are ignored`() {
        val release = AppUpdate.release(
            """{"versionCode": 5, "versionName": "1.2", "url": "https://gryonix.com/a.apk", "changelogUrl": "…"}"""
        )
        assertEquals(5L, release?.versionCode)
    }

    @Test
    fun `the digest parses through when present and is null when absent`() {
        val hash = "e".repeat(64)
        val withHash = AppUpdate.release(
            """{"versionCode": 5, "versionName": "1.2", "url": "https://gryonix.com/a.apk", "sha256": "$hash"}"""
        )
        assertEquals(hash, withHash?.sha256)
        assertNull(AppUpdate.release(feed())?.sha256)
    }

    @Test
    fun `rubbish is not a release`() {
        assertNull(AppUpdate.release(""))
        assertNull(AppUpdate.release("<html>404</html>"))
        assertNull(AppUpdate.release("""{"versionName": "1.2", "url": "https://gryonix.com/a.apk"}"""))
    }

    @Test
    fun `a download somewhere else is refused`() {
        assertNull(AppUpdate.release(feed(url = "http://gryonix.com/a.apk")))
        assertNull(AppUpdate.release(feed(url = "https://example.org/a.apk")))
        assertNull(AppUpdate.release(feed(url = "https://gryonix.com.example.org/a.apk")))
        assertNull(AppUpdate.release(feed(url = "not a url at all")))
    }

    @Test
    fun `the feed is the nexus one`() {
        assertEquals("https://gryonix.com/nexus/android/latest.json", AppUpdate.FEED_URL)
        assertTrue(AppUpdate.isOurDownload("https://gryonix.com/nexus/android/gryonixnexus-1.0.apk"))
    }

    @Test
    fun `a version code of zero or less is refused`() {
        assertNull(AppUpdate.release(feed(code = 0)))
        assertNull(AppUpdate.release(feed(code = -3)))
    }

    @Test
    fun `an empty version name is refused`() {
        assertNull(AppUpdate.release(feed(name = "")))
    }

    /** Strictly newer */
    @Test
    fun `only a strictly higher version code is news`() {
        val release = AppUpdate.release(feed(code = 5))!!
        assertTrue(AppUpdate.isNewer(release, installed = 4))
        assertFalse(AppUpdate.isNewer(release, installed = 5))
        assertFalse(AppUpdate.isNewer(release, installed = 6))
    }

    // ------------------------------------------------------------- the clock

    @Test
    fun `the check is due once a day`() {
        val day = AppUpdate.INTERVAL_MS
        assertTrue(AppUpdate.isDue(now = day, last = 0))
        assertTrue(AppUpdate.isDue(now = day + 1, last = 0))
        assertFalse(AppUpdate.isDue(now = day - 1, last = 0))
    }

    /** A stamp in the future counts as due */
    @Test
    fun `a stamp from the future does not silence the check for ever`() {
        assertTrue(AppUpdate.isDue(now = 1_000, last = 999_999_999))
    }

    // ---------------------------------------------------------- the settings

    private class MemoryStore : SettingsStore {
        val values = mutableMapOf<String, Any>()
        private val _revision = MutableStateFlow(0L)
        override val revision: StateFlow<Long> = _revision
        override fun string(key: String): String? = values[key] as? String
        override fun setString(key: String, value: String) { values[key] = value; _revision.value++ }
        override fun stringList(key: String): List<String>? {
            @Suppress("UNCHECKED_CAST")
            return values[key] as? List<String>
        }
        override fun setStringList(key: String, value: List<String>) { values[key] = value; _revision.value++ }
        override fun boolean(key: String): Boolean? = values[key] as? Boolean
        override fun setBoolean(key: String, value: Boolean) { values[key] = value; _revision.value++ }
        override fun remove(key: String) { values.remove(key); _revision.value++ }
    }

    @Test
    fun `automatic checks are on by default and can be turned off`() {
        val store = MemoryStore()
        assertTrue(AppUpdate.autoCheckEnabled(store))
        AppUpdate.setAutoCheck(store, false)
        assertFalse(AppUpdate.autoCheckEnabled(store))
        AppUpdate.setAutoCheck(store, true)
        assertTrue(AppUpdate.autoCheckEnabled(store))
    }

    // ------------------------------------------------------------- the model

    private fun model(
        store: SettingsStore,
        installed: Long = 4,
        now: Long = AppUpdate.INTERVAL_MS * 10,
        answer: String? = """{"versionCode": 5, "versionName": "1.2", "url": "https://gryonix.com/a.apk"}""",
        asked: MutableList<String> = mutableListOf(),
    ) = AppUpdateViewModel(
        store = store,
        installed = installed,
        installedName = "1.1",
        fetch = { url -> asked += url; answer },
        now = { now },
    )

    @Test
    fun `a newer version becomes the available state`() = runTest {
        val store = MemoryStore()
        val model = model(store)
        model.checkNow(this)
        advanceUntilIdle()
        advanceUntilIdle()
        val state = model.state.value
        assertTrue(state is AppUpdateViewModel.State.Available)
        assertEquals("1.2", (state as AppUpdateViewModel.State.Available).release.versionName)
    }

    @Test
    fun `the same version is up to date, not a failure`() = runTest {
        val model = model(MemoryStore(), installed = 5)
        model.checkNow(this)
        advanceUntilIdle()
        advanceUntilIdle()
        assertEquals(AppUpdateViewModel.State.UpToDate, model.state.value)
    }

    @Test
    fun `no answer is a failure and not up to date`() = runTest {
        val model = model(MemoryStore(), answer = null)
        model.checkNow(this)
        advanceUntilIdle()
        advanceUntilIdle()
        assertEquals(AppUpdateViewModel.State.Failed, model.state.value)
    }

    @Test
    fun `an answer that is not a release is a failure too`() = runTest {
        val model = model(MemoryStore(), answer = "<html>maintenance</html>")
        model.checkNow(this)
        advanceUntilIdle()
        advanceUntilIdle()
        assertEquals(AppUpdateViewModel.State.Failed, model.state.value)
    }

    @Test
    fun `the automatic check asks nothing when it is switched off`() = runTest {
        val store = MemoryStore()
        AppUpdate.setAutoCheck(store, false)
        val asked = mutableListOf<String>()
        model(store, asked = asked).checkIfDue(this)
        advanceUntilIdle()
        assertEquals(emptyList<String>(), asked)
    }

    @Test
    fun `the automatic check asks once a day and not twice`() = runTest {
        val store = MemoryStore()
        val asked = mutableListOf<String>()
        val now = AppUpdate.INTERVAL_MS * 10
        model(store, now = now, asked = asked).checkIfDue(this)
        advanceUntilIdle()
        assertEquals(listOf(AppUpdate.FEED_URL), asked)
        model(store, now = now + 60_000, asked = asked).checkIfDue(this)
        advanceUntilIdle()
        assertEquals(listOf(AppUpdate.FEED_URL), asked)
        // A day later it asks again.
        model(store, now = now + AppUpdate.INTERVAL_MS, asked = asked).checkIfDue(this)
        advanceUntilIdle()
        assertEquals(listOf(AppUpdate.FEED_URL, AppUpdate.FEED_URL), asked)
    }

    /** A day offline is not a day of not asking */
    @Test
    fun `a check that could not reach the site does not count as today's`() = runTest {
        val store = MemoryStore()
        val asked = mutableListOf<String>()
        val now = AppUpdate.INTERVAL_MS * 10
        model(store, now = now, answer = null, asked = asked).checkIfDue(this)
        advanceUntilIdle()
        assertEquals(listOf(AppUpdate.FEED_URL), asked)
        model(store, now = now + 60_000, answer = null, asked = asked).checkIfDue(this)
        advanceUntilIdle()
        assertEquals(listOf(AppUpdate.FEED_URL, AppUpdate.FEED_URL), asked)
    }

    /** The button asks whatever the switch says — otherwise nobody can look once. */
    @Test
    fun `pressing the row asks even with automatic checks off`() = runTest {
        val store = MemoryStore()
        AppUpdate.setAutoCheck(store, false)
        val asked = mutableListOf<String>()
        model(store, asked = asked).checkNow(this)
        advanceUntilIdle()
        assertEquals(listOf(AppUpdate.FEED_URL), asked)
    }
}
