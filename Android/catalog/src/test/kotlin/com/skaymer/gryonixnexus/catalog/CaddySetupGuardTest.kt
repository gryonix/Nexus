package com.skaymer.gryonixnexus.catalog

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class CaddySetupGuardTest {
    private val site = "photos.example.com {\n    # gryonixnexus: immich\n    import /etc/caddy/gryonixnexus-admin-guard\n    reverse_proxy 127.0.0.1:2283\n}"

    @Test
    fun `a first visitor site waits behind the VPN only with WireGuard`() {
        val guarded = CaddySetupGuard.guarding(site, "immich", setOf(ServiceID.IMMICH, ServiceID.WIREGUARD_VPN))
        assertTrue(guarded.contains("    import /etc/caddy/gryonixnexus-setup/immich*\n    import /etc/caddy/gryonixnexus-admin-guard"))
        assertEquals(site, CaddySetupGuard.guarding(site, "immich", setOf(ServiceID.IMMICH)))
        assertEquals(site, CaddySetupGuard.guarding(site, "vaultwarden", setOf(ServiceID.WIREGUARD_VPN)))
    }

    @Test
    fun `the rules match the agent's byte for byte`() {
        val denial = "This site opens to the internet once its first account exists. Connect to your WireGuard VPN to create it."
        val expected = "@gryonixnexus_setup_relay {\n    remote_ip 10.8.0.0/24\n    not remote_ip 10.8.0.254/32\n}\nrespond @gryonixnexus_setup_relay \"$denial\" 403\n@gryonixnexus_setup_public not remote_ip private_ranges\nrespond @gryonixnexus_setup_public \"$denial\" 403\n@gryonixnexus_setup_tunnel header Cf-Connecting-IP *\nrespond @gryonixnexus_setup_tunnel \"$denial\" 403\n"
        assertEquals(expected, CaddySetupGuard.RULES)
    }

    @Test
    fun `the guard is armed only for a site the host does not serve yet`() {
        val section = CaddySetupGuard.armSection(listOf("n8n"))
        assertTrue(section.startsWith("\nif ! grep -qE '^[[:space:]]*# gryonixnexus: n8n\$' /etc/caddy/Caddyfile"))
        assertTrue(section.contains("<<'EOF_SETUP_GUARD'\n@gryonixnexus_setup_relay {"))
        assertTrue(section.contains("403\nEOF_SETUP_GUARD\n"))
        assertEquals("", CaddySetupGuard.armSection(emptyList()))
    }
}
