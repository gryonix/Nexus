package com.skaymer.gryonixnexus.app.licensing

import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

enum class LicenseFailure { UNKNOWN_CODE, EXPIRED, REVOKED, DEVICE_LIMIT, WRONG_PRODUCT, OFFLINE, REJECTED }

class LicenseApiException(val failure: LicenseFailure) : Exception(failure.name)

@Serializable
data class LicenseGrant(val token: String? = null, val code: String? = null)

@Serializable
data class LicenseDevice(val device: String, val name: String? = null, val platform: String? = null)

@Serializable
data class LicenseDeviceList(val limit: Int, val devices: List<LicenseDevice>)

/** Calls to the license server on gryonix.com. */
open class LicenseApi(private val base: String = "https://gryonix.com/api/") {
    private val json = Json { ignoreUnknownKeys = true }

    open suspend fun activate(code: String, device: String, name: String): LicenseGrant =
        json.decodeFromString(post("activate", mapOf("code" to code, "device" to device,
            "app" to APP, "name" to name, "platform" to "android")))

    open suspend fun deactivate(code: String, device: String) {
        post("deactivate", mapOf("code" to code, "device" to device))
    }

    open suspend fun markUsed(code: String, device: String) {
        post("used", mapOf("code" to code, "device" to device))
    }

    open suspend fun devices(code: String): LicenseDeviceList =
        json.decodeFromString(post("devices", mapOf("code" to code)))

    private suspend fun post(path: String, body: Map<String, String>): String = withContext(Dispatchers.IO) {
        val connection = runCatching { URL(base + path).openConnection() as HttpURLConnection }
            .getOrElse { throw LicenseApiException(LicenseFailure.OFFLINE) }
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 20_000
            connection.readTimeout = 20_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            val payload = JsonObject(body.mapValues { JsonPrimitive(it.value) }).toString()
            runCatching { connection.outputStream.use { it.write(payload.toByteArray()) } }
                .getOrElse { throw LicenseApiException(LicenseFailure.OFFLINE) }
            read(connection)
        } finally {
            connection.disconnect()
        }
    }

    private fun read(connection: HttpURLConnection): String {
        val status = runCatching { connection.responseCode }
            .getOrElse { throw LicenseApiException(LicenseFailure.OFFLINE) }
        val stream = if (status == 200) connection.inputStream else connection.errorStream
        val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
        if (status != 200) throw LicenseApiException(failure(text))
        return text
    }

    private fun failure(text: String): LicenseFailure {
        val error = runCatching { json.parseToJsonElement(text).jsonObject["error"]?.jsonPrimitive?.content }
            .getOrNull()
        return when (error) {
            "unknown_code" -> LicenseFailure.UNKNOWN_CODE
            "expired" -> LicenseFailure.EXPIRED
            "revoked" -> LicenseFailure.REVOKED
            "device_limit" -> LicenseFailure.DEVICE_LIMIT
            "wrong_product" -> LicenseFailure.WRONG_PRODUCT
            else -> LicenseFailure.REJECTED
        }
    }

    companion object {
        const val APP = "nexus"
    }
}
