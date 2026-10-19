package com.skaymer.gryonixnexus.catalog

import com.skaymer.gryonixnexus.catalog.services.VPNPanelService

/** A first-visitor site stays VPN-only until its account exists */
object CaddySetupGuard {
    const val DIRECTORY = "/etc/caddy/gryonixnexus-setup"

    /** Sites whose first visitor becomes their administrator */
    val FIRST_VISITOR_ADMIN: List<ServiceID> = listOf(
        ServiceID.IMMICH, ServiceID.JELLYFIN, ServiceID.HOME_ASSISTANT,
        ServiceID.N8N, ServiceID.OPEN_WEB_UI, ServiceID.ANYTHING_LLM,
    )

    private const val DENIAL =
        "This site opens to the internet once its first account exists. Connect to your WireGuard VPN to create it."

    val RULES: String = """
        @gryonixnexus_setup_relay {
            remote_ip 10.8.0.0/24
            not remote_ip 10.8.0.254/32
        }
        respond @gryonixnexus_setup_relay "$DENIAL" 403
        @gryonixnexus_setup_public not remote_ip private_ranges
        respond @gryonixnexus_setup_public "$DENIAL" 403
        @gryonixnexus_setup_tunnel header Cf-Connecting-IP *
        respond @gryonixnexus_setup_tunnel "$DENIAL" 403
    """.trimIndent() + "\n"

    fun importLine(owner: String): String = "import $DIRECTORY/$owner*"

    /** Without WireGuard nobody could reach a guarded site */
    fun applies(owner: String, installed: Set<ServiceID>): Boolean =
        ServiceID.WIREGUARD_VPN in installed && ServiceID(owner) in FIRST_VISITOR_ADMIN

    fun guarding(site: String, owner: String, installed: Set<ServiceID>): String {
        if (!applies(owner, installed)) return site
        val at = site.indexOf("import ${VPNPanelService.ADMIN_GUARD_PATH}")
        if (at < 0) return site
        val lineStart = site.lastIndexOf('\n', at - 1) + 1
        val indent = site.substring(lineStart, at)
        return site.substring(0, at) + importLine(owner) + "\n" + indent + site.substring(at)
    }

    fun armSection(owners: List<String>): String = owners.joinToString("") { owner ->
        "\n" + """
            if ! grep -qE '^[[:space:]]*# gryonixnexus: $owner$' /etc/caddy/Caddyfile 2>/dev/null; then
              install -d -m 755 $DIRECTORY
              cat > $DIRECTORY/$owner <<'EOF_SETUP_GUARD'
            @RULES@EOF_SETUP_GUARD
              chmod 644 $DIRECTORY/$owner
            fi
        """.trimIndent().embedding("RULES" to RULES)
    }
}
