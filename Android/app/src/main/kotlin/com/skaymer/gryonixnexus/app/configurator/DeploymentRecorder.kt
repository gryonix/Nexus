package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.app.licensing.LicenseGate
import com.skaymer.gryonixnexus.app.secrets.DeploymentSecrets
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.InstalledDeploymentRecord
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import java.util.UUID

class DeploymentRecorder(
    private val fleet: FleetRepository,
    private val secrets: SecretStore,
) {
    /** The id this form's server should have */
    fun identify(form: ConfiguratorForm, carried: String?): String {
        val domain = form.domain.trim().lowercase()
        val existing = fleet.deployments.value.firstOrNull {
            it.topology == form.topology && it.domain == domain
        }
        if (existing != null) return existing.id
        if (carried != null && fleet.deployments.value.none { it.id == carried }) return carried
        return UUID.randomUUID().toString().uppercase()
    }

    fun record(
        id: String,
        form: ConfiguratorForm,
        services: Set<ServiceID>,
        passwords: Map<SSHHostID, String>,
    ): Deployment {
        val domain = form.domain.trim().lowercase()
        val generated = Deployment(
            id = id,
            name = domain,
            topology = form.topology,
            domain = domain,
            additionalDomains = form.additionalDomains
                .map { it.trim().lowercase() }
                .filter { it.isNotEmpty() },
            entry = HostEndpoint(
                host = form.publicIP.trim(),
                user = form.dashboardSSHUser.trim().lowercase(),
            ),
            homeWGAddress =
                if (form.topology == Topology.VPS_RELAY_WITH_HOME_BACKEND) form.homeVPNIP else null,
            services = services,
            serviceSettings = form.serviceSettings,
            usesPasswordAuth = form.useExistingUser,
            scope = form.scope,
        )
        val deployment = InstalledDeploymentRecord.merged(
            generated = generated,
            existing = fleet.deployments.value.firstOrNull { it.id == id },
        )
        if (!LicenseGate.unlocked) return deployment
        val store = DeploymentSecrets(secrets, id)
        for ((host, password) in passwords) {
            if (password.isNotEmpty()) store.setPassword(password, host)
        }
        fleet.add(deployment)
        return deployment
    }
}
