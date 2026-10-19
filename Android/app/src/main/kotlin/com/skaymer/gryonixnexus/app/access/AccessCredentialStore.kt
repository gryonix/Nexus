package com.skaymer.gryonixnexus.app.access

import com.skaymer.gryonixnexus.app.secrets.SecretStore
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class AccessCredential(
    val login: String? = null,
    val password: String? = null,
    val token: String? = null,
) {
    val isEmpty: Boolean
        get() = login.isNullOrEmpty() && password.isNullOrEmpty() && token.isNullOrEmpty()
}

/** The overrides of one deployment, keyed by [AccessCredentialStore.key] */
class AccessCredentialStore(
    private val store: SecretStore,
    private val deploymentID: String,
) {
    fun load(): Map<String, AccessCredential> {
        val text = store.string(account) ?: return emptyMap()
        return runCatching { json.decodeFromString<Map<String, AccessCredential>>(text) }
            .getOrDefault(emptyMap())
    }

    /** Replaces the whole override set */
    fun save(overrides: Map<String, AccessCredential>) {
        val pruned = overrides.filterValues { !it.isEmpty }
        if (pruned.isEmpty()) {
            store.deleteSecret(account)
            return
        }
        store.setString(account, json.encodeToString(pruned))
    }

    fun delete() = store.deleteSecret(account)

    private val account: String get() = "access-credentials-$deploymentID"

    companion object {
        fun key(host: String, title: String): String = "$host|$title"

        private val json = Json { ignoreUnknownKeys = true }
    }
}
