package com.skaymer.gryonixnexus.catalog

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class ForwardedPortsTest {
    private val context = ServiceContext(domain = "example.com", sshUser = "admin")

    @Test
    fun homeOnlyServiceKeepsItsOwnPortsOffTheRelay() {
        val services = ServiceRegistry.services(setOf(ServiceID.DOCKER_MAILSERVER, ServiceID.VAULTWARDEN))
        val ports = ForwardedPorts.tcp(services, context, setOf(ServiceID.DOCKER_MAILSERVER.rawValue))
        assertEquals(listOf(80, 443), ports)
    }

    @Test
    fun withoutExclusionsMailPortsAreForwarded() {
        val services = ServiceRegistry.services(setOf(ServiceID.DOCKER_MAILSERVER))
        assertEquals(true, 25 in ForwardedPorts.tcp(services, context))
    }
}
