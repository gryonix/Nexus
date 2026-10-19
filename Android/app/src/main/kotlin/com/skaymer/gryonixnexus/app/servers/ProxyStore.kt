package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.servercontrol.ProxyProfile
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

object ProxyStore {
    private const val KEY = "proxies.list"
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun all(store: SettingsStore): List<ProxyProfile> {
        val text = store.string(KEY)?.takeIf { it.isNotEmpty() } ?: return emptyList()
        return runCatching {
            json.decodeFromString(ListSerializer(ProxyProfile.serializer()), text)
        }.getOrDefault(emptyList())
    }

    fun save(store: SettingsStore, list: List<ProxyProfile>) {
        if (list.isEmpty()) {
            store.remove(KEY)
            return
        }
        store.setString(KEY, json.encodeToString(ListSerializer(ProxyProfile.serializer()), list))
    }

    fun profile(store: SettingsStore, id: String?): ProxyProfile? =
        id?.let { wanted -> all(store).firstOrNull { it.id == wanted } }

    fun remove(store: SettingsStore, secrets: SecretStore, id: String) {
        save(store, all(store).filterNot { it.id == id })
        ProxyPasswords(secrets).delete(id)
    }
}

class ProxyPasswords(private val secrets: SecretStore) {
    private fun account(id: String) = "gryonixnexus.proxy.$id"

    fun password(id: String): String? =
        secrets.secret(account(id))?.decodeToString()?.takeIf { it.isNotEmpty() }

    fun setPassword(id: String, password: String) {
        if (password.isEmpty()) {
            secrets.deleteSecret(account(id))
        } else {
            secrets.setSecret(account(id), password.encodeToByteArray())
        }
    }

    fun delete(id: String) = secrets.deleteSecret(account(id))
}
