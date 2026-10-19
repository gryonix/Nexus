package com.skaymer.gryonixnexus.app.speed

import android.content.SharedPreferences
import com.skaymer.gryonixnexus.catalog.storage.SpeedTest
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/** One finished speed test; location is null for the internet */
@Serializable
data class SpeedRecord(
    val epochMillis: Long,
    val location: String? = null,
    val disk: SpeedTest.DiskResult? = null,
    val internet: SpeedTest.InternetResult? = null,
)

/** Latest speed tests per server, kept on this device */
class SpeedTestHistory(private val preferences: SharedPreferences) {
    fun records(serverId: String, host: SSHHostID): List<SpeedRecord> =
        preferences.getString(key(serverId, host), null)
            ?.let { runCatching { Json.decodeFromString(SERIALIZER, it) }.getOrNull() }
            .orEmpty()

    fun add(record: SpeedRecord, serverId: String, host: SSHHostID) {
        val kept = (listOf(record) + records(serverId, host)).take(LIMIT)
        preferences.edit().putString(key(serverId, host), Json.encodeToString(SERIALIZER, kept)).apply()
    }

    private fun key(serverId: String, host: SSHHostID) = "speedTest.history.$serverId.$host"

    companion object {
        const val LIMIT = 20
        private val SERIALIZER = ListSerializer(SpeedRecord.serializer())
    }
}
