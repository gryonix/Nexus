package com.skaymer.gryonixnexus.app.secrets

class InMemorySecretStore : SecretStore {
    val items = mutableMapOf<String, ByteArray>()

    override fun secret(account: String): ByteArray? = items[account]

    override fun setSecret(account: String, value: ByteArray) {
        items[account] = value
    }

    override fun deleteSecret(account: String) {
        items.remove(account)
    }
}
