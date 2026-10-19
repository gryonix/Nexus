package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry

/** One installed service's own web address */
data class WebSite(val id: ServiceID, val name: String, val host: String) {
    val url: String get() = "https://$host"
}

object WebSites {
    fun of(services: Set<ServiceID>, context: ServiceContext): List<WebSite> =
        all(services, context).filter { !it.host.endsWith(".") }

    fun needDomain(services: Set<ServiceID>, context: ServiceContext): Boolean =
        all(services, context).any { it.host.endsWith(".") }

    private fun all(services: Set<ServiceID>, context: ServiceContext): List<WebSite> =
        ServiceRegistry.services(services).mapNotNull { service: ManagedService ->
            service.webIngress(context)?.let {
                WebSite(id = service.id, name = service.displayName, host = it.hostname)
            }
        }
}
