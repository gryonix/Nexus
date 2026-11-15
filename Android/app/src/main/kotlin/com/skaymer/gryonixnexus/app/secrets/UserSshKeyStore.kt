package com.skaymer.gryonixnexus.app.secrets

import com.skaymer.gryonixnexus.servercontrol.UserSshKey
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/** Keystore-backed list of the user's own SSH keys */
class UserSshKeyStore(private val store: SecretStore) {
    private val _keys = MutableStateFlow(read())
    val keys: StateFlow<List<UserSshKey>> = _keys.asStateFlow()

    fun add(key: UserSshKey) = write(_keys.value + key)

    fun rename(id: String, name: String) = write(_keys.value.map { if (it.id == id) it.copy(name = name) else it })

    fun delete(id: String) = write(_keys.value.filter { it.id != id })

    private fun write(updated: List<UserSshKey>) {
        store.setString(ACCOUNT, Json.encodeToString(serializer, updated))
        _keys.value = updated
    }

    private fun read(): List<UserSshKey> =
        store.string(ACCOUNT)?.let { runCatching { Json.decodeFromString(serializer, it) }.getOrNull() }.orEmpty()

    private companion object {
        const val ACCOUNT = "user-ssh-keys"
        val serializer = ListSerializer(UserSshKey.serializer())
    }
}
