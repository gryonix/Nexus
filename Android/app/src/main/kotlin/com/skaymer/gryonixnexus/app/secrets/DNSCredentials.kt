package com.skaymer.gryonixnexus.app.secrets

import com.skaymer.gryonixnexus.app.configurator.DNSProviderKind
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import java.util.UUID

data class DNSCredential(val id: String, val name: String, val kind: DNSProviderKind)

class DNSCredentials(private val store: SettingsStore, private val secrets: SecretStore) {
    val all: List<DNSCredential>
        get() = (store.stringList(IDS_KEY) ?: emptyList()).map { credential(it) }

    /** The credential the app publishes with when nothing else says */
    var selectedID: String?
        get() {
            val stored = store.string(SELECTED_KEY)
            return if (stored != null && all.any { it.id == stored }) stored else all.firstOrNull()?.id
        }
        set(value) {
            if (value == null) store.remove(SELECTED_KEY) else store.setString(SELECTED_KEY, value)
        }

    val selected: DNSCredential? get() = all.firstOrNull { it.id == selectedID }

    fun credential(id: String): DNSCredential = DNSCredential(id, name(id), kind(id))

    fun name(id: String): String = storedName(id) ?: kind(id).displayName

    fun storedName(id: String): String? = store.string(NAME_PREFIX + id)

    fun kind(id: String): DNSProviderKind =
        store.string(KIND_PREFIX + id)?.let { raw ->
            DNSProviderKind.entries.firstOrNull { it.name == raw }
        } ?: DNSProviderKind.CLOUDFLARE

    /** A new, empty credential */
    fun add(name: String, kind: DNSProviderKind): DNSCredential {
        val id = UUID.randomUUID().toString()
        store.setStringList(IDS_KEY, all.map { it.id } + id)
        write(id, name, kind)
        if (store.string(SELECTED_KEY) == null) store.setString(SELECTED_KEY, id)
        return credential(id)
    }

    fun update(id: String, name: String, kind: DNSProviderKind) = write(id, name, kind)

    /** Forget a credential and every token under it */
    fun remove(id: String) {
        val credential = credential(id)
        secrets.deleteSecret(tokenKey(credential.id, credential.kind))
        secrets.deleteSecret(tunnelKey(credential.id))
        store.remove(NAME_PREFIX + id)
        store.remove(KIND_PREFIX + id)
        val left = all.map { it.id }.filterNot { it == id }
        store.setStringList(IDS_KEY, left)
        if (store.string(SELECTED_KEY) == id) {
            if (left.isEmpty()) store.remove(SELECTED_KEY) else store.setString(SELECTED_KEY, left.first())
        }
    }

    /** The list this device already had, made real */
    fun adoptStoredTokensIfNeeded() {
        if (store.stringList(IDS_KEY) != null) return
        val adopted = mutableListOf<Triple<String, String, DNSProviderKind>>()

        val storedAccounts = store.stringList(LEGACY_CLOUDFLARE_IDS)
        for (id in storedAccounts ?: listOf(CLOUDFLARE_FIRST_ID)) {
            val hasDNS = secrets.string(tokenKey(id, DNSProviderKind.CLOUDFLARE)).isNullOrEmpty().not()
            val hasTunnel = secrets.string(tunnelKey(id)).isNullOrEmpty().not()
            if (storedAccounts == null && !hasDNS && !hasTunnel) continue
            val name = store.string(LEGACY_CLOUDFLARE_NAME_PREFIX + id)
                ?: DNSProviderKind.CLOUDFLARE.displayName
            adopted += Triple(id, name, DNSProviderKind.CLOUDFLARE)
        }

        for (kind in DNSProviderKind.entries) {
            if (kind == DNSProviderKind.CLOUDFLARE) continue
            val id = adoptedID(kind)
            if (secrets.string(tokenKey(id, kind)).isNullOrEmpty()) continue
            adopted += Triple(id, kind.displayName, kind)
        }

        if (adopted.isEmpty()) return
        adopted.forEach { (id, name, kind) -> write(id, name, kind) }
        store.setStringList(IDS_KEY, adopted.map { it.first })
        val previousKind = store.string(LEGACY_DEFAULT_KIND)?.let { raw ->
            DNSProviderKind.entries.firstOrNull { it.name == raw }
        } ?: DNSProviderKind.CLOUDFLARE
        val previous = if (previousKind == DNSProviderKind.CLOUDFLARE) {
            store.string(LEGACY_CLOUDFLARE_SELECTED) ?: CLOUDFLARE_FIRST_ID
        } else {
            adoptedID(previousKind)
        }
        store.setString(
            SELECTED_KEY,
            if (adopted.any { it.first == previous }) previous else adopted.first().first,
        )
    }

