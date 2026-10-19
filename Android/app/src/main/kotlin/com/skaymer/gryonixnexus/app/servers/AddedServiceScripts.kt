package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.app.configurator.ConfiguratorForm
import com.skaymer.gryonixnexus.app.configurator.of
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.recipe.MailRecipe
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** Install scripts for services added to a running server */
object AddedServiceScripts {
    fun scripts(services: List<ManagedService>, deployment: Deployment): List<Artifact> {
        val wanted = services.map { it.id }.toMutableSet()
        if (wanted.any { it in ServiceID.VPN_PROTOCOLS }) wanted += ServiceID.VPN_PANEL
        val bundle = bundle(deployment.copy(services = deployment.services + wanted))
            ?: bundle(deployment.copy(services = wanted))
            ?: return emptyList()
        val names = wanted.map { "service-" + it.rawValue + ".sh" }.toSet()
        return bundle.serviceScripts.filter { it.fileName in names }
    }

    /** The setup bundle; null when the plan fails checks */
    private fun bundle(planned: Deployment) =
        runCatching { MailRecipe().generate(ConfiguratorForm.of(planned).toInput()) }.getOrNull()
}
