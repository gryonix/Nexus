package com.skaymer.gryonixnexus.app.install

import com.skaymer.gryonixnexus.app.secrets.AppIdentities
import com.skaymer.gryonixnexus.app.secrets.DeploymentSecrets
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.transport.SSHClients
import com.skaymer.gryonixnexus.transport.SSHConnectionSettings
import com.skaymer.gryonixnexus.transport.SSHJCommandRunner
import com.skaymer.gryonixnexus.transport.TOFUHostKeyVerifier
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import net.schmizz.sshj.SSHClient

class InstallSessions(private val secrets: SecretStore) {
    fun runner(deploymentID: String, target: InstallTarget): SSHJCommandRunner {
        com.skaymer.gryonixnexus.app.licensing.LicenseGate.check(deploymentID)
        val store = DeploymentSecrets(secrets, deploymentID)
        val settings = settings(deploymentID, target)
        return SSHJCommandRunner(
            settings = settings,
            onPinHostKey = { _, key -> store.setHostKeyPin(key, target.slot) },
            connect = { address, host -> dial(address, host, settings, store, target) },
        )
    }

    /** The install's own connection parameters */
    fun settings(deploymentID: String, target: InstallTarget): SSHConnectionSettings {
        val identity = AppIdentities(secrets).identity(deploymentID)
        val secret = target.secret
        return SSHConnectionSettings(
            vpsHost = target.address.trim(),
            vpsPort = target.port,
            username = target.username.trim(),
            homeHost = "",
            privateKeySeed = identity.privateKeySeed,
            passwords = when (secret) {
                is InstallTarget.Secret.Password -> mapOf(SSHHostID.VPS to secret.value)
                InstallTarget.Secret.AppKey -> emptyMap()
            },
            pinnedVPSHostKey = DeploymentSecrets(secrets, deploymentID).hostKeyPin(target.slot),
        )
    }

    private suspend fun dial(
        address: SSHConnectionSettings.Route.Address,
        host: SSHHostID,
        settings: SSHConnectionSettings,
        store: DeploymentSecrets,
        target: InstallTarget,
    ): SSHClient = withContext(Dispatchers.IO) {
        SSHClients.redialing {
            val client = SSHClients.create()
            client.addHostKeyVerifier(
                TOFUHostKeyVerifier(
                    hostLabel = target.address,
                    pinnedKey = store.hostKeyPin(target.slot),
                    onPin = { key -> store.setHostKeyPin(key, target.slot) },
                )
            )
            SSHClients.signIn(client) {
                connect(address.host, address.port)
                SSHJCommandRunner.authenticate(this, settings, host)
            }
        }
    }
}
