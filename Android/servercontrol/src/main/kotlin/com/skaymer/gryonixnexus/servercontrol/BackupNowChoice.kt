package com.skaymer.gryonixnexus.servercontrol

/** What "Back up now" runs: services, encryption and key */
data class BackupNowChoice(
    /** Chosen services, raw IDs, in the order they run */
    val services: List<String> = emptyList(),
    /** Null until changed: then the services' own default */
    val encrypt: Boolean? = null,
    val key: Key = Key.STORED,
    val passphrase: String = "",
    val confirmation: String = "",
) {
    /** Which password encrypts the archives */
    enum class Key { STORED, TYPED }

    fun toggled(service: String): BackupNowChoice =
        copy(services = if (service in services) services - service else services + service)

    /** The toggle: as set, or on if a service encrypts */
    fun encrypting(defaultsOn: Set<String>): Boolean = encrypt ?: services.any { it in defaultsOn }

    /** Whether one service's archive is encrypted */
    fun encrypts(service: String, defaultsOn: Set<String>, alwaysEncrypted: Set<String>): Boolean =
        service in alwaysEncrypted || encrypting(defaultsOn)

    /** Whether any chosen archive needs a key */
    fun needsKey(defaultsOn: Set<String>, alwaysEncrypted: Set<String>): Boolean =
        services.any { encrypts(it, defaultsOn, alwaysEncrypted) }

    /** The password to send; null means the server's stored key */
    val passphraseToSend: String? get() = passphrase.takeIf { key == Key.TYPED && it.isNotEmpty() }

    /** Whether the run can start; an unknown key is tried */
    fun isReady(defaultsOn: Set<String>, alwaysEncrypted: Set<String>, hasStoredKey: Boolean?): Boolean {
        if (services.isEmpty()) return false
        if (!needsKey(defaultsOn, alwaysEncrypted)) return true
        return when (key) {
            Key.STORED -> hasStoredKey != false
            Key.TYPED -> passphrase.length >= 8 && passphrase == confirmation
        }
    }

    companion object {
        /** The chosen services' sizes added up, or null */
        fun total(estimates: List<BackupEstimate>): BackupEstimate? {
            if (estimates.isEmpty()) return null
            return BackupEstimate(estimates.sumOf { it.dataBytes }, estimates.minOf { it.freeBytes })
        }
    }
}
