package com.skaymer.gryonixnexus.app.push

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

/** Firebase's public Android settings, as the relay hands them out */
@Serializable
data class FirebaseSettings(
    val project_id: String,
    val app_id: String,
    val api_key: String,
    val sender_id: String,
)

/** Starts Firebase from a relay and gets a push token */
object RelayFirebase {
    private val json = Json { ignoreUnknownKeys = true }

    /** The settings in the relay's answer, if it has them */
    fun parse(body: String): FirebaseSettings? = runCatching {
        val fcm = json.parseToJsonElement(body).jsonObject["fcm"] as? JsonObject ?: return null
        json.decodeFromJsonElement(FirebaseSettings.serializer(), fcm)
    }.getOrNull()

    suspend fun settings(relayUrl: String): FirebaseSettings? = withContext(Dispatchers.IO) {
        val connection = URL(relayUrl.trimEnd('/') + "/v1/client").openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        try {
            if (connection.responseCode != HttpURLConnection.HTTP_OK) return@withContext null
            parse(connection.inputStream.bufferedReader().use { it.readText() })
        } finally {
            connection.disconnect()
        }
    }

    /** This phone's push token for the relay's Firebase project */
    suspend fun token(context: Context, settings: FirebaseSettings): String {
        val app = app(context.applicationContext, settings)
        val token = app.get(FirebaseMessaging::class.java).token.await()
        context.getSharedPreferences(GryonixMessagingService.PREFERENCES, Context.MODE_PRIVATE)
            .edit().putString(GryonixMessagingService.TOKEN_KEY, token).apply()
        return token
    }

    private fun app(context: Context, settings: FirebaseSettings): FirebaseApp {
        val existing = FirebaseApp.getApps(context)
        existing.firstOrNull { it.options.projectId == settings.project_id }?.let { return it }
        val options = FirebaseOptions.Builder()
            .setProjectId(settings.project_id)
            .setApplicationId(settings.app_id)
            .setApiKey(settings.api_key)
            .setGcmSenderId(settings.sender_id)
            .build()
        val hasDefault = existing.any { it.name == FirebaseApp.DEFAULT_APP_NAME }
        return if (hasDefault) {
            FirebaseApp.initializeApp(context, options, settings.project_id)
        } else {
            FirebaseApp.initializeApp(context, options)
        }
    }
}
