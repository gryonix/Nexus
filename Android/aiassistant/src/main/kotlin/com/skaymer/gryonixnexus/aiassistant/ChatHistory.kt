package com.skaymer.gryonixnexus.aiassistant

import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class AIChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val role: String,
    val text: String,
    val createdAt: Long,
    val inputTokens: Int? = null,
    val outputTokens: Int? = null,
    @SerialName("imageIDs") val imageIds: List<String>? = null,
)

@Serializable
data class AIChat(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val updatedAt: Long,
    val messages: List<AIChatMessage> = emptyList(),
)

enum class AIDateGroup { TODAY, YESTERDAY, LAST_WEEK, EARLIER }

/** All chats of this device, newest first. */
@Serializable
data class AIChatHistory(val chats: List<AIChat> = emptyList()) {
    fun upsert(chat: AIChat): AIChatHistory =
        AIChatHistory((listOf(chat) + chats.filter { it.id != chat.id }).sortedByDescending { it.updatedAt })

    fun delete(id: String): AIChatHistory = AIChatHistory(chats.filter { it.id != id })

    fun groups(nowMillis: Long, zone: ZoneId = ZoneId.systemDefault()): List<Pair<AIDateGroup, List<AIChat>>> {
        val today = Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDate()
        fun group(chat: AIChat): AIDateGroup {
            val day: LocalDate = Instant.ofEpochMilli(chat.updatedAt).atZone(zone).toLocalDate()
            val age = ChronoUnit.DAYS.between(day, today)
            return when {
                age <= 0 -> AIDateGroup.TODAY
                age == 1L -> AIDateGroup.YESTERDAY
                age < 7 -> AIDateGroup.LAST_WEEK
                else -> AIDateGroup.EARLIER
            }
        }
        return AIDateGroup.entries.mapNotNull { name ->
            chats.filter { group(it) == name }.takeIf { it.isNotEmpty() }?.let { name to it }
        }
    }
}

/** A JSON file holding the history; never synced. */
class AIChatFileStore(private val file: File) {
    fun load(): AIChatHistory =
        runCatching { Json.decodeFromString<AIChatHistory>(file.readText()) }.getOrDefault(AIChatHistory())

    fun save(history: AIChatHistory) {
        file.parentFile?.mkdirs()
        val temporary = File(file.path + ".tmp")
        temporary.writeText(Json.encodeToString(AIChatHistory.serializer(), history))
        temporary.renameTo(file)
    }
}
