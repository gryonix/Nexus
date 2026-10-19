package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.ArchiveBackupPlan
import com.skaymer.gryonixnexus.catalog.BackupPlan
import com.skaymer.gryonixnexus.catalog.BackupSpec
import com.skaymer.gryonixnexus.catalog.BackupWrapperSpec
import com.skaymer.gryonixnexus.catalog.ComposeFile
import com.skaymer.gryonixnexus.catalog.FirewallPort
import com.skaymer.gryonixnexus.catalog.L10nServices
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.PrivilegedCommand
import com.skaymer.gryonixnexus.catalog.RestoreSpec
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.ServiceActions
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceCommand
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServicePower
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.ShellQuoting
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress
import com.skaymer.gryonixnexus.catalog.embedding

class VPNPanelService : ManagedService {
    override val id = ServiceID.VPN_PANEL
    override val displayName = "VPN Panel"
    override val systemImage = "shield.checkerboard"
    override val category = ServiceCategory.IMPLICIT
    /** The VPN protocols brought it — see `ManagedService.displayCategory` */
    override val displayCategory = ServiceCategory.VPN
    override val usesSharedAdminLogin = true
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.vpnHostname
        return if (custom.isEmpty()) "vpn.${context.domain}" else custom
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val wgPort = context.settings.wireguardVPNPort
        return ComposeFile(
            directory = PATH,
            composeContents = """
            services:
              vpnpanel:
                build: $PATH/build
                image: $IMAGE
                container_name: $CONTAINER_NAME
                restart: unless-stopped
                cap_add:
                  - NET_ADMIN
                  - SYS_MODULE
                sysctls:
                  - net.ipv4.ip_forward=1
                env_file:
                  - $PATH/.env
                volumes:
                  - $PATH/data:/data
                  # The agent's broker restarts and inspects the protocol
                  # containers; the panel holds no docker socket. Config
                  # dirs below; unused mounts are harmless empty dirs.
                  - /run/gryonixnexus-panel:/run/gryonixnexus-panel
                  - ${context.settings.shadowsocksPath}:/protocols/shadowsocks
                  - ${context.settings.xrayRealityPath}:/protocols/xray
                  - ${context.settings.openVPNPath}/data:/protocols/openvpn
                  - ${context.settings.amneziaWGPath}/data:/protocols/amneziawg
                  # Read-only: lets the panel find mailcow's database
                  # credentials so it can offer the existing mailboxes as the
                  # sender for password-reset mail. The DIRECTORY is
                  # mounted, not mailcow.conf itself — docker materialises a
                  # missing bind source, and an empty mailcow.conf directory
                  # would make mailcow's own "already configured?" guard skip
                  # generate_config.sh on a later install. An empty directory
                  # is harmless: git clone still populates it.
                  - ${context.settings.mailcowPath}:/protocols/mailcow:ro
                extra_hosts:
                  # Reaching the host's SMTP listener (mailcow's Postfix) from
                  # inside the container.
                  - "host.docker.internal:host-gateway"
                ports:
                  - "127.0.0.1:$WEB_UI_PORT:80"
                  # WireGuard (only listens when WireGuard is among the enabled
                  # protocols; harmless otherwise).
                  - "$wgPort:$wgPort/udp"
            """.trimIndent(),
            envTemplate = null
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val lang = context.language
        val host = hostname(context)
        val wgPort = context.settings.wireguardVPNPort
        val adminUser = ShellQuoting.singleQuoted(context.settings.adminUsername)
        val pwResolution = """
            VPNPANEL_PW=""
            if [ -f $PATH/.env ]; then
            VPNPANEL_PW="${SH}(grep '^ADMIN_PASSWORD=' $PATH/.env | cut -d= -f2-)"
            fi
            case "${SH}VPNPANEL_PW" in
              *[!0-9a-f]* | "") VPNPANEL_PW="${SH}(openssl rand -hex 12)" ;;
              *) [ ${SH}{#VPNPANEL_PW} -eq 24 ] || VPNPANEL_PW="${SH}(openssl rand -hex 12)" ;;
            esac
        """.trimIndent()
        return listOf("""
        log "VPN Panel: ${L10nServices.serviceStarting(lang)}"
        install -d $PATH/build $PATH/data
        cat > $PATH/build/Dockerfile <<'EOF_VPNPANEL_DOCKER'
        @DOCKERFILE@
        EOF_VPNPANEL_DOCKER
        cat > $PATH/build/app.py <<'EOF_VPNPANEL_APP'
        @APPPY@
        EOF_VPNPANEL_APP
        cat > $PATH/build/index.html <<'EOF_VPNPANEL_HTML'
        @INDEXHTML@
        EOF_VPNPANEL_HTML
        cat > $PATH/build/login.html <<'EOF_VPNPANEL_LOGIN'
        @LOGINHTML@
        EOF_VPNPANEL_LOGIN
        cat > $PATH/build/reset.html <<'EOF_VPNPANEL_RESET'
        @RESETHTML@
        EOF_VPNPANEL_RESET
        # Panel credentials in .env, refreshed on every run (a user-chosen
        # password is applied idempotently; a generated one is preserved — see
        # ${SH}VPNPANEL_PW resolution above). ADMIN_USER and the WG parameters
        # always track the current configuration.
        @PWRESOLUTION@
        {
          printf 'ADMIN_USER=%s\n' $adminUser
          printf 'ADMIN_PASSWORD=%s\n' "${SH}VPNPANEL_PW"
          printf 'WG_HOST=%s\n' "$host"
          printf 'WG_PORT=%s\n' "$wgPort"
          printf 'WG_SUBNET=%s\n' "$WG_SUBNET"
        } > $PATH/.env
        chmod 600 $PATH/.env
        [ -f $PATH/data/services.json ] || echo '{"services":[]}' > $PATH/data/services.json
        # Admin lockdown plumbing: the guard snippet (created locked by
        # default on first install, via the wrapper's own "on" below;
        # re-runs keep whatever state the dashboard last set) and the
        # wrapper the dashboard calls over sudo. "On" allows only
        # private-range sources (loopback, RFC1918,
        # ULA): VPN clients reach Caddy MASQUERADEd from the protocol
        # containers, whose Docker bridge may sit in ANY private pool
        # (172.16/12 or 192.168/16 once the pools run out — pinning bridge
        # subnets 403'd VPN clients). The scenario B relay tunnel
        # (10.8.0.0/24) carries relayed PUBLIC traffic, so it is denied
        # explicitly before the private-range allow — EXCEPT the hairpin
        # source .254, which the VPS SNATs VPN-client traffic to so it can
        # be told apart from public visitors (both otherwise reach Caddy as
        # the same VPS tunnel address). See NftablesConfig hairpin_src.
        install -d /etc/caddy
        if [ -f $ADMIN_GUARD_PATH ]; then
          GRYONIXNEXUS_GUARD_EXISTED=1
        else
          : > $ADMIN_GUARD_PATH
          GRYONIXNEXUS_GUARD_EXISTED=0
        fi
        cat > $LOCKDOWN_SCRIPT_PATH <<'EOF_VPNPANEL_LOCKDOWN'
        #!/bin/bash
        # Managed by gryonixNexus — VPN-only access switch for admin web panels.
        # on = every site; only host... = just those sites (per-service
        # selection); off = public again. Every Caddy site imports the guard,
        # so a host matcher inside it narrows which vhosts actually block.
        set -euo pipefail
        GUARD=$ADMIN_GUARD_PATH
        # Shown to blocked visitors so a locked panel is a clear "denied"
        # page, not an empty-bodied 403 that browsers render as a blank
        # white screen. It names WireGuard specifically: whoever reads this
        # page is most often already connected to the VPN — on AmneziaWG or
        # one of the proxy protocols, which do not carry admin traffic — so
        # "connect to the VPN" would be advice they already followed.
        # ASCII only and no quotes: it rides through a Caddyfile heredoc and
        # lands inside a double-quoted respond argument.
        DENY='Access denied. The admin panels are reachable only over the VPN. Connect to your VPN and try again.'
        reload_caddy() { systemctl reload caddy 2>/dev/null || systemctl restart caddy || true; }
        write_guard() {
          hosts="${SH}1"
          # Scenario-A hairpin allow-source. VPN clients on the containerised
          # protocols (amneziaWG / OpenVPN / shadowsocks / xray) that open an
          # admin panel served on THIS host's own public IP loop back through
          # the protocol/host NAT and reach Caddy SNAT'd to that public IP — a
          # source private_ranges does not cover, so the guard used to 403 a
          # genuinely VPN-side client (only the panel's own WireGuard, which
          # arrives from a private address, got through). No off-box client can
          # forge our own public IP as its source — the TCP return path comes
          # straight back to us — so our own global addresses are a safe allow.
          # This is the scenario-A counterpart to the 10.8.0.254 relay hairpin.
          selfip=${SH}(
            { ip -4 -o addr show scope global; ip -6 -o addr show scope global; } 2>/dev/null \
              | awk '{ split(${SH}4, a, "/"); ip = a[1]; print ip (index(ip, ":") ? "/128" : "/32") }' \
              | paste -sd' ' -
          )
          # Cloudflare Tunnel visitors come from loopback; its header marks them.
          {
            if [ -n "${SH}hosts" ]; then
              printf '@gryonixnexus_relay {\n'
              printf '    host %s\n' "${SH}hosts"
              printf '    remote_ip 10.8.0.0/24\n'
              printf '    not remote_ip 10.8.0.254/32\n'
              printf '}\n'
              printf 'respond @gryonixnexus_relay "%s" 403\n' "${SH}DENY"
              printf '@gryonixnexus_public {\n'
              printf '    host %s\n' "${SH}hosts"
              printf '    not remote_ip private_ranges %s\n' "${SH}selfip"
              printf '}\n'
              printf 'respond @gryonixnexus_public "%s" 403\n' "${SH}DENY"
              printf '@gryonixnexus_tunnel {\n'
              printf '    host %s\n' "${SH}hosts"
              printf '    header Cf-Connecting-IP *\n'
              printf '}\n'
              printf 'respond @gryonixnexus_tunnel "%s" 403\n' "${SH}DENY"
            else
              printf '@gryonixnexus_relay {\n'
              printf '    remote_ip 10.8.0.0/24\n'
              printf '    not remote_ip 10.8.0.254/32\n'
              printf '}\n'
              printf 'respond @gryonixnexus_relay "%s" 403\n' "${SH}DENY"
              printf '@gryonixnexus_public not remote_ip private_ranges %s\n' "${SH}selfip"
              printf 'respond @gryonixnexus_public "%s" 403\n' "${SH}DENY"
              printf '@gryonixnexus_tunnel header Cf-Connecting-IP *\n'
              printf 'respond @gryonixnexus_tunnel "%s" 403\n' "${SH}DENY"
            fi
          } > "${SH}GUARD"
          reload_caddy
        }
        case "${SH}{1:-status}" in
          on)
            write_guard ""
            echo on ;;
          only)
            shift
            [ "${SH}#" -ge 1 ] || { echo "usage: ${SH}0 only host..." >&2; exit 64; }
            for h in "${SH}@"; do
              case "${SH}h" in
                *[!A-Za-z0-9.-]*|"") echo "invalid host: ${SH}h" >&2; exit 64 ;;
              esac
            done
            write_guard "${SH}*"
            echo "only ${SH}*" ;;
          off)
            : > "${SH}GUARD"
            reload_caddy
            echo off ;;
          status)
            if [ ! -s "${SH}GUARD" ]; then
              echo off
            elif grep -q 'host ' "${SH}GUARD"; then
              echo "only ${SH}(grep -m1 'host ' "${SH}GUARD" | sed 's/^ *host //')"
            else
              echo on
            fi ;;
          *)
            echo "usage: ${SH}0 on|off|only host...|status" >&2; exit 64 ;;
        esac
        EOF_VPNPANEL_LOCKDOWN
        chmod 750 $LOCKDOWN_SCRIPT_PATH
        # Ship locked by default instead of public: run the wrapper's own
        # "on" verb once, right here, the same action the dashboard's switch
        # takes later. Only on the FIRST install — a re-run must never
        # fight an owner who chose "off" from the dashboard since.
        [ "${SH}GRYONIXNEXUS_GUARD_EXISTED" = 1 ] || $LOCKDOWN_SCRIPT_PATH on
        docker build -t $IMAGE $PATH/build
        # cd before compose: without it the panel would inherit the previous
        # section's directory and launch THAT service's compose file.
        cd $PATH
        docker compose -p $COMPOSE_PROJECT up -d
        """.trimIndent().embedding(
            "DOCKERFILE" to VPNPanelAssets.dockerfile,
            "APPPY" to VPNPanelAssets.appPY,
            "INDEXHTML" to VPNPanelAssets.indexHTML,
            "LOGINHTML" to VPNPanelAssets.loginHTML,
            "RESETHTML" to VPNPanelAssets.resetHTML,
            "PWRESOLUTION" to pwResolution
        ))
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext): WebIngress? {
        if (!context.settings.vpnClientAccess.publishesPanelSite) return null
        return WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT,
                          adminGuard = true, overwriteForwardedFor = true)
    }

    override fun extraSudoers(context: ServiceContext) =
        listOf(PrivilegedCommand(LOCKDOWN_SCRIPT_PATH, ""))

    override fun dnsHostnames(context: ServiceContext): List<String> =
        if (context.settings.vpnClientAccess.publishesPanelSite) listOf(hostname(context))
        else emptyList()

    override fun reportSteps(context: ServiceContext): List<String> {
        val lang = context.language
        val passwordLabel = L10nServices.passwordGeneratedOnServerLabel(lang)
        return listOf("""
        echo "VPN Panel: https://${hostname(context)}"
        echo "  ${L10nServices.adminPanelLabel(lang)}: https://${hostname(context)}"
        echo "  ${L10nServices.administratorLabel(lang)}: ${SH}(grep '^ADMIN_USER=' $PATH/.env | cut -d= -f2-)"
        echo "  $passwordLabel: ${SH}(grep '^ADMIN_PASSWORD=' $PATH/.env | cut -d= -f2-)"
        echo "  ${L10nServices.vpnClientsNote(lang)}"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext) = ServiceActions(
        statusProbe = StatusProbe.Container(
            name = CONTAINER_NAME,
            list = PrivilegedCommand("/usr/bin/docker", "ps -a")
        ),
        restart = ServicePower.container(CONTAINER_NAME, "restart"),
        start = ServicePower.container(CONTAINER_NAME, "start"),
        stop = ServicePower.container(CONTAINER_NAME, "stop"),
        backup = BackupSpec.WrapperScript(BackupWrapperSpec(
            wrapperTarget = WRAPPER_TARGET,
            backupDir = context.backupDirectory(ServiceID.VPN_PANEL),
            run = ServiceCommand(
                PrivilegedCommand(BackupWrapperSpec.WRAPPER_PATH, ""),
                ServiceCommand.TimeoutClass.LONG,
                streamsOutput = true
            ),
            plan = BackupPlan.Archive(ArchiveBackupPlan(
                composeProject = COMPOSE_PROJECT,
                dataPath = "$PATH/data",
                databases = emptyList(),
                quiesceServices = listOf(CONTAINER_NAME),
                encryptsByDefault = true,
                sizePaths = listOf("$PATH/data")
            ))
        )),
        restore = RestoreSpec(
            wrapperTarget = WRAPPER_TARGET,
            backupDir = context.backupDirectory(ServiceID.VPN_PANEL),
            needsPassphrase = false,
            privileged = PrivilegedCommand(RestoreSpec.WRAPPER_PATH, "")
        )
    )

    override fun updateSpec(context: ServiceContext) = UpdateSpec.builtOnServer(listOf(IMAGE))

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        configDirectory = PATH,
        dataPaths = listOf("$PATH/data.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(ServiceID.VPN_PANEL)),
        preSteps = listOf(
            "ip link delete wgpanel 2>/dev/null || true"
        ),
        postSteps = listOf(
            "rm -f $LOCKDOWN_SCRIPT_PATH",
            ": > $ADMIN_GUARD_PATH 2>/dev/null || true",
            "systemctl reload caddy 2>/dev/null || true"
        )
    )

    companion object {
        const val COMPOSE_PROJECT = "vpnpanel"
        const val CONTAINER_NAME = "vpnpanel"
        const val PATH = "/opt/gryonix-vpn-panel"

        /** Loopback port the panel binds; the shared Caddy reverse-proxies vpn.<domain> */
        const val WEB_UI_PORT = 51900
        const val IMAGE = "gryonix-vpn-panel:local"

        const val WG_SUBNET = "10.9.0.0/24"

        const val ADMIN_GUARD_PATH = "/etc/caddy/gryonixnexus-admin-guard"

        const val LOCKDOWN_SCRIPT_PATH = "/opt/gryonixnexus-admin-lockdown.sh"

        val WRAPPER_TARGET = ServiceID.VPN_PANEL.rawValue
    }
}
