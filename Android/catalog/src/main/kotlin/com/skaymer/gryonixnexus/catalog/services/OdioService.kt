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
import com.skaymer.gryonixnexus.catalog.ServiceDefaultHostnames
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServicePower
import com.skaymer.gryonixnexus.catalog.ServiceResources
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress
import com.skaymer.gryonixnexus.catalog.embedding
import com.skaymer.gryonixnexus.catalog.helper

/** A whole-house audio hub, at home only */
class OdioService : ManagedService {
    override val id = ServiceID.ODIO
    override val displayName = "Audio hub (odio)"
    override val systemImage = "hifispeaker.2"
    override val category = ServiceCategory.AUDIO
    override val runtime = ServiceRuntime.Systemd("odio-api")
    override val requiresHomeMachine: Boolean get() = true

    override val resources = ServiceResources(memoryMB = 512, diskGB = 3)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.odioHostname
        return custom.ifEmpty { LOCAL_HOSTNAME }
    }

    override fun composeFile(context: ServiceContext): ComposeFile? = null

    override fun setupSteps(context: ServiceContext): List<String> {
        val lang = context.language
        val path = context.settings.odioPath
        val keepsOwnAirPlay = ServiceID.SHAIRPORT_SYNC in context.installedServices
        return listOf("""
            log "Audio hub (odio): ${L10nServices.serviceStarting(lang)}"
            install -d -m 755 $path
            odio_tmp="${SH}(mktemp -d)"
            curl -fsSL -o "${SH}odio_tmp/install.sh" '$INSTALLER_URL'
            echo '$INSTALLER_SHA256  '"${SH}odio_tmp/install.sh" | sha256sum -c - >/dev/null \
              || fail "${L10nServices.odioInstallerChecksum(lang)}"
            odio_airplay=Y
            if [ "${if (keepsOwnAirPlay) "1" else "0"}" = 1 ] || [ -f ${context.settings.shairportPath}/docker-compose.yml ]; then
              odio_airplay=N
            fi
            printf 'APT::Get::Assume-Yes "true";\n' > "${SH}odio_tmp/apt.conf"
            odio_mympd=Y
            if grep -qE '^ID=(debian|raspbian)${SH}' /etc/os-release && [ "${SH}(. /etc/os-release; echo "${SH}VERSION_ID" | cut -d. -f1)" -lt 13 ] 2>/dev/null; then
              odio_mympd=N
              echo 'myMPD needs Debian 13 or newer; installing the hub without it'
            fi
            DEBIAN_FRONTEND=noninteractive apt-get install -yq python3-jinja2 python3-cryptography
            TARGET_USER=$ACCOUNT ODIOS_VERSION=$VERSION INSTALL_BRANDING=N \
              INSTALL_SHAIRPORT_SYNC="${SH}odio_airplay" INSTALL_MYMPD="${SH}odio_mympd" APT_CONFIG="${SH}odio_tmp/apt.conf" \
              DEBIAN_FRONTEND=noninteractive bash -s < "${SH}odio_tmp/install.sh"
            rm -rf "${SH}odio_tmp"
            odio_home="${SH}(getent passwd $ACCOUNT | cut -d: -f6)"
            install -d -m 700 -o $ACCOUNT -g $ACCOUNT "${SH}odio_home/.config/odio-api/conf.d"
            printf 'bind: lo\n' > "${SH}odio_home/.config/odio-api/conf.d/20-gryonixnexus.yml"
            chown $ACCOUNT:$ACCOUNT "${SH}odio_home/.config/odio-api/conf.d/20-gryonixnexus.yml"
            cat > $CONTROL_PATH <<'EOF_ODIO_CTL'
            @CTL@
            EOF_ODIO_CTL
            chmod 755 $CONTROL_PATH
            if [ ! -f $path/.env ]; then
              install -m 600 /dev/null $path/.env
              printf 'ODIO_WEB_USER=$ACCOUNT\nODIO_WEB_PASSWORD=%s\n' "${SH}(openssl rand -hex 12)" > $path/.env
            fi
            . $path/.env
            printf 'basic_auth {\n    %s %s\n}\nredir / /ui/\n' "${SH}ODIO_WEB_USER" "${SH}(caddy hash-password --plaintext "${SH}ODIO_WEB_PASSWORD")" \
              > $AUTH_SNIPPET_PATH
            chmod 644 $AUTH_SNIPPET_PATH
            $CONTROL_PATH restart
        """.trimIndent().embedding("CTL" to controlScript()))
    }

    /** None: discovery stays on the home network */
    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) = WebIngress(
        hostname = hostname(context),
        upstreamPort = WEB_UI_PORT,
        basicAuthSnippet = AUTH_SNIPPET_PATH,
        homeOnly = isAtHome(context)
    )

    /** Whether the panel answers only on its .local name */
    fun isAtHome(context: ServiceContext): Boolean = hostname(context).endsWith(".local")

    override fun dnsHostnames(context: ServiceContext): List<String> =
        if (isAtHome(context)) emptyList() else listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val lang = context.language
        val path = context.settings.odioPath
        return listOf("""
            echo "Audio hub: https://${hostname(context)}"
            echo "  ${L10nServices.administratorLabel(lang)}: ${SH}(grep '^ODIO_WEB_USER=' $path/.env | cut -d= -f2-)"
            echo "  ${L10nServices.passwordGeneratedOnServerLabel(lang)}: ${SH}(grep '^ODIO_WEB_PASSWORD=' $path/.env | cut -d= -f2-)"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext) = ServiceActions(
        statusProbe = StatusProbe.SystemdUnits(
            list = PrivilegedCommand(CONTROL_PATH, "status"),
            journal = PrivilegedCommand(CONTROL_PATH, "logs")
        ),
        restart = ServicePower.helper(CONTROL_PATH, "restart"),
        start = ServicePower.helper(CONTROL_PATH, "start"),
        stop = ServicePower.helper(CONTROL_PATH, "stop")
    )

    override fun updateSpec(context: ServiceContext) = UpdateSpec.OWN_UPDATER

    override fun uninstallSpec(context: ServiceContext): UninstallSpec {
        val lang = context.language
        return UninstallSpec(
            dataPaths = listOf(context.settings.odioPath),
            preSteps = listOf(
                "[ -x $CONTROL_PATH ] && $CONTROL_PATH disable || true",
                "rm -f $CONTROL_PATH $AUTH_SNIPPET_PATH",
                "echo \"odio: ${L10nServices.odioLeftovers(lang, LEFTOVER_PACKAGES, ACCOUNT)}\""
            )
        )
    }

    companion object {
        const val VERSION = "2026.10.0b3"
        const val INSTALLER_URL =
            "https://github.com/b0bbywan/odios/releases/download/2026.10.0b3/install.sh"
        const val INSTALLER_SHA256 = "1f1aafe4ef853ae10c9f6f134f24988b2943b6d5c50c388f8177103045c0f569"
        const val ACCOUNT = "odio"
        const val WEB_UI_PORT = 8018
        const val LOCAL_HOSTNAME = "odio.local"
        const val CONTROL_PATH = "/usr/local/sbin/gryonixnexus-odio-ctl"
        const val AUTH_SNIPPET_PATH = "/etc/caddy/gryonixnexus-odio-auth"
        const val SHAIRPORT_UNIT = "shairport-sync.service"
        val USER_UNITS = listOf(
            "odio-api.service", "mpd.service", "mympd.service", "spotifyd.service",
            "snapclient.service", "upmpdcli.service", SHAIRPORT_UNIT
        )
        const val LEFTOVER_PACKAGES =
            "mpd, myMPD, Spotifyd, Snapcast, upmpdcli, BlueZ, PulseAudio, odio-api, odioctl"

        /** Root helper that drives the account's user units */
        fun controlScript(): String = """
            #!/bin/bash
            set -eu
            user=$ACCOUNT
            units="${USER_UNITS.joinToString(" ")}"
            uid="${SH}(id -u "${SH}user")"
            as_user() { runuser -u "${SH}user" -- env XDG_RUNTIME_DIR="/run/user/${SH}uid" "${SH}@"; }
            each_unit() {
              for unit in ${SH}units; do
                if as_user systemctl --user cat "${SH}unit" >/dev/null 2>&1; then
                  as_user systemctl --user "${SH}@" "${SH}unit"
                fi
              done
            }
            case "${SH}{1:-}" in
              status) as_user systemctl --user show ${SH}units --property=Id,LoadState,ActiveState ;;
              logs) journalctl "_UID=${SH}uid" -n 500 --no-pager -o short-iso ;;
              start|restart) each_unit "${SH}1" ;;
              stop) each_unit stop; as_user systemctl --user stop mpd.socket || true ;;
              disable) each_unit disable --now; as_user systemctl --user disable --now mpd.socket || true ;;
              *) exit 2 ;;
            esac
        """.trimIndent()
    }
}
