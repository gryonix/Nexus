package com.skaymer.gryonixnexus.app.secrets

import java.util.UUID

class DeviceIdentity(private val store: SecretStore) {
    /** This installation's id, minting one on first use */
    val uid: String
        get() {
            cached?.let { return it }
            val existing = runCatching { store.string(ACCOUNT) }.getOrElse { return "" }
            if (!existing.isNullOrEmpty()) {
                cached = existing
                return existing
            }
            val minted = UUID.randomUUID().toString().uppercase()
            val written = runCatching { store.setString(ACCOUNT, minted) }.isSuccess
            if (!written) return ""
            cached = minted
            return minted
        }

    /** Forgets this installation's id */
    fun forget() {
        runCatching { store.deleteSecret(ACCOUNT) }
        cached = null
    }

    /** Read once per instance */
    private var cached: String? = null

    companion object {
        /** The same account name the other app files it under */
        const val ACCOUNT = "device-uid"
    }
}
