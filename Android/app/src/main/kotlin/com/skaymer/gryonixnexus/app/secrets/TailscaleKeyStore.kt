package com.skaymer.gryonixnexus.app.secrets

/** The user's Tailscale join key, kept in the keystore */
class TailscaleKeyStore(private val store: SecretStore) {
    fun key(): String? = store.string(ITEM)?.takeIf { it.isNotEmpty() }

    fun setKey(value: String?) {
        val trimmed = value?.trim()
        if (trimmed.isNullOrEmpty()) store.deleteSecret(ITEM) else store.setString(ITEM, trimmed)
    }

    private companion object {
        const val ITEM = "tailscale-auth-key"
    }
}
