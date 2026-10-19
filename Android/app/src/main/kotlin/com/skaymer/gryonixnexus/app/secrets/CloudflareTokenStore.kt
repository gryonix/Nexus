package com.skaymer.gryonixnexus.app.secrets

import com.skaymer.gryonixnexus.app.configurator.DNSProviderKind

class CloudflareTokenStore(
    private val store: SecretStore,
    /** Which account the tokens below belong to */
    private val selectedAccount: () -> String = { DNSCredentials.CLOUDFLARE_FIRST_ID },
) {
    var dnsToken: String?
        get() = read(DNSCredentials.tokenKey(selectedAccount(), DNSProviderKind.CLOUDFLARE))
        set(value) = write(DNSCredentials.tokenKey(selectedAccount(), DNSProviderKind.CLOUDFLARE), value)

    var tunnelToken: String?
        get() = read(DNSCredentials.tunnelKey(selectedAccount()))
        set(value) = write(DNSCredentials.tunnelKey(selectedAccount()), value)

    fun dnsToken(accountID: String): String? = read(DNSCredentials.tokenKey(accountID, DNSProviderKind.CLOUDFLARE))

    fun setDNSToken(accountID: String, value: String?) =
        write(DNSCredentials.tokenKey(accountID, DNSProviderKind.CLOUDFLARE), value)

    fun tunnelToken(accountID: String): String? = read(DNSCredentials.tunnelKey(accountID))

    fun setTunnelToken(accountID: String, value: String?) =
        write(DNSCredentials.tunnelKey(accountID), value)

    /** Whether this app can mint a connector token at all */
    val canIssueTunnelToken: Boolean get() = tunnelToken != null

    private fun read(account: String): String? {
        val stored = store.string(account)
        return if (stored.isNullOrEmpty()) null else stored
    }

    private fun write(account: String, value: String?) {
        val trimmed = value?.trim()
        if (trimmed.isNullOrEmpty()) store.deleteSecret(account) else store.setString(account, trimmed)
    }
}
