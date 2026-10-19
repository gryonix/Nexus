package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.services.MailcowService
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test

class PortalPathsTest {
    @Test
    fun `only mailcow admin pages ask for the portal, as the Swift generator renders it`() {
        val site = ServiceInfraSections.caddySite(
            owner = "mailcow", hostname = "mail.example.com", upstreamPort = 18443,
            adminGuard = true, upstreamHTTPS = true, sso = true,
        )
        val swift = javaClass.getResource("/caddy-mailcow-portal-paths.txt")!!.readText()
        assertEquals(swift, site)
        assertFalse(ServiceInfraSections.caddySite(
            owner = "nextcloud", hostname = "files.example.com", upstreamPort = 8081, adminGuard = true, sso = true,
        ).contains("handle"))
    }

    @Test
    fun `mailcow sync paths skip the guard and the portal, as the Swift generator renders it`() {
        val site = ServiceInfraSections.caddySite(
            owner = "mailcow", hostname = "mail.example.com", upstreamPort = 18443,
            adminGuard = true, upstreamHTTPS = true, sso = true, publicPaths = MailcowService.SYNC_PATHS,
        )
        val swift = javaClass.getResource("/caddy-mailcow-sync-paths.txt")!!.readText()
        assertEquals(swift, site)
    }
}
