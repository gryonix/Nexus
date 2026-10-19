package com.skaymer.gryonixnexus.app.notify

import com.skaymer.gryonixnexus.app.secrets.SecretStore
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.security.SecureRandom
import org.json.JSONObject

class DevicePushProof(private val secrets: SecretStore) {
    val secret: String
        get() = secrets.string(ACCOUNT) ?: newSecret().also { secrets.setString(ACCOUNT, it) }

    val proof: String get() = hash(secret)

    fun serversHolding(token: String, extraRelays: List<String> = emptyList()): Int =
        total(token, "GET", "servers", extraRelays)

    fun stopAll(token: String, extraRelays: List<String> = emptyList()): Int =
        total(token, "DELETE", "removed", extraRelays)

    private fun total(token: String, method: String, field: String, extraRelays: List<String>): Int {
        var sum = 0
        for (relay in (listOf(NotifyViewModel.DEFAULT_RELAY_URL) + extraRelays).distinct()) {
            sum += runCatching {
                val connection = URL("$relay/v1/devices/$token").openConnection() as HttpURLConnection
                connection.requestMethod = method
                connection.connectTimeout = 15_000
                connection.readTimeout = 15_000
                connection.setRequestProperty("x-gryonix-device-secret", secret)
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                JSONObject(body).getInt(field)
            }.getOrDefault(0)
        }
        return sum
    }

    companion object {
        private const val ACCOUNT = "push.device-secret"

        fun hash(secret: String): String =
            MessageDigest.getInstance("SHA-256").digest(secret.toByteArray()).joinToString("") { "%02x".format(it) }

        private fun newSecret(): String {
            val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
            return bytes.joinToString("") { "%02x".format(it) }
        }
    }
}
