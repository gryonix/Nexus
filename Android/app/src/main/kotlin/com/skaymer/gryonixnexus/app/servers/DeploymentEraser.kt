package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.app.access.AccessCredentialStore
import com.skaymer.gryonixnexus.app.access.InstallReportStore
import com.skaymer.gryonixnexus.app.secrets.DeploymentSecrets
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.servercontrol.Deployment

class DeploymentEraser(
    private val secrets: SecretStore,
    private val settings: com.skaymer.gryonixnexus.app.shell.SettingsStore? = null,
) {
    fun erase(deployment: Deployment) {
        DeploymentSecrets(secrets, deployment.id).forget(deployment.nodes)
        AccessCredentialStore(secrets, deployment.id).delete()
        InstallReportStore(secrets, deployment.id).delete()
        settings?.let { ServerAccessStore.forget(it, deployment.id) }
    }
}
