package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.PairingCode
import com.skaymer.gryonixnexus.app.secrets.DeploymentSecrets
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.transport.AppSSHKeyGenerator
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.transport.SSHJCommandRunner
import java.util.concurrent.ConcurrentHashMap
import kotlin.time.Duration.Companion.seconds

/** A one-time SSH key an export file carries */
class TransferKey(val seed: ByteArray, val id: String)

suspend fun mintTransferKey(client: AgentClient): TransferKey? {
    val minted = runCatching { client.createTransfer(validMinutes = 60) }.getOrNull() ?: return null
    if (minted.private_key_seed.size != 32 || minted.transfer_id.isEmpty()) return null
    return TransferKey(minted.private_key_seed.toByteArray(), minted.transfer_id)
}

class TransferClaim(
    private val secrets: SecretStore,
    private val deviceUID: () -> String,
    private val deviceLabel: () -> String,
) {
    private val claiming = ConcurrentHashMap.newKeySet<String>()

    suspend fun claimIfPending(deployment: Deployment, runner: SSHJCommandRunner, client: AgentClient) {
        val kept = DeploymentSecrets(secrets, deployment.id)
        val transferID = kept.pendingTransferID() ?: return
        if (!claiming.add(deployment.id)) return
        try {
            val own = AppSSHKeyGenerator.generate()
            val code = pairingCode(deployment, runner) ?: return
            val paired = runCatching {
                client.pairing(code, own.publicKeyOpenSSH, deviceLabel(), deviceUID(), true, transferID)
            }.getOrNull()
            if (paired?.ssh_key_authorized != true) return
            kept.setIdentitySeed(own.privateKeySeed)
            kept.clearPendingTransfer()
        } finally {
            claiming.remove(deployment.id)
        }
    }

    private suspend fun pairingCode(deployment: Deployment, runner: SSHJCommandRunner): String? {
        val result = runCatching {
            runner.run(AdoptViewModel.PAIR_CODE_COMMAND, deployment.servicesHost, 30.seconds)
        }.getOrNull() ?: return null
        return if (result.succeeded) PairingCode.parse(result.stdout) else null
    }
}
