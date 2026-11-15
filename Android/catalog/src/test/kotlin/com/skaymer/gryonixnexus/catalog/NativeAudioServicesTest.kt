package com.skaymer.gryonixnexus.catalog

import com.skaymer.gryonixnexus.catalog.services.OdioService
import com.skaymer.gryonixnexus.catalog.services.PackagedAudioService
import com.skaymer.gryonixnexus.catalog.services.UxPlayService
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class NativeAudioServicesTest {
    private fun context(settings: ServiceSettings = ServiceSettings(), installed: Set<ServiceID> = emptySet()) =
        ServiceContext(domain = "example.com", sshUser = "admin", settings = settings, installedServices = installed)

    @Test
    fun `the screen runs as a unit with fixed ports and headless sinks`() {
        val unit = UxPlayService.unitFile(context(ServiceSettings(uxplayName = "Living room")))
        assertTrue(unit.contains("ExecStart=/usr/bin/uxplay -n \"Living room\" -nh -p 7200 -vs kmssink -as alsasink"), unit)
        assertTrue(unit.contains("User=uxplay"))
    }

    @Test
    fun `the screen name cannot break the unit`() {
        val unit = UxPlayService.unitFile(context(ServiceSettings(uxplayName = "A\"$(x)%h`b\\")))
        assertTrue(unit.contains("-n \"A(x)hb\""), unit)
        assertTrue(UxPlayService.unitFile(context(ServiceSettings(uxplayName = "\""))).contains("-n \"gryonix TV\""))
    }

    @Test
    fun `the screen opens its own ports on the home network only`() {
        val service = UxPlayService()
        val ports = service.firewallPorts(context())
        assertEquals(listOf(7200, 7201, 7202), ports.filter { it.proto == FirewallPort.Proto.TCP }.map { it.port })
        assertEquals(listOf(7200, 7201, 7202), ports.filter { it.proto == FirewallPort.Proto.UDP }.map { it.port })
        assertEquals(listOf(80), ForwardedPorts.tcp(listOf(service), context()))
        assertTrue(service.requiresHomeMachine)
        assertFalse(ServiceRegistry.needsDocker(setOf(ServiceID.UXPLAY, ServiceID.ODIO)))
    }

    @Test
    fun `the screen manages its own unit`() {
        val actions = UxPlayService().actions(context())
        val probe = actions.statusProbe as StatusProbe.SystemdUnits
        assertEquals("sudo systemctl show gryonixnexus-uxplay.service --property=Id --property=LoadState --property=ActiveState",
                     probe.list.command)
        assertTrue(probe.journal.command.startsWith("sudo journalctl -u gryonixnexus-uxplay.service"))
        assertEquals("sudo systemctl restart gryonixnexus-uxplay.service", actions.restart?.command)
        assertTrue(UxPlayService().sudoersLines(context()).contains(
            "admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop gryonixnexus-uxplay.service"))
    }

    @Test
    fun `the hub checks the pinned installer before running it`() {
        val text = OdioService().setupSteps(context()).single()
        assertTrue(text.contains(OdioService.INSTALLER_URL))
        assertTrue(text.contains("${OdioService.INSTALLER_SHA256}  "))
        assertTrue(text.contains("sha256sum -c -"))
        assertTrue(text.contains("ODIOS_VERSION=2026.10.0b3"))
        assertTrue(text.contains("bash -s < \"\$odio_tmp/install.sh\""))
        assertTrue(text.contains("apt-get install -yq python3-jinja2 python3-cryptography"))
        assertTrue(text.contains("INSTALL_BRANDING=N"))
    }

    @Test
    fun `the hub leaves airplay to the speaker when both are selected`() {
        val both = OdioService().setupSteps(context(installed = setOf(ServiceID.ODIO, ServiceID.SHAIRPORT_SYNC))).single()
        assertTrue(both.contains("if [ \"1\" = 1 ]"))
        val alone = OdioService().setupSteps(context()).single()
        assertTrue(alone.contains("if [ \"0\" = 1 ]"))
        assertTrue(alone.contains("/opt/shairport-sync/docker-compose.yml"))
    }

    @Test
    fun `the hub is behind the guard and a password`() {
        val ingress = OdioService().webIngress(context())
        assertTrue(ingress.adminGuard)
        assertEquals(8018, ingress.upstreamPort)
        assertEquals("odio.local", ingress.hostname)
        assertTrue(ingress.homeOnly)
        assertEquals("/etc/caddy/gryonixnexus-odio-auth", ingress.basicAuthSnippet)
        val text = OdioService().setupSteps(context()).single()
        assertTrue(text.contains("caddy hash-password --plaintext"))
        assertTrue(text.contains("printf 'bind: lo\\n'"))
    }

    @Test
    fun `the hub reports its generated password and leaves its packages`() {
        val report = OdioService().reportSteps(context()).joinToString("\n")
        assertTrue(report.contains("https://odio.local"))
        assertTrue(report.contains("ODIO_WEB_PASSWORD"))
        val spec = OdioService().uninstallSpec(context())
        assertEquals(listOf("/opt/odio"), spec.dataPaths)
        assertTrue(spec.preSteps.joinToString("\n").contains("left in place"))
        assertTrue(spec.preSteps.any { it.contains("gryonixnexus-odio-ctl disable") })
    }

    @Test
    fun `the hub controls its user units through one helper`() {
        val actions = OdioService().actions(context())
        assertEquals("sudo gryonixnexus-odio-ctl restart", actions.restart?.command)
        assertEquals("sudo gryonixnexus-odio-ctl status", (actions.statusProbe as StatusProbe.SystemdUnits).list.command)
        assertTrue(OdioService().sudoersLines(context()).contains(
            "admin ALL=(ALL) NOPASSWD: /usr/local/sbin/gryonixnexus-odio-ctl stop"))
        assertTrue(OdioService.controlScript().contains("runuser -u \"\$user\""))
    }

    @Test
    fun theDlnaSpeakerInstallsBothUnitsAndMarksItself() {
        val text = PackagedAudioService.UPMPDCLI.setupSteps(context()).single()
        assertTrue(text.contains("install -yq mpd upmpdcli avahi-daemon"), text)
        assertTrue(text.contains("systemctl restart mpd.service upmpdcli.service"))
        assertTrue(text.endsWith("touch /var/lib/gryonixnexus/packaged/upmpdcli"))
        assertTrue(PackagedAudioService.UPMPDCLI.uninstallSpec(context()).preSteps.any { it.contains("remove -yq upmpdcli >") })
    }

    @Test
    fun theBluetoothSpeakerKeepsBluezAndSharesSudoersWithTheAgent() {
        val bluetooth = PackagedAudioService.BLUEALSA
        val text = bluetooth.setupSteps(context()).single()
        assertTrue(text.contains("bt-agent --capability=NoInputNoOutput"))
        assertTrue(text.contains("s/^#\\?DiscoverableTimeout"), text)
        assertFalse(bluetooth.uninstallSpec(context()).preSteps.any { it.contains("remove -yq bluez ") })
        assertTrue(bluetooth.sudoersLines(context()).contains(
            "admin ALL=(ALL) NOPASSWD: /usr/bin/systemctl show bluetooth.service bluealsa.service " +
                "bluealsa-aplay.service gryonixnexus-bt-agent.service --property=Id --property=LoadState --property=ActiveState"))
        assertEquals(PackagedAudioService.ALL.map { it.id }.toSet(),
            ServiceRegistry.services(PackagedAudioService.ALL.map { it.id }.toSet()).map { it.id }.toSet())
    }

    @Test
    fun spotifyConnectInstallsAPinnedPackageNamedAfterTheMachine() {
        val text = PackagedAudioService.RASPOTIFY.setupSteps(context()).single()
        assertTrue(text.contains("raspotify_0.48.4.librespot.v0.8.0-99b6088_\$(dpkg --print-architecture).deb"), text)
        assertTrue(text.contains("LIBRESPOT_NAME=\\\"\$(hostname)\\\"/\" /etc/raspotify/conf\nsystemctl daemon-reload"), text)
        assertEquals(PackagedAudioService.SNAPSERVER.setupSteps(context()).single().lines().size, 7)
    }

    @Test
    fun theMusicLibraryAnswersOnItsOwnPortAndRemovalKeepsSharedUnits() {
        val text = PackagedAudioService.MYMPD.setupSteps(context()).single()
        assertTrue(text.contains("odio-mympd/releases/download/v26.1.2/mympd_26.1.2-1_\$(dpkg --print-architecture).deb"), text)
        assertTrue(text.contains("printf '[Service]\\nEnvironment=MYMPD_HTTP_PORT=8019"), text)
        assertEquals("systemctl disable --now mympd.service >/dev/null 2>&1 || true",
            PackagedAudioService.MYMPD.uninstallSpec(context()).preSteps.first())
        assertFalse(PackagedAudioService.BLUEALSA.uninstallSpec(context()).preSteps.first().contains(" bluetooth.service"))
    }

    @Test
    fun homeOnlyPortsSkipWebAndRepeats() {
        val ports = HomeOnlyPorts.of(
            listOf(PackagedAudioService.SNAPSERVER, PackagedAudioService.UPMPDCLI, PackagedAudioService.SNAPSERVER), context(),
        )
        assertEquals(listOf("tcp/1704", "tcp/1705", "tcp/1780", "udp/1900", "tcp/49152", "tcp/49153"),
            ports.map { "${it.proto.wireValue}/${it.port}" })
    }
}
