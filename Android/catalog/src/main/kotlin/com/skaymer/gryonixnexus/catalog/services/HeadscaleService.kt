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
import com.skaymer.gryonixnexus.catalog.ServiceDefaultHostnames
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServicePower
import com.skaymer.gryonixnexus.catalog.ServiceResources
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress

class HeadscaleService : ManagedService {
    override val id = ServiceID.HEADSCALE
    override val displayName = "Headscale"
    override val systemImage = "point.3.filled.connected.trianglepath.dotted"
    override val category = ServiceCategory.MESH

    override val usesSharedAdminLogin = false

    override val requiresPublicDomain = true
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    /** One Go daemon with a SQLite file */
    override val resources = ServiceResources(memoryMB = 256, diskGB = 2)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.headscaleHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.HEADSCALE, context)
        } else {
            custom
        }
    }

    fun baseDomain(context: ServiceContext): String {
        val custom = context.settings.headscaleBaseDomain
        return if (custom.isEmpty()) "ts.${context.domain}" else custom
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.headscalePath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              headscale:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                command: serve
                volumes:
                  - $path/config:/etc/headscale
                  - $path/data:/var/lib/headscale
                ports:
                  # Loopback only: Caddy terminates TLS in front of it, which
                  # also puts it under the lockdown guard like every other UI.
                  # The clients REQUIRE the control server over HTTPS, and the
                  # certificate is Caddy's.
                  - "127.0.0.1:$WEB_UI_PORT:$CONTAINER_PORT"
                  # Public on purpose — STUN for the embedded DERP relay. A
                  # relay only reachable from this host relays nothing.
                  - "$STUN_PORT:$STUN_PORT/udp"
            """.trimIndent()
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.headscalePath
        val lang = context.language
        val host = hostname(context)
        val base = baseDomain(context)
        return listOf("""
        log "Headscale: ${L10nServices.serviceStarting(lang)}"
        install -d -m 755 $path/config $path/data
        # Written every run: the file is ours, and a domain or hostname
        # change has to reach it. Headscale generates its own noise key
        # into the data directory on first start and never rewrites it.
        cat > $path/config/config.yaml <<'EOF_HEADSCALE'
        server_url: https://$host
        listen_addr: 0.0.0.0:$CONTAINER_PORT
        metrics_listen_addr: 127.0.0.1:9090
        noise:
          private_key_path: /var/lib/headscale/noise_private.key
        prefixes:
          v4: 100.64.0.0/10
          v6: fd7a:115c:a1e0::/48
          allocation: sequential
        derp:
          server:
            # The point of self-hosting: without this, a node that cannot
            # reach its peer directly falls back to Tailscale's public
            # relays. Measured — a lab node reported a relay region abroad
            # while this was off.
            enabled: true
            region_id: 999
            region_code: "gryonix"
            region_name: "$host"
            stun_listen_addr: "0.0.0.0:$STUN_PORT"
            private_key_path: /var/lib/headscale/derp_server_private.key
          # No public relay map: everything stays on this host.
          urls: []
          auto_update_enabled: false
        database:
          type: sqlite
          sqlite:
            path: /var/lib/headscale/db.sqlite
        log:
          level: info
        dns:
          magic_dns: true
          base_domain: $base
          # Service names inside the mesh, pointed at this server's own
          # mesh address. A separate FILE rather than an inline
          # `extra_records` block (the two are mutually exclusive) because
          # the addresses are not known now: a node's mesh address is
          # handed out when it joins, which is after this file is written.
          extra_records_path: /etc/headscale/extra-records.json
          nameservers:
            global:
              - 1.1.1.1
        policy:
          mode: database
        EOF_HEADSCALE
        chmod 600 $path/config/config.yaml
        # Created only when ABSENT, unlike config.yaml: this file holds the
        # published names, and rewriting it on every run would drop them on
        # the next re-install.
        #
        # The second test REPAIRS what older builds wrote here.
        # "unmarshalling records, content: [] backslash n"). A file that
        # does not parse cannot be holding published names, so replacing
        # exactly that content loses nothing; anything else is left alone.
        HS_RECORDS=$path/config/extra-records.json
        if [ ! -f "${SH}HS_RECORDS" ] || [ "${SH}(cat "${SH}HS_RECORDS")" = '[]\n' ]; then
          printf '[]\n' > "${SH}HS_RECORDS"
          chmod 644 "${SH}HS_RECORDS"
        fi
        cd $path
        docker compose -p $COMPOSE_PROJECT pull -q
        docker compose -p $COMPOSE_PROJECT up -d
        """.trimIndent())
    }

    /** STUN only */
    override fun firewallPorts(context: ServiceContext) = listOf(
        FirewallPort(STUN_PORT, FirewallPort.Proto.UDP, comment = "Headscale DERP STUN")
    )

    override fun webIngress(context: ServiceContext) = WebIngress(
        hostname = hostname(context),
        upstreamPort = WEB_UI_PORT,
        adminGuard = false
    )

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val lang = context.language
        val host = hostname(context)
        val base = baseDomain(context)
        return listOf("""
        echo "Headscale: https://$host"
        echo "  ${L10nServices.headscaleNoWebUINote(lang)}"
        echo "  ${L10nServices.headscaleCreateUserNote(lang)}:"
        echo "    sudo docker exec $CONTAINER headscale users create <name>"
        echo "    sudo docker exec $CONTAINER headscale preauthkeys create --user <id> --reusable --expiration 24h"
        echo "  ${L10nServices.headscaleJoinNote(lang)}:"
        echo "    tailscale up --login-server https://$host --authkey <key>"
        echo "  ${L10nServices.headscaleMagicDNSNote(lang)}: <device>.$base"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.headscalePath
        return ServiceActions(
            statusProbe = StatusProbe.Container(
                name = CONTAINER,
                list = PrivilegedCommand("/usr/bin/docker", "ps -a")
            ),
            restart = ServicePower.container(CONTAINER, "restart"),
            start = ServicePower.container(CONTAINER, "start"),
            stop = ServicePower.container(CONTAINER, "stop"),
            backup = BackupSpec.WrapperScript(BackupWrapperSpec(
                wrapperTarget = WRAPPER_TARGET,
                backupDir = context.backupDirectory(id),
                run = ServiceCommand(
                    PrivilegedCommand(BackupWrapperSpec.WRAPPER_PATH, ""),
                    ServiceCommand.TimeoutClass.LONG,
                    streamsOutput = true
                ),
                plan = BackupPlan.Archive(ArchiveBackupPlan(
                    composeProject = COMPOSE_PROJECT,
                    dataPath = "$path/data",
                    databases = emptyList(),
                    quiesceServices = listOf(CONTAINER),
                    encryptsByDefault = true,
                    sizePaths = listOf("$path/data")
                ))
            )),
            restore = RestoreSpec(
                wrapperTarget = WRAPPER_TARGET,
                backupDir = context.backupDirectory(id),
                needsPassphrase = false,
                privileged = PrivilegedCommand(RestoreSpec.WRAPPER_PATH, "")
            )
        )
    }

    override fun updateSpec(context: ServiceContext) = UpdateSpec(images = listOf(IMAGE))

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        configDirectory = context.settings.headscalePath,
        dataPaths = listOf("${context.settings.headscalePath}/data.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "headscale"
        const val CONTAINER = "headscale"

        const val WEB_UI_PORT = 8091

        /** The port headscale serves on INSIDE the container */
        const val CONTAINER_PORT = 8080

        /** STUN, for the embedded DERP relay */
        const val STUN_PORT = 3478
        val WRAPPER_TARGET = ServiceID.HEADSCALE.rawValue

        /** Exact patch tag */
        const val IMAGE = "headscale/headscale:v0.29.3"
    }
}
