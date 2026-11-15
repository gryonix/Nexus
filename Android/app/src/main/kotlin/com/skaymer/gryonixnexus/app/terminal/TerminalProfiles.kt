package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.app.secrets.SecretStore
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** One saved way into a shell on a server */
data class TerminalProfile(
    val id: String = UUID.randomUUID().toString(),
    val username: String,
    /** Which machine of the server; null is the first */
    val nodeID: String? = null,
    val usesAppKey: Boolean,
    val password: String = "",
    val keepAliveWithTmux: Boolean = false,
)

/** A server's saved logins, kept behind the device keystore */
class TerminalProfileStore(private val store: SecretStore, deploymentID: String) {
    private val account = "terminal-profiles-$deploymentID"

    fun load(): List<TerminalProfile> {
        val raw = store.string(account) ?: return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            (0 until array.length()).map { decode(array.getJSONObject(it)) }
        }.getOrDefault(emptyList())
    }

    fun save(profiles: List<TerminalProfile>) {
        if (profiles.isEmpty()) return store.deleteSecret(account)
        store.setString(account, JSONArray(profiles.map(::encode)).toString())
    }

    private fun encode(profile: TerminalProfile) = JSONObject()
        .put("id", profile.id)
        .put("username", profile.username)
        .put("nodeID", profile.nodeID ?: JSONObject.NULL)
        .put("appKey", profile.usesAppKey)
        .put("password", profile.password)
        .put("tmux", profile.keepAliveWithTmux)

    private fun decode(json: JSONObject) = TerminalProfile(
        id = json.getString("id"),
        username = json.getString("username"),
        nodeID = json.optString("nodeID").takeIf { it.isNotEmpty() && it != "null" },
        usesAppKey = json.optBoolean("appKey"),
        password = json.optString("password"),
        keepAliveWithTmux = json.optBoolean("tmux"),
    )
}
