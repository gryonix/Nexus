package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.Apt
import com.skaymer.gryonixnexus.catalog.ComposeFile
import com.skaymer.gryonixnexus.catalog.FirewallPort
import com.skaymer.gryonixnexus.catalog.L10nServices
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.PrivilegedCommand
import com.skaymer.gryonixnexus.catalog.ServiceActions
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServicePower
import com.skaymer.gryonixnexus.catalog.ServiceResources
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.embedding
import com.skaymer.gryonixnexus.catalog.systemctl

/** An AirPlay screen on the TV, at home only */
class UxPlayService : ManagedService {
    override val id = ServiceID.UXPLAY
    override val displayName = "AirPlay screen"
    override val systemImage = "airplayvideo"
    override val category = ServiceCategory.AUDIO
    override val runtime = ServiceRuntime.Systemd(UNIT)
    override val requiresHomeMachine: Boolean get() = true

    override val resources = ServiceResources(memoryMB = 256, diskGB = 1)

    override fun composeFile(context: ServiceContext): ComposeFile? = null

    override fun setupSteps(context: ServiceContext): List<String> {
        val packages = (listOf(PACKAGE) + SUPPORT_PACKAGES).joinToString(" ")
        return listOf("""
            log "AirPlay screen: ${L10nServices.serviceStarting(context.language)}"
            ${Apt.QUIET} install -yq $packages
            id $ACCOUNT >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin $ACCOUNT
            for group in audio video render; do
              if getent group "${SH}group" >/dev/null; then usermod -aG "${SH}group" $ACCOUNT; fi
            done
            cat > $UNIT_PATH <<'EOF_UXPLAY_UNIT'
            @UNIT@
            EOF_UXPLAY_UNIT
            systemctl daemon-reload
            systemctl enable --now avahi-daemon.service
            systemctl enable $UNIT.service
            systemctl restart $UNIT.service
        """.trimIndent().embedding("UNIT" to unitFile(context)))
    }

    /** Home network only, never forwarded */
    override fun firewallPorts(context: ServiceContext): List<FirewallPort> {
        val ports = PORT_BASE..(PORT_BASE + 2)
        val tcp = ports.map { FirewallPort(it, FirewallPort.Proto.TCP, "AirPlay screen (home network)") }
        val udp = ports.map { FirewallPort(it, FirewallPort.Proto.UDP, "AirPlay screen (home network)") }
        return tcp + udp
    }

    /** None: a screen has no web page */
    override fun webIngress(context: ServiceContext) = null

    override fun dnsHostnames(context: ServiceContext): List<String> = emptyList()

    override fun reportSteps(context: ServiceContext): List<String> {
        val lang = context.language
        return listOf("""
            echo "AirPlay screen: ${screenName(context)}"
            echo "  ${L10nServices.airplayScreenHint(lang)}"
            echo "  ${L10nServices.airplayScreenDrmNote(lang)}"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val unit = "$UNIT.service"
        return ServiceActions(
            statusProbe = StatusProbe.SystemdUnits(
                list = PrivilegedCommand("/usr/bin/systemctl", "show $unit --property=Id --property=LoadState --property=ActiveState"),
                journal = PrivilegedCommand("/usr/bin/journalctl", "-u $unit -n 500 --no-pager -o short-iso")
            ),
            restart = ServicePower.systemctl("restart", unit),
            start = ServicePower.systemctl("start", unit),
            stop = ServicePower.systemctl("stop", unit)
        )
    }

    override fun updateSpec(context: ServiceContext) = UpdateSpec.OWN_UPDATER

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(preSteps = listOf(
        "systemctl disable --now $UNIT.service >/dev/null 2>&1 || true",
        "rm -f $UNIT_PATH",
        "systemctl daemon-reload || true",
        "${Apt.QUIET} remove -yq $PACKAGE >/dev/null 2>&1 || true",
        "userdel $ACCOUNT >/dev/null 2>&1 || true"
    ))

    companion object {
        const val UNIT = "gryonixnexus-uxplay"
        const val UNIT_PATH = "/etc/systemd/system/gryonixnexus-uxplay.service"
        const val PACKAGE = "uxplay"
        const val ACCOUNT = "uxplay"
        const val DEFAULT_NAME = "gryonix TV"
        const val PORT_BASE = 7200
        const val VIDEO_SINK = "kmssink"
        const val AUDIO_SINK = "alsasink"
        val SUPPORT_PACKAGES = listOf(
            "gstreamer1.0-plugins-good", "gstreamer1.0-plugins-bad", "gstreamer1.0-libav",
            "gstreamer1.0-alsa", "avahi-daemon"
        )

        private const val FORBIDDEN = "\"\\\$`%"

        /** The name, safe inside a unit file */
        fun screenName(context: ServiceContext): String {
            val kept = context.settings.uxplayName
                .filter { it.code >= 0x20 && it.code != 0x7f && it !in FORBIDDEN }
            return kept.trim().ifEmpty { DEFAULT_NAME }
        }

        fun unitFile(context: ServiceContext): String = """
            [Unit]
            Description=UxPlay AirPlay screen
            After=network-online.target avahi-daemon.service
            Wants=network-online.target avahi-daemon.service

            [Service]
            User=$ACCOUNT
            Group=$ACCOUNT
            ExecStart=/usr/bin/uxplay -n "${screenName(context)}" -nh -p $PORT_BASE -vs $VIDEO_SINK -as $AUDIO_SINK
            Restart=on-failure
            RestartSec=5

            [Install]
            WantedBy=multi-user.target
        """.trimIndent()
    }
}
