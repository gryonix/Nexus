package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry

object ServiceGrouping {
    const val OVERRIDE_KEY = "dashboard.groupServicesByCategory"

    fun groups(services: Collection<ServiceID>, override: Boolean?): Boolean =
        override ?: aShelfHoldsSeveral(services)

    /** Whether any category would hold two or more ROWS */
    fun aShelfHoldsSeveral(services: Collection<ServiceID>): Boolean {
        val seen = mutableSetOf<ServiceCategory>()
        for (id in services) {
            val category = ServiceRegistry.service(id)?.displayCategory ?: continue
            if (!seen.add(category)) return true
        }
        return false
    }
}
