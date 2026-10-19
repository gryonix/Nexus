package com.skaymer.gryonixnexus.app.notify

import com.skaymer.gryonixnexus.app.shell.SettingsStore
import java.util.concurrent.ConcurrentHashMap
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** One message about a job a server runs */
data class ServerJobCard(
    val job: String,
    /** Only the first message names the kind and title */
    val kind: String? = null,
    val title: String? = null,
    val server: String? = null,
    val text: String = "",
    val progress: Double? = null,
    val step: Int? = null,
    val steps: Int? = null,
    val finished: Boolean = false,
    val error: String? = null,
    val end: Boolean = false,
) {
    /** The line under the title, with "3/7" when known */
    val line: String
        get() = if (step != null && steps != null) "$step/$steps · $text" else text

    companion object {
        fun from(live: JsonObject): ServerJobCard? {
            fun JsonObject.text(key: String) = this[key]?.let { runCatching { it.jsonPrimitive.contentOrNull }.getOrNull() }
            val job = live.text("job")?.takeIf { it.isNotEmpty() } ?: return null
            val state = runCatching { live["state"]?.jsonObject }.getOrNull() ?: JsonObject(emptyMap())
            return ServerJobCard(
                job = job,
                kind = live.text("kind"),
                title = live.text("title"),
                server = live.text("server"),
                text = state.text("progressText").orEmpty(),
                progress = state["progress"]?.jsonPrimitive?.doubleOrNull,
                step = state["step"]?.jsonPrimitive?.intOrNull,
                steps = state["steps"]?.jsonPrimitive?.intOrNull,
                finished = state["isFinished"]?.jsonPrimitive?.booleanOrNull == true,
                error = state.text("errorMessage"),
                end = live["end"]?.jsonPrimitive?.booleanOrNull == true,
            )
        }
    }
}

/** Notifications for jobs a server reports, wherever they started */
object ServerJobNotices {
    private const val PREFIX = "serverJob."

    @Volatile
    var store: SettingsStore? = null

    /** Cancels a job on the machine behind a relay id */
    @Volatile
    var canceller: (suspend (serverId: String, job: String) -> Unit)? = null

    /** The saved server's name for a relay id */
    @Volatile
    var serverName: (serverId: String) -> String? = { null }

    private val shown = ConcurrentHashMap<String, Pair<OperationNotice, String>>()

    fun received(serverId: String, card: ServerJobCard) {
        val store = store ?: return
        val key = PREFIX + card.job
        if (card.end) {
            store.remove(key)
            return
        }
        if (card.title != null) store.setString(key, listOf(card.kind.orEmpty(), card.title, card.server.orEmpty()).joinToString("\n"))
        val saved = store.string(key)?.split("\n") ?: return
        val notice = shown[card.job]?.first ?: open(serverId, card.job, saved) ?: return
        if (card.finished) {
            shown.remove(card.job)
            notice.finish(card.text, card.error)
        } else {
            notice.update(card.line, card.progress)
        }
    }

    /** A new notification, unless this phone already shows its own */
    private fun open(serverId: String, job: String, saved: List<String>): OperationNotice? {
        val name = serverName(serverId) ?: saved.getOrNull(2).orEmpty()
        if (OperationNotices.isShowing(name) && shown.values.none { it.second == name }) return null
        val kind = OperationKind.entries.firstOrNull { it.name.lowercase() == saved.first() } ?: OperationKind.OTHER
        val notice = OperationNotices.startTitled(saved.getOrNull(1).orEmpty(), name, kind = kind)
        canceller?.let { cancel -> notice.onStop { cancel(serverId, job) } }
        shown[job] = notice to name
        return notice
    }
}