    private fun write(id: String, name: String, kind: DNSProviderKind) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) store.remove(NAME_PREFIX + id) else store.setString(NAME_PREFIX + id, trimmed)
        store.setString(KIND_PREFIX + id, kind.name)
    }

    companion object {
        const val IDS_KEY = "dns.credentials"
        const val SELECTED_KEY = "dns.credentials.selected"
        const val NAME_PREFIX = "dns.credential.name."
        const val KIND_PREFIX = "dns.credential.kind."

        const val CLOUDFLARE_FIRST_ID = "default"

        /** The keys the two old stores wrote */
        const val LEGACY_CLOUDFLARE_IDS = "cloudflare.accounts"
        const val LEGACY_CLOUDFLARE_SELECTED = "cloudflare.selectedAccount"
        const val LEGACY_CLOUDFLARE_NAME_PREFIX = "cloudflare.name."
        const val LEGACY_DEFAULT_KIND = "dns.defaultProviderKind"

        fun adoptedID(kind: DNSProviderKind): String = "kind.${kind.name}"

        fun tokenKey(id: String, kind: DNSProviderKind): String = when {
            kind == DNSProviderKind.CLOUDFLARE ->
                if (id == CLOUDFLARE_FIRST_ID) "cloudflare-api-token" else "cloudflare-api-token.$id"
            id == adoptedID(kind) -> "dns-provider-token.${kind.name}"
            else -> "dns-credential-token.$id"
        }

        fun tunnelKey(id: String): String =
            if (id == CLOUDFLARE_FIRST_ID) "cloudflare-tunnel-api-token"
            else "cloudflare-tunnel-api-token.$id"
    }
}

/** A credential's tokens, behind the platform keystore and nowhere else */
class DNSCredentialTokenStore(private val store: SecretStore) {
    fun token(credential: DNSCredential): String? =
        read(DNSCredentials.tokenKey(credential.id, credential.kind))

    fun setToken(credential: DNSCredential, value: String?) =
        write(DNSCredentials.tokenKey(credential.id, credential.kind), value)

    fun tunnelToken(credential: DNSCredential): String? =
        if (credential.kind == DNSProviderKind.CLOUDFLARE) {
            read(DNSCredentials.tunnelKey(credential.id))
        } else {
            null
        }

    fun setTunnelToken(credential: DNSCredential, value: String?) =
        write(DNSCredentials.tunnelKey(credential.id), value)

    /** Changing a credential's provider moves its token with it */
    fun move(credential: DNSCredential, kind: DNSProviderKind) {
        if (kind == credential.kind) return
        val token = token(credential)
        val tunnel = tunnelToken(credential)
        setToken(credential, null)
        setTunnelToken(credential, null)
        val moved = credential.copy(kind = kind)
        if (token != null) setToken(moved, token)
        if (tunnel != null && kind == DNSProviderKind.CLOUDFLARE) setTunnelToken(moved, tunnel)
    }

    fun currentCloudflareTunnelToken(credentials: DNSCredentials): String? {
        val chosen = credentials.selected?.takeIf { it.kind == DNSProviderKind.CLOUDFLARE }
            ?: credentials.all.firstOrNull { it.kind == DNSProviderKind.CLOUDFLARE }
            ?: return null
        return read(DNSCredentials.tunnelKey(chosen.id))
    }

    private fun read(key: String): String? {
        val stored = store.string(key)
        return if (stored.isNullOrEmpty()) null else stored
    }

    private fun write(key: String, value: String?) {
        val trimmed = value?.trim()
        if (trimmed.isNullOrEmpty()) store.deleteSecret(key) else store.setString(key, trimmed)
    }
}
