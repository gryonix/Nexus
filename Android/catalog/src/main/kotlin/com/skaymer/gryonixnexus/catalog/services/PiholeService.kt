package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.embedding
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

class PiholeService : ManagedService {
    override val id = ServiceID.PIHOLE
    override val displayName = "Pi-hole"
    override val systemImage = "shield.lefthalf.filled"
    override val category = ServiceCategory.NETWORK

    override val usesSharedAdminLogin = false
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    override val resources = ServiceResources(memoryMB = 256, diskGB = 2)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.piholeHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.PIHOLE, context)
        } else {
            custom
        }
    }

    /** The upstreams as the container's own resolvers */
    private fun containerDNS(upstreams: String): String {
        val servers = upstreams.split(";").map { it.trim() }.filter { it.isNotEmpty() && "#" !in it }
        if (servers.isEmpty()) return ""
        return "\n    # Blocklist downloads resolve here, not at the router\n    dns:" +
            servers.joinToString("") { "\n      - $it" }
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.piholePath
        val dnsBind = if (context.settings.piholeServesNetwork) "" else "127.0.0.1:"
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              pihole:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped@DNS@
                environment:
                  # Read by FTL itself: every `FTLCONF_<section>_<key>` maps to
                  # the matching key of pihole.toml. Verified in the pinned
                  # image's own `bash_functions.sh`, not assumed.
                  FTLCONF_webserver_api_password: ${SH}{PIHOLE_ADMIN_PASSWORD}
                  # `local` — FTL's default — answers only the subnets of its
                  # own interfaces, and inside a container that is the docker
                  # bridge alone: every forwarded query would be refused, which
                  # reads as "the filter does not work" rather than as a bind
                  # setting. What is actually reachable is decided by the
                  # published address below.
                  FTLCONF_dns_listeningMode: all
                  FTLCONF_dns_upstreams: ${context.settings.piholeUpstreams}
                volumes:
                  - $path/etc-pihole:/etc/pihole
                ports:
                  - "127.0.0.1:$WEB_UI_PORT:$CONTAINER_WEB_PORT/tcp"
                  # See the type comment: a published port is reachable
                  # regardless of our nftables ruleset, so an open resolver is
                  # prevented by the bind address or nowhere.
                  - "${dnsBind}53:53/tcp"
                  - "${dnsBind}53:53/udp"
            """.trimIndent().embedding("DNS" to containerDNS(context.settings.piholeUpstreams)),
            envTemplate = """
            PIHOLE_ADMIN_PASSWORD=__RANDOM__
            """.trimIndent()
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.piholePath
        val lang = context.language
        return listOf(
            """
            log "Pi-hole: ${L10nServices.serviceStarting(lang)}"
            install -d -m 755 $path/etc-pihole
            cd $path
            docker compose -p $COMPOSE_PROJECT pull -q
            docker compose -p $COMPOSE_PROJECT up -d
            """.trimIndent(),
            """
            # Wait for the resolver to actually answer, by a DEADLINE rather
            # than a number of tries: each probe can burn its own timeout, so
            # counting tries makes the real wait unbounded (the same lesson the
            # mailcow API block was written from).
            #
            # The probe is a DNS query, not "the container is up": Pi-hole
            # downloads its blocklists on first start (`gravity`), and until
            # that finishes it is running and answering nothing. Nothing here
            # is fatal — a filter that is still building its list is a working
            # install a few minutes early, and failing the whole setup over it
            # would take the remaining services and the install-key revocation
            # with it.
            PH_DEADLINE=${SH}((${SH}(date +%s) + 300))
            PH_TRY=0
            PH_READY=0
            while [ "${SH}(date +%s)" -lt "${SH}PH_DEADLINE" ]; do
              if docker exec $CONTAINER dig +short +norecurse +retry=0 \
                   @127.0.0.1 pi.hole >/dev/null 2>&1; then
                PH_READY=1
                break
              fi
              PH_TRY=${SH}((PH_TRY + 1))
              # Heartbeat every ~30 s: a silent wait is indistinguishable from
              # a hung install in the app's progress view.
              if [ "${SH}((PH_TRY % 6))" -eq 0 ]; then
                log "${L10nServices.piholeWaiting(lang)}"
              fi
              sleep 5
            done
            if [ "${SH}PH_READY" -ne 1 ]; then
              log "${L10nServices.piholeUnavailable(lang)}"
            fi
            """.trimIndent()
        )
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> {
        if (!context.settings.piholeServesNetwork) return emptyList()
        return listOf(
            FirewallPort(53, comment = "DNS"),
            FirewallPort(53, FirewallPort.Proto.UDP, comment = "DNS")
        )
    }

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT)

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val path = context.settings.piholePath
        val lang = context.language
        val host = hostname(context)
        val bindNote = if (context.settings.piholeServesNetwork) {
            """echo "  ${L10nServices.piholeServesNetworkNote(lang)}""""
        } else {
            """echo "  ${L10nServices.piholeLoopbackNote(lang)}""""
        }
        return listOf("""
        echo "Pi-hole: https://$host/admin"
        echo "  ${L10nServices.passwordGeneratedOnServerLabel(lang)}: ${SH}(grep '^PIHOLE_ADMIN_PASSWORD=' $path/.env | cut -d= -f2-)"
        $bindNote
        """.trimIndent())
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.piholePath
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
                    dataPath = "$path/etc-pihole",
                    databases = emptyList(),
                    quiesceServices = emptyList(),
                    encryptsByDefault = true,
                    sizePaths = listOf("$path/etc-pihole")
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
        configDirectory = context.settings.piholePath,
        dataPaths = listOf("${context.settings.piholePath}/etc-pihole.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "pihole"
        const val CONTAINER = "pihole"

        const val WEB_UI_PORT = 8092

        /** Port the admin interface binds INSIDE the container */
        const val CONTAINER_WEB_PORT = 80
        val WRAPPER_TARGET = ServiceID.PIHOLE.rawValue

        /** Exact patch tag */
        const val IMAGE = "pihole/pihole:2026.07.2"
    }
}
