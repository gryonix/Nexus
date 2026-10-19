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

class ShadowsocksService : ManagedService {
    override val id = ServiceID.SHADOWSOCKS
    override val displayName = "Shadowsocks"
    override val systemImage = "bolt.horizontal.circle"
    override val category = ServiceCategory.VPN
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.vpnHostname
        return if (custom.isEmpty()) "vpn.${context.domain}" else custom
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.shadowsocksPath
        val port = context.settings.shadowsocksPort
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              ssserver:
                image: $IMAGE
                container_name: $CONTAINER_NAME
                restart: unless-stopped
                # Explicit binary name: the image's entrypoint does not prepend
                # `ssserver` for a bare `-c …`, so `exec "${SH}@"` chokes on the
                # leading option ("exec: illegal option -c"). Run as root (0:0):
                # config.json is chmod 600 root-owned (setup and the panel both
                # keep it 600), so a non-root process could not read it.
                command: ssserver -c $CONTAINER_CONFIG_PATH
                user: "0:0"
                volumes:
                  - $path/config.json:$CONTAINER_CONFIG_PATH:ro
                ports:
                  - "$port:$port/tcp"
                  - "$port:$port/udp"
            """.trimIndent(),
            envTemplate = null
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.shadowsocksPath
        val port = context.settings.shadowsocksPort
        val lang = context.language
        return listOf("""
        log "Shadowsocks: ${L10nServices.serviceStarting(lang)}"
        install -d $path
        cd $path
        # First run only: generate the pre-shared key on this server (a
        # base64-encoded 32-byte key for the 2022 cipher); re-runs keep it.
        if [ ! -f config.json ]; then
          SS_PASSWORD="${SH}(openssl rand -base64 32)"
          cat > config.json <<EOF_SS_CONFIG
        {
            "server": "0.0.0.0",
            "server_port": $port,
            "password": "${SH}{SS_PASSWORD}",
            "method": "$METHOD",
            "mode": "tcp_and_udp",
            "timeout": 300
        }
        EOF_SS_CONFIG
        fi
        chmod 600 config.json
        docker compose -p $COMPOSE_PROJECT pull -q
        docker compose -p $COMPOSE_PROJECT up -d
        """.trimIndent())
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> {
        val port = context.settings.shadowsocksPort
        return listOf(
            FirewallPort(port, FirewallPort.Proto.TCP, comment = "Shadowsocks"),
            FirewallPort(port, FirewallPort.Proto.UDP, comment = "Shadowsocks")
        )
    }

    /** Not an HTTP service — no reverse proxy */
    override fun webIngress(context: ServiceContext): WebIngress? = null

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val path = context.settings.shadowsocksPath
        val port = context.settings.shadowsocksPort
        val lang = context.language
        val endpoint = "${hostname(context)}:$port"
        return listOf("""
        echo "Shadowsocks: $endpoint (TCP+UDP)"
        SS_PW="${SH}(sed -n 's/.*"password"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' $path/config.json | head -n 1)"
        SS_ENC="${SH}(printf '%s' "${SH}SS_PW" | sed -e 's/+/%2B/g' -e 's#/#%2F#g' -e 's/=/%3D/g')"
        echo "  ${L10nServices.shadowsocksLinkLabel(lang)}:"
        echo "  ss://$METHOD:${SH}{SS_ENC}@$endpoint#gryonixNexus"
        echo "  ${L10nServices.shadowsocksClientsNote(lang)}"
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
        const val COMPOSE_PROJECT = "shadowsocks"
        const val CONTAINER_NAME = "shadowsocks"

        const val METHOD = "2022-blake3-aes-256-gcm"
        const val IMAGE = "ghcr.io/shadowsocks/ssserver-rust:v1.24.0"

        const val CONTAINER_CONFIG_PATH = "/etc/shadowsocks-rust/config.json"
    }
}
