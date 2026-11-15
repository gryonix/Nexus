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
import com.skaymer.gryonixnexus.catalog.systemctl

/** Audio services installed from Debian packages */
class PackagedAudioService private constructor(
    override val id: ServiceID,
    override val displayName: String,
    override val systemImage: String,
    val packages: List<String>,
    /** Removed on uninstall; shared helpers such as avahi stay */
    val ownPackages: List<String>,
    val units: List<String>,
    private val ports: List<FirewallPort> = emptyList(),
    private val extraSetup: String = "",
    private val extraRemoval: List<String> = emptyList()
) : ManagedService {
    override val category = ServiceCategory.AUDIO
    override val runtime = ServiceRuntime.Systemd(units.first())
    override val requiresHomeMachine: Boolean get() = true
    override val resources = ServiceResources(memoryMB = 128, diskGB = 1)

    /** Install marker; preinstalled packages lack it */
    val marker: String get() = "$MARKER_DIRECTORY/${id.rawValue}"

    private val unitList: String get() = units.joinToString(" ") { "$it.service" }

    private val ownUnits: String get() = units.filterNot { it in SHARED_UNITS }.joinToString(" ") { "$it.service" }

    override fun composeFile(context: ServiceContext): ComposeFile? = null

    override fun setupSteps(context: ServiceContext): List<String> = listOf(
        "log \"$displayName: ${L10nServices.serviceStarting(context.language)}\"\n" +
            "${Apt.QUIET} install -yq ${packages.joinToString(" ")}\n" +
            extraSetup +
            nameSetup(speakerName(context.settings.speakerName)) +
            "systemctl daemon-reload\n" +
            "systemctl enable $unitList\n" +
            "systemctl restart $unitList\n" +
            "install -d -m 755 $MARKER_DIRECTORY\n" +
            "touch $marker"
    )

    /** Script lines that give the speaker its name */
    private fun nameSetup(name: String): String = when {
        name.isEmpty() -> ""
        id == ServiceID.RASPOTIFY ->
            "sed -i 's/^#\\?LIBRESPOT_NAME=.*/LIBRESPOT_NAME=\"$name\"/' /etc/raspotify/conf\n"
        id == ServiceID.BLUEALSA ->
            "if [ -f /etc/bluetooth/main.conf ]; then sed -i 's/^#\\?Name *=.*/Name = $name/' /etc/bluetooth/main.conf; fi\n" +
                "bluetoothctl system-alias '$name' >/dev/null 2>&1 || true\n"
        id == ServiceID.UPMPDCLI ->
            "touch /etc/upmpdcli.conf\nsed -i '/^#\\?friendlyname *=/d' /etc/upmpdcli.conf\n" +
                "echo 'friendlyname = $name' >> /etc/upmpdcli.conf\n"
        else -> ""
    }

    /** Home network only, never forwarded */
    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = ports

    override fun webIngress(context: ServiceContext) = null

    override fun dnsHostnames(context: ServiceContext): List<String> = emptyList()

    override fun reportSteps(context: ServiceContext): List<String> =
        listOf("echo \"$displayName: ${L10nServices.packagedAudioReady(context.language)}\"")

    override fun actions(context: ServiceContext): ServiceActions {
        val journalUnits = units.joinToString(" ") { "-u $it.service" }
        return ServiceActions(
            statusProbe = StatusProbe.SystemdUnits(
                list = PrivilegedCommand("/usr/bin/systemctl", "show $unitList --property=Id --property=LoadState --property=ActiveState"),
                journal = PrivilegedCommand("/usr/bin/journalctl", "$journalUnits -n 500 --no-pager -o short-iso")
            ),
            restart = ServicePower.systemctl("restart", unitList),
            start = ServicePower.systemctl("start", unitList),
            stop = ServicePower.systemctl("stop", unitList)
        )
    }

    override fun updateSpec(context: ServiceContext) = UpdateSpec.OWN_UPDATER

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        preSteps = listOf("systemctl disable --now $ownUnits >/dev/null 2>&1 || true") + extraRemoval + listOf(
            "systemctl daemon-reload || true",
            "${Apt.QUIET} remove -yq ${ownPackages.joinToString(" ")} >/dev/null 2>&1 || true",
            "rm -f $marker"
        )
    )

    companion object {
        const val MARKER_DIRECTORY = "/var/lib/gryonixnexus/packaged"
        private const val BT_AGENT_UNIT = "gryonixnexus-bt-agent"
        private const val NAME_FORBIDDEN = "\"\\\$`%'/&|"

        /** Services whose name the phones see */
        val NAMED = setOf(ServiceID.RASPOTIFY, ServiceID.BLUEALSA, ServiceID.UPMPDCLI)

        /** The name without characters a script cannot carry */
        fun speakerName(asked: String): String {
            val kept = asked.codePoints().toArray()
                .filter { it >= 0x20 && it != 0x7f && (it > 0x7f || it.toChar() !in NAME_FORBIDDEN) }
            val trimmed = String(kept.toIntArray(), 0, kept.size).trim(' ')
            val points = trimmed.codePoints().toArray()
            return String(points, 0, minOf(points.size, 40)).trim(' ')
        }

        private fun homePorts(label: String, vararg ports: Pair<Int, FirewallPort.Proto>) =
            ports.map { (port, proto) -> FirewallPort(port, proto, "$label (home network)") }

        val SNAPSERVER = PackagedAudioService(
            ServiceID.SNAPSERVER, "Multi-room server (Snapcast)", "hifispeaker.2",
            packages = listOf("snapserver", "avahi-daemon"), ownPackages = listOf("snapserver"),
            units = listOf("snapserver"),
            ports = homePorts("Snapcast", 1704 to FirewallPort.Proto.TCP, 1705 to FirewallPort.Proto.TCP,
                1780 to FirewallPort.Proto.TCP))

        val SNAPCLIENT = PackagedAudioService(
            ServiceID.SNAPCLIENT, "Multi-room speaker (Snapcast)", "hifispeaker",
            packages = listOf("snapclient", "avahi-daemon"), ownPackages = listOf("snapclient"),
            units = listOf("snapclient"))

        val UPMPDCLI = PackagedAudioService(
            ServiceID.UPMPDCLI, "DLNA speaker", "music.note.house",
            packages = listOf("mpd", "upmpdcli", "avahi-daemon"), ownPackages = listOf("upmpdcli"),
            units = listOf("mpd", "upmpdcli"),
            ports = homePorts("DLNA", 1900 to FirewallPort.Proto.UDP, 49152 to FirewallPort.Proto.TCP,
                49153 to FirewallPort.Proto.TCP))

        val BLUEALSA = PackagedAudioService(
            ServiceID.BLUEALSA, "Bluetooth speaker", "wave.3.right",
            packages = listOf("bluez", "bluez-alsa-utils", "bluez-tools"),
            ownPackages = listOf("bluez-alsa-utils", "bluez-tools"),
            units = listOf("bluetooth", "bluealsa", "bluealsa-aplay", BT_AGENT_UNIT),
            extraSetup = bluetoothSetup(),
            extraRemoval = listOf(
                "rm -f /etc/systemd/system/$BT_AGENT_UNIT.service",
                "rm -rf /etc/systemd/system/bluealsa.service.d/gryonixnexus.conf"
            ))

        val RASPOTIFY = PackagedAudioService(
            ServiceID.RASPOTIFY, "Spotify Connect speaker", "dot.radiowaves.left.and.right",
            packages = listOf("ca-certificates", "curl"), ownPackages = listOf("raspotify"),
            units = listOf("raspotify"),
            extraSetup = spotifySetup())

        val MYMPD = PackagedAudioService(
            ServiceID.MYMPD, "Music library (MPD + myMPD)", "music.note.list",
            packages = listOf("mpd", "avahi-daemon", "ca-certificates", "curl"), ownPackages = listOf("mympd"),
            units = listOf("mpd", "mympd"),
            ports = homePorts("myMPD", 8019 to FirewallPort.Proto.TCP),
            extraSetup = mympdSetup(),
            extraRemoval = listOf("rm -rf /etc/systemd/system/mympd.service.d/gryonixnexus.conf"))

        val ALL = listOf(SNAPSERVER, SNAPCLIENT, UPMPDCLI, BLUEALSA, RASPOTIFY, MYMPD)

        /** System units other services share; removal leaves them running */
        private val SHARED_UNITS = setOf("mpd", "bluetooth")

        private fun mympdSetup(): String = """
            case "${SH}(dpkg --print-architecture)" in
              amd64) mympd_sha=bb839fe621bc9ab6a08fbf71b2db3d007555fdf5eaabe94c7b04e18b19ba027c ;;
              arm64) mympd_sha=c65e824ec01f4cdd8f298869a3368865fd6d6a10a7877225c860522032588853 ;;
              armhf) mympd_sha=7524caf1677d88f4f0dcb0c8248c14c3b7f8c49120db7c2ea559d76e915ca349 ;;
              *) echo "myMPD has no package for this processor" >&2; exit 1 ;;
            esac
            mympd_deb="/tmp/mympd_${SH}(dpkg --print-architecture).deb"
            curl -fsSL -o "${SH}mympd_deb" "https://github.com/b0bbywan/odio-mympd/releases/download/v26.1.2/mympd_26.1.2-1_${SH}(dpkg --print-architecture).deb"
            echo "${SH}mympd_sha  ${SH}mympd_deb" | sha256sum -c - >/dev/null
            install -d /etc/systemd/system/mympd.service.d
            printf '[Service]\nEnvironment=MYMPD_HTTP_PORT=8019\nEnvironment=MYMPD_SSL=false\n' > /etc/systemd/system/mympd.service.d/gryonixnexus.conf
            DEBIAN_FRONTEND=noninteractive apt-get install -yq "${SH}mympd_deb"
            rm -f "${SH}mympd_deb"
            for mympd_dir in /var/lib/mympd /var/lib/private/mympd; do
              if [ -d "${SH}mympd_dir/config" ]; then echo 8019 > "${SH}mympd_dir/config/http_port"; echo false > "${SH}mympd_dir/config/ssl"; fi
            done
        """.trimIndent() + "\n"

        private fun spotifySetup(): String = """
            case "${SH}(dpkg --print-architecture)" in
              amd64) spotify_sha=7b228feb0623bf0f9b65904961ad3ad9df8e1f4b07a002ab2388e1ee9385eeed ;;
              arm64) spotify_sha=4d272678f475ad18961563951b6c36e5395c8a85b8d5607d1e3e9f94671108e2 ;;
              armhf) spotify_sha=47cc9b1d1e75e583a7eb45c2fa24b38cf6ed92f3231443d37f9b2477e32be59b ;;
              *) echo "Spotify Connect has no package for this processor" >&2; exit 1 ;;
            esac
            spotify_deb="/tmp/raspotify_${SH}(dpkg --print-architecture).deb"
            curl -fsSL -o "${SH}spotify_deb" "https://github.com/dtcooper/raspotify/releases/download/0.48.4/raspotify_0.48.4.librespot.v0.8.0-99b6088_${SH}(dpkg --print-architecture).deb"
            echo "${SH}spotify_sha  ${SH}spotify_deb" | sha256sum -c - >/dev/null
            DEBIAN_FRONTEND=noninteractive apt-get install -yq "${SH}spotify_deb"
            rm -f "${SH}spotify_deb"
            sed -i "s/^#\?LIBRESPOT_NAME=.*/LIBRESPOT_NAME=\"${SH}(hostname)\"/" /etc/raspotify/conf
        """.trimIndent() + "\n"

        private fun bluetoothSetup(): String = """
            install -d /etc/systemd/system/bluealsa.service.d
            cat > /etc/systemd/system/bluealsa.service.d/gryonixnexus.conf <<'EOF_BLUEALSA'
            [Service]
            ExecStart=
            ExecStart=/usr/bin/bluealsa -p a2dp-sink
            EOF_BLUEALSA
            cat > /etc/systemd/system/$BT_AGENT_UNIT.service <<'EOF_BT_AGENT'
            [Unit]
            Description=Bluetooth pairing without a PIN
            After=bluetooth.service
            Requires=bluetooth.service

            [Service]
            ExecStartPre=/usr/bin/bluetoothctl power on
            ExecStartPre=/usr/bin/bluetoothctl discoverable on
            ExecStartPre=/usr/bin/bluetoothctl pairable on
            ExecStart=/usr/bin/bt-agent --capability=NoInputNoOutput
            Restart=on-failure

            [Install]
            WantedBy=multi-user.target
            EOF_BT_AGENT
            if [ -f /etc/bluetooth/main.conf ]; then sed -i 's/^#\?DiscoverableTimeout.*/DiscoverableTimeout = 0/' /etc/bluetooth/main.conf; fi
        """.trimIndent() + "\n"
    }
}
