package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import gryonixnexusd.v1.VaultwardenTwoFactor

/** How many Vaultwarden accounts have no two-factor login */
data class VaultwardenTwoFactorStatus(val users: Int, val usersWithoutTwoFactor: Int) {
    val needsAttention: Boolean get() = usersWithoutTwoFactor > 0

    companion object {
        /** Null when the agent could not read the database */
        fun from(answer: VaultwardenTwoFactor): VaultwardenTwoFactorStatus? =
            if (answer.readable) {
                VaultwardenTwoFactorStatus(answer.users, answer.users_without_two_factor)
            } else {
                null
            }
    }
}

class AgentVaultwardenOperations(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) {
    suspend fun twoFactor(): VaultwardenTwoFactorStatus? =
        agentFailure("vaultwarden") { gate.gated { VaultwardenTwoFactorStatus.from(client.vaultwardenTwoFactor()) } }
}
