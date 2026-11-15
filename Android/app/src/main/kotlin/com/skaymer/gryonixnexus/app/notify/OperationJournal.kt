package com.skaymer.gryonixnexus.app.notify

import android.content.Context
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** What happened to each operation notification, kept across launches. */
object OperationJournal {
    @Serializable
    data class Entry(val at: Long, val run: String, val text: String)

    const val LIMIT = 300
    private const val PREFS = "operation-journal"
    private const val KEY = "entries"
    private const val WEEK_MILLIS = 7L * 24 * 3600 * 1000
    private const val SUMMARY_LINES = 60
    private val json = Json { ignoreUnknownKeys = true }

    @Volatile
    private var context: Context? = null
    private var cached: List<Entry>? = null

    fun install(context: Context) {
        this.context = context.applicationContext
    }

    @Synchronized
    fun note(text: String, run: String = "") {
        val next = (entries() + Entry(System.currentTimeMillis(), run, text)).takeLast(LIMIT)
        cached = next
        prefs()?.edit()?.putString(KEY, json.encodeToString(next))?.apply()
    }

    @Synchronized
    fun entries(): List<Entry> = cached ?: load().also { cached = it }

    /** The last week, as lines for the weekly summary */
    fun recentLines(now: Long = System.currentTimeMillis()): List<String> = recent(entries(), now)

    fun recent(entries: List<Entry>, now: Long): List<String> =
        entries.filter { it.at > now - WEEK_MILLIS }.takeLast(SUMMARY_LINES).map(::line)

    fun line(entry: Entry): String {
        val run = if (entry.run.isEmpty()) "" else " [${entry.run}]"
        val stamp = SimpleDateFormat("dd.MM HH:mm:ss", Locale.ROOT).format(Date(entry.at))
        return "$stamp$run ${entry.text}"
    }

    /** A job id short enough to read */
    fun short(job: String): String = job.take(8)

    private fun prefs() = context?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun load(): List<Entry> {
        val raw = prefs()?.getString(KEY, null) ?: return emptyList()
        return runCatching { json.decodeFromString<List<Entry>>(raw) }.getOrDefault(emptyList())
    }
}
