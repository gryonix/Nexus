package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.ComposeFile
import com.skaymer.gryonixnexus.catalog.FirewallPort
import com.skaymer.gryonixnexus.catalog.L10nServices
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.PrivilegedCommand
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.ServiceActions
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServicePower
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress

class XrayRealityService : ManagedService {
    override val id = ServiceID.XRAY_REALITY
    override val displayName = "VLESS / Reality"
    override val systemImage = "eye.slash"
    override val category = ServiceCategory.VPN
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.vpnHostname
        return if (custom.isEmpty()) "vpn.${context.domain}" else custom
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.xrayRealityPath
        val port = context.settings.xrayRealityPort
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              xray:
                image: $IMAGE
                container_name: $CONTAINER_NAME
                restart: unless-stopped
                # Run as root (0:0): config.json is chmod 600 root-owned (setup
                # and the panel both keep it 600, since it holds the REALITY
                # private key), and the image runs as a non-root user that would
                # otherwise get "permission denied" reading it.
                user: "0:0"
                volumes:
                  - $path/config:$CONTAINER_CONFIG_DIR:ro
                ports:
                  - "$port:$port/tcp"
            """.trimIndent(),
            envTemplate = null
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.xrayRealityPath
        val port = context.settings.xrayRealityPort
        val sni = context.settings.xrayRealitySNI
        val host = hostname(context)
        val lang = context.language
        return listOf("""
        log "VLESS/Reality: ${L10nServices.serviceStarting(lang)}"
        install -d $path/config
        cd $path
        # First run only: generate the UUID, the x25519 keypair and a shortId
        # on this server, then bake them into the config and the client link.
        if [ ! -f config/config.json ]; then
          docker pull -q $IMAGE >/dev/null
          XRAY_UUID="${SH}(docker run --rm $IMAGE uuid | tr -d '\r\n')"
          XRAY_KEYS="${SH}(docker run --rm $IMAGE x25519)"
          # Format changed across releases; accept "PrivateKey:" + "Password
          # (PublicKey):" (26.7), plain "Password:" and the older
          # "Private key:"/"Public key:". [^:]* swallows the "(PublicKey)" part.
          XRAY_PRIV="${SH}(printf '%s\n' "${SH}XRAY_KEYS" | sed -n -e 's/^PrivateKey:[[:space:]]*//p' -e 's/^Private key:[[:space:]]*//p' | head -n1)"
          XRAY_PUB="${SH}(printf '%s\n' "${SH}XRAY_KEYS" | sed -n -e 's/^Password[^:]*:[[:space:]]*//p' -e 's/^Public key:[[:space:]]*//p' | head -n1)"
          XRAY_SID="${SH}(openssl rand -hex 8)"
          [ -n "${SH}XRAY_PRIV" ] && [ -n "${SH}XRAY_PUB" ] || fail "xray x25519 returned an empty key"
          cat > config/config.json <<EOF_XRAY_CONFIG
        {
            "log": { "loglevel": "warning" },
            "inbounds": [
                {
                    "listen": "0.0.0.0",
                    "port": $port,
                    "protocol": "vless",
                    "settings": {
                        "clients": [ { "id": "${SH}{XRAY_UUID}", "flow": "xtls-rprx-vision" } ],
                        "decryption": "none"
                    },
                    "streamSettings": {
                        "network": "tcp",
                        "security": "reality",
                        "realitySettings": {
                            "dest": "$sni:443",
                            "serverNames": [ "$sni" ],
                            "privateKey": "${SH}{XRAY_PRIV}",
                            "shortIds": [ "${SH}{XRAY_SID}" ]
                        }
                    },
                    "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ], "routeOnly": true }
                }
            ],
            "outbounds": [ { "protocol": "freedom", "tag": "direct" } ]
        }
        EOF_XRAY_CONFIG
          # The client link needs the PUBLIC key + shortId, which are not in the
          # server config — persist the ready vless:// link for the report.
          printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp#gryonixNexus\n' \
            "${SH}XRAY_UUID" "$host" "$port" "$sni" "${SH}XRAY_PUB" "${SH}XRAY_SID" > link.txt
        fi
        chmod 600 config/config.json link.txt
        docker compose -p $COMPOSE_PROJECT pull -q
        docker compose -p $COMPOSE_PROJECT up -d
        """.trimIndent())
    }

    override fun firewallPorts(context: ServiceContext) = listOf(
        FirewallPort(context.settings.xrayRealityPort, FirewallPort.Proto.TCP,
                     comment = "VLESS/Reality")
    )

    /** Not an HTTP service — no reverse proxy */
    override fun webIngress(context: ServiceContext): WebIngress? = null

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val path = context.settings.xrayRealityPath
        val port = context.settings.xrayRealityPort
        val lang = context.language
        val endpoint = "${hostname(context)}:$port"
        return listOf("""
        echo "VLESS/Reality: $endpoint (TCP)"
        echo "  ${L10nServices.xrayLinkLabel(lang)}:"
        echo "  ${SH}(cat $path/link.txt)"
        echo "  ${L10nServices.xrayClientsNote(lang)}"
        echo "  ${L10nServices.adminViaWireGuardNote(lang)}"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext) = ServiceActions(
        statusProbe = StatusProbe.Container(
            name = CONTAINER_NAME,
            list = PrivilegedCommand("/usr/bin/docker", "ps -a")
        ),
        restart = ServicePower.container(CONTAINER_NAME, "restart"),
        start = ServicePower.container(CONTAINER_NAME, "start"),
        stop = ServicePower.container(CONTAINER_NAME, "stop")
    )

    override fun updateSpec(context: ServiceContext) = UpdateSpec(images = listOf(IMAGE))

    companion object {
        const val COMPOSE_PROJECT = "xray"
        const val CONTAINER_NAME = "xray"

        const val IMAGE = "ghcr.io/xtls/xray-core:26.7.11"

        const val CONTAINER_CONFIG_DIR = "/usr/local/etc/xray"

        val SUGGESTED_SITES = listOf(
            "www.apple.com", "www.microsoft.com", "www.cloudflare.com", "dl.google.com",
            "www.samsung.com", "www.amazon.com", "www.nvidia.com", "addons.mozilla.org",
        )

        private val SITE_LABEL = Regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$")

        fun normalisedSite(text: String): String? {
            val site = text.trim().lowercase()
            val labels = site.split(".")
            if (site.length > 253 || labels.size < 2) return null
            return if (labels.all { SITE_LABEL.matches(it) }) site else null
        }
    }
}
