package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceContext

/** The address a service row shows, or nothing */
object ServiceAddress {
    fun of(service: ManagedService, context: ServiceContext): String? {
        val hostname = service.webIngress(context)?.hostname ?: return null
        if (hostname.isEmpty() || hostname.endsWith(".")) return null
        return hostname
    }
}
