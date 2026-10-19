package com.skaymer.gryonixnexus.app.access

import com.skaymer.gryonixnexus.agentcontrol.VaultMerge
import gryonixnexusd.v1.VaultEntry

/** The passwords screen's side of the server-held vault */
object AccessVault {
    /** What a Save sends to the server */
    fun entriesToPush(
        accounts: List<AccessAccount>,
        nowMillis: Long,
        writer: String,
    ): List<VaultEntry> = accounts.mapNotNull { account ->
        if (account.isChanged) {
            entry(account, updatedAt = nowMillis, updatedBy = writer)
        } else if (account.isEmptyCredential) {
            null
        } else {
            entry(account, updatedAt = 0, updatedBy = SEEDED_BY)
        }
    }

    fun applying(remote: List<VaultEntry>, accounts: List<AccessAccount>): List<AccessAccount> {
        val local = accounts.map { entry(it, updatedAt = it.updatedAt, updatedBy = it.updatedBy) }
        val winners = VaultMerge.resolved(local, remote).associateBy { it.id }
        val updated = accounts.mapNotNull { account ->
            val winner = winners[account.id] ?: return@mapNotNull account
            if (winner.deleted) return@mapNotNull null
            account.copy(
                login = winner.login,
                password = winner.password,
                token = winner.token,
                hasToken = account.hasToken || winner.token.isNotEmpty(),
                updatedAt = winner.updated_at,
                updatedBy = winner.updated_by,
            ).markingLoaded()
        }
        val known = accounts.map { it.id }.toSet()
        val fromServer = winners.values
            .filter { it.id !in known && !it.deleted && it.service_secret.isEmpty() }
            .sortedBy { it.id }
            .map { AccessAccount.fromServer(it) }
        return updated + fromServer
    }

    const val SEEDED_BY = "agent"

    private fun entry(account: AccessAccount, updatedAt: Long, updatedBy: String) = VaultEntry(
        id = account.id,
        host = account.host,
        title = account.title,
        website = account.website.orEmpty(),
        login = account.login,
        password = account.password,
        token = account.token,
        updated_at = updatedAt,
        updated_by = updatedBy,
    )
}
