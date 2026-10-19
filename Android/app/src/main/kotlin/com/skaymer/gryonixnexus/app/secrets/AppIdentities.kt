package com.skaymer.gryonixnexus.app.secrets

import com.skaymer.gryonixnexus.servercontrol.AppSSHIdentity
import com.skaymer.gryonixnexus.transport.AppSSHKeyGenerator

class AppIdentities(private val store: SecretStore) {
    fun identity(deploymentID: String): AppSSHIdentity {
        val secrets = DeploymentSecrets(store, deploymentID)
        secrets.identitySeed()?.let { return AppSSHKeyGenerator.identity(it) }
        val fresh = AppSSHKeyGenerator.generate()
        secrets.setIdentitySeed(fresh.privateKeySeed)
        return fresh
    }

    /** The `authorized_keys` line the install pastes into the server */
    fun publicKey(deploymentID: String): String = identity(deploymentID).publicKeyOpenSSH

    /** Throws this server's identity away and mints a new one */
    fun regenerate(deploymentID: String): AppSSHIdentity {
        DeploymentSecrets(store, deploymentID).forgetIdentitySeed()
        return identity(deploymentID)
    }
}
