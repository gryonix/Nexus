package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.VPNPortShare
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

class AmneziaWGVPNService : ManagedService {
    override val id = ServiceID.AMNEZIA_WG
    override val displayName = "AmneziaWG"
    override val systemImage = "shield.lefthalf.filled.badge.checkmark"
    override val category = ServiceCategory.VPN
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.vpnHostname
        return if (custom.isEmpty()) "vpn.${context.domain}" else custom
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.amneziaWGPath
        val port = context.settings.amneziaWGPort
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              amnezia-wg-easy:
                image: $IMAGE
                container_name: $CONTAINER_NAME
                restart: unless-stopped
                cap_add:
                  - NET_ADMIN
                  - SYS_MODULE
                # Most kernels have no AmneziaWG module, so awg-quick falls back
                # to the userspace amneziawg-go, which needs a TUN device to
                # bring wg0 up. Without it the container crashlooped with
                # "RTNETLINK: Not supported" / "Protocol not supported".
                devices:
                  - /dev/net/tun:/dev/net/tun
                sysctls:
                  - net.ipv4.ip_forward=1
                  - net.ipv4.conf.all.src_valid_mark=1
                environment:
                  WG_HOST: ${hostname(context)}
                  WG_PORT: "$port"
                  # 10.10.0.x: clear of the relay tunnel (10.8.0.0/24) and the
                  # plain WireGuard VPN (10.9.0.0/24).
                  WG_DEFAULT_ADDRESS: 10.10.0.x
                  PASSWORD_HASH: ${SH}{PASSWORD_HASH}
                  PORT: "$WEB_UI_PORT"
                volumes:
                  # The deckersu fork stores its config under
                  # /etc/amnezia/amneziawg (NOT wg-easy's /etc/wireguard) — the
                  # container ENOENT-crashlooped saving wg0.json when mounted at
                  # the wrong path, and the panel (which reads <path>/data/
                  # wg0.json) saw nothing. Mount at the path the fork uses.
                  - $path/data:/etc/amnezia/amneziawg
                ports:
                  # The wg-easy fork sets the wg0 interface's ListenPort to
                  # WG_PORT (the same value advertised to clients), so the
                  # container listens on `port` INTERNALLY — not on a fixed
                  # 51820. Publishing host:port onto a different container port
                  # (the old 51820) sent every UDP packet to a port nothing
                  # listened on: clients handshook into a black hole. The
                  # container port must equal WG_PORT. (The unified VPN panel's
                  # own wgpanel already does this right — host:wgPort→wgPort.)
                  - "$port:$port/udp"
                  - "127.0.0.1:$WEB_UI_PORT:$WEB_UI_PORT"
            """.trimIndent(),
            envTemplate = null
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.amneziaWGPath
        val lang = context.language
        return listOf("""
        log "AmneziaWG VPN: ${L10nServices.serviceStarting(lang)}"
        install -d $path
        cd $path
        # First run only: generate the panel password on this server and hash
        # it with the image's node and bcryptjs; it goes in on stdin.
        if [ ! -f .env ]; then
          AWGVPN_PASSWORD="${SH}(openssl rand -hex 12)"
          timeout 300 docker pull -q $IMAGE >/dev/null || true
          AWGVPN_OUT="${SH}(printf '%s' "${SH}AWGVPN_PASSWORD" | timeout 60 docker run --rm -i --entrypoint node $IMAGE -e 'let p="";process.stdin.on("data",d=>p+=d).on("end",()=>console.log(require("bcryptjs").hashSync(p,12)))' 2>/dev/null)" || AWGVPN_OUT=""
          AWGVPN_HASH="${SH}(printf '%s' "${SH}AWGVPN_OUT" | head -n1 | tr -d "'")"
          case "${SH}AWGVPN_HASH" in '${SH}2'*) ;; *) AWGVPN_HASH="" ;; esac
          if [ -n "${SH}AWGVPN_HASH" ]; then
            printf 'ADMIN_PASSWORD=%s\nPASSWORD_HASH=%s\n' "${SH}AWGVPN_PASSWORD" "${SH}AWGVPN_HASH" > .env
          else
            # No hash: the stock panel starts without a password. It binds
            # loopback only and nothing proxies it — clients are managed from
            # the unified VPN panel — so this is a degraded but working VPN,
            # which beats an installation that never finishes.
            log "${L10nServices.amneziaPanelWithoutPassword(lang)}"
            printf 'ADMIN_PASSWORD=%s\nPASSWORD_HASH=\n' "${SH}AWGVPN_PASSWORD" > .env
          fi
        fi
        # docker compose interpolates ${SH} inside .env values, so the bcrypt
        # hash must carry ${SH}${SH} or it reaches the container mangled (the WARN
        # "variable is not set" flood). Idempotent: runs of ${SH} collapse to ${SH}${SH},
        # an already escaped hash is left as is; also repairs pre-fix installs.
        sed -i '/^PASSWORD_HASH=/s/\${SH}\{1,\}/${SH}${SH}/g' .env
        chmod 600 .env
        docker compose -p $COMPOSE_PROJECT pull -q
        docker compose -p $COMPOSE_PROJECT up -d
        """.trimIndent())
    }

    override fun firewallPorts(context: ServiceContext) = listOf(
        FirewallPort(context.settings.amneziaWGPort, FirewallPort.Proto.UDP,
                     comment = "AmneziaWG VPN")
    )

    override fun webIngress(context: ServiceContext): WebIngress? = null

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val port = VPNPortShare.clientPort(context)
        return listOf("""
        echo "AmneziaWG: ${hostname(context)}:$port (UDP)"
        echo "  ${L10nServices.amneziaAdminViaWireGuardNote(context.language)}"
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
        const val COMPOSE_PROJECT = "awgvpn"
        const val CONTAINER_NAME = "awgvpn"

        const val WEB_UI_PORT = 51823

        const val IMAGE = "ghcr.io/deckersu/amnezia-wg-easy:14"
    }
}
