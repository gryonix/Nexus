package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.Topology
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test

class HomeOnlyTest {
    private fun relay(homeOnly: Set<ServiceID>) = Deployment(
        id = "A", name = "R", topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        entry = HostEndpoint("203.0.113.10", user = "server-user"),
        homeWGAddress = "10.8.0.2", homeOnlyServices = homeOnly,
    )

    @Test
    fun homeOnlyServicesRoundTrip() {
        val text = DeploymentListCodec.encode(listOf(relay(setOf(ServiceID.NEXTCLOUD))))
        assertEquals(setOf(ServiceID.NEXTCLOUD), DeploymentListCodec.decode(text).single().homeOnlyServices)
    }

    @Test
    fun emptyHomeOnlyIsOmitted() {
        assertFalse(DeploymentListCodec.encode(listOf(relay(emptySet()))).contains("homeOnlyServices"))
    }

    private fun deployment(
        homeOnly: Set<ServiceID> = emptySet(),
        noVPN: Set<ServiceID> = emptySet(),
        removed: Set<ServiceID> = emptySet(),
        services: Set<ServiceID> = emptySet(),
    ) = relay(homeOnly).copy(domain = "example.com", services = services, homeOnlyNoVPN = noVPN, homeOnlyDNSRemoved = removed)

    @Test
    fun noVPNAndRemovedRecordsRoundTrip() {
        val text = DeploymentListCodec.encode(listOf(deployment(setOf(ServiceID.NEXTCLOUD), setOf(ServiceID.NEXTCLOUD), setOf(ServiceID.NEXTCLOUD))))
        val back = DeploymentListCodec.decode(text).single()
        assertEquals(setOf(ServiceID.NEXTCLOUD), back.homeOnlyNoVPN)
        assertEquals(setOf(ServiceID.NEXTCLOUD), back.homeOnlyDNSRemoved)
    }

    @Test
    fun emptyNoVPNAndRemovedRecordsAreOmitted() {
        val text = DeploymentListCodec.encode(listOf(deployment(setOf(ServiceID.NEXTCLOUD))))
        assertFalse(text.contains("homeOnlyNoVPN"))
        assertFalse(text.contains("homeOnlyDNSRemoved"))
    }

    @Test
    fun onlyHomeOnlyServicesRefuseVPN() {
        val both = deployment(setOf(ServiceID.NEXTCLOUD), setOf(ServiceID.NEXTCLOUD, ServiceID.VAULTWARDEN), services = setOf(ServiceID.NEXTCLOUD, ServiceID.VAULTWARDEN))
        assertEquals(listOf("files.example.com"), both.hostsRefusingVPN)
        assertEquals(emptyList<String>(), deployment(setOf(ServiceID.NEXTCLOUD), services = setOf(ServiceID.NEXTCLOUD)).hostsRefusingVPN)
    }

    @Test
    fun theSSHCommandCarriesTheNoVPNList() {
        assertEquals("sudo /opt/gryonixnexus-admin-lockdown.sh only a.example.com", CommandCatalog.AdminLockdown.only(listOf("a.example.com")))
        assertEquals(
            "sudo /opt/gryonixnexus-admin-lockdown.sh only a.example.com b.example.com --no-vpn b.example.com",
            CommandCatalog.AdminLockdown.only(listOf("a.example.com", "b.example.com"), listOf("b.example.com")),
        )
        assertEquals(true, CommandCatalog.AdminLockdown.only(listOf("a.example.com"), emptyList()).endsWith("--no-vpn"))
    }

    @Test
    fun aProbeVerdictNamesOnlyTheOpenPortsAsked() {
        assertEquals(PublicPortProbe.Verdict.Closed, PublicPortProbe.verdict(listOf(25, 993), emptyList()))
        assertEquals(PublicPortProbe.Verdict.Open(listOf(25, 993)), PublicPortProbe.verdict(listOf(25, 993), listOf(993, 25, 8080)))
    }

    @Test
    fun aServiceProbesItsOwnPortsNotTheWebPorts() {
        val mail = ServiceRegistry.service(ServiceID.DOCKER_MAILSERVER)!!
        val vault = ServiceRegistry.service(ServiceID.VAULTWARDEN)!!
        val d = deployment(setOf(ServiceID.DOCKER_MAILSERVER), services = setOf(ServiceID.DOCKER_MAILSERVER, ServiceID.VAULTWARDEN))
        assertEquals(true, 25 in PublicPortProbe.ports(mail, d))
        assertEquals(false, 443 in PublicPortProbe.ports(mail, d))
        assertEquals(emptyList<Int>(), PublicPortProbe.ports(vault, d))
    }

    @Test
    fun theCertificateFileGetsASafeName() {
        assertEquals("my-home-server-root-ca.crt", InternalCertificate.fileName("My Home Server!"))
        assertEquals("server-root-ca.crt", InternalCertificate.fileName("!!"))
        assertEquals(false, InternalCertificate.isPem("not a certificate"))
        assertEquals(true, InternalCertificate.isPem("-----BEGIN CERTIFICATE-----\nAA==\n-----END CERTIFICATE-----"))
    }
}
