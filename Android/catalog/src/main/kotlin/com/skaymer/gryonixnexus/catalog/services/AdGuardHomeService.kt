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

class AdGuardHomeService : ManagedService {
    override val id = ServiceID.ADGUARD_HOME
    override val displayName = "AdGuard Home"
    override val systemImage = "shield.lefthalf.filled"
    override val category = ServiceCategory.NETWORK

    override val usesSharedAdminLogin = true
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    /** One small Go daemon: it idles around 100 MiB */
    override val resources = ServiceResources(memoryMB = 256, diskGB = 2)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.adguardHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.ADGUARD_HOME, context)
        } else {
            custom
        }
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.adguardPath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              adguardhome:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                volumes:
                  - $path/conf:/opt/adguardhome/conf
                  - $path/work:/opt/adguardhome/work
                ports:
                  - "127.0.0.1:$WEB_UI_PORT:$CONTAINER_WEB_PORT"
                  # Loopback ONLY — see the type comment. A published port is
                  # reachable from the internet regardless of our nftables
                  # ruleset, so an open resolver is prevented here or nowhere.
                  - "127.0.0.1:53:53/tcp"
                  - "127.0.0.1:53:53/udp"
            """.trimIndent(),
            envTemplate = """
            ADGUARD_ADMIN_PASSWORD=__RANDOM__
            """.trimIndent()
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.adguardPath
        val lang = context.language
        val admin = context.settings.adminUsername
        return listOf(
            """
            log "AdGuard Home: ${L10nServices.serviceStarting(lang)}"
            install -d -m 755 $path/conf $path/work
            cd $path
            docker compose -p $COMPOSE_PROJECT pull -q
            docker compose -p $COMPOSE_PROJECT up -d
            """.trimIndent(),
            """
            # Initial configuration through AdGuard's own installation API.
            #
            # Without it AdGuard serves its SETUP WIZARD to whoever opens the
            # page, and this page is on a public hostname — the first visitor
            # would name the administrator and own the resolver. The password
            # is generated on the server, travels in a request BODY (never in
            # argv, where /proc hands it to every account) and is stored by
            # AdGuard as a bcrypt hash.
            #
            # Nothing below is fatal and no output is discarded: the same rule
            # the mailcow API and Nextcloud occ blocks follow. Under
            # `set -euo pipefail` a failure here would take the remaining
            # steps — including the install key revocation — with it.
            AG_CODE=""
            AG_BODY=""
            ag_api() {
              local method="${SH}1" path="${SH}2" data="${SH}{3:-}" out=""
              if [ -n "${SH}data" ]; then
                out="${SH}(timeout 20 curl -sS -X "${SH}method" -H 'Content-Type: application/json' \
                       --data-binary "@${SH}data" -w '\nGD_HTTP:%{http_code}' \
                       "http://127.0.0.1:$WEB_UI_PORT${SH}path" 2>&1)" || true
              else
                out="${SH}(timeout 20 curl -sS -X "${SH}method" -w '\nGD_HTTP:%{http_code}' \
                       "http://127.0.0.1:$WEB_UI_PORT${SH}path" 2>&1)" || true
              fi
              AG_CODE="${SH}(printf '%s' "${SH}out" | sed -n 's/^GD_HTTP://p' | tail -n1)"
              AG_BODY="${SH}(printf '%s' "${SH}out" | sed '/^GD_HTTP:/d')"
              case "${SH}AG_CODE" in 2*) return 0 ;; *) return 1 ;; esac
            }
            # Why the last call failed, bounded to one line — the body IS the
            # explanation, which is exactly what `curl -f` throws away.
            ag_why() { printf '%s %s' "${SH}{AG_CODE:-no-response}" "${SH}(printf '%s' "${SH}AG_BODY" | tr -d '\r\n' | cut -c1-300)"; }
            AG_CONF=$path/conf/AdGuardHome.yaml
            if [ ! -f "${SH}AG_CONF" ]; then
              # A deadline, not a number of tries: every attempt can burn its
              # own timeout, so counting attempts makes the real wait unbounded.
              AG_READY=0
              AG_TRY=0
              AG_DEADLINE=${SH}((${SH}(date +%s) + 300))
              while [ "${SH}(date +%s)" -lt "${SH}AG_DEADLINE" ]; do
                if ag_api GET /control/install/get_addresses; then AG_READY=1; break; fi
                AG_TRY=${SH}((AG_TRY + 1))
                # Heartbeat every ~30 s: a silent wait is indistinguishable
                # from a hung install in the app's progress view.
                if [ "${SH}((AG_TRY % 6))" -eq 0 ]; then
                  log "${L10nServices.adguardWaiting(lang)} (${SH}(ag_why))"
                fi
                sleep 5
              done
              if [ "${SH}AG_READY" -eq 1 ]; then
                AG_PASSWORD="${SH}(grep '^ADGUARD_ADMIN_PASSWORD=' $path/.env | cut -d= -f2- || true)"
                if [ -n "${SH}AG_PASSWORD" ]; then
                  AG_REQ="${SH}(mktemp)"
                  chmod 600 "${SH}AG_REQ"
                  # The web port MUST be the one the compose file publishes to,
                  # and the DNS port the one bound inside the container: this
                  # call is what AdGuard writes into its config and listens on
                  # from here on.
                  printf '{"web":{"ip":"0.0.0.0","port":%s},"dns":{"ip":"0.0.0.0","port":53},"username":"%s","password":"%s"}' \
                    $CONTAINER_WEB_PORT '$admin' "${SH}AG_PASSWORD" > "${SH}AG_REQ"
                  if ! ag_api POST /control/install/configure "${SH}AG_REQ"; then
                    log "${L10nServices.adguardConfigureFailed(lang)} (${SH}(ag_why))"
                  fi
                  rm -f "${SH}AG_REQ"
                fi
              else
                log "${L10nServices.adguardUnavailable(lang)} (${SH}(ag_why))"
              fi
            fi
            # Plain-HTTP DoH, so the filter can be used from anywhere through
            # Caddy without a public UDP resolver. The key MOVED in v0.107.74
            # (tls.allow_unencrypted_doh became http.doh.insecure_enabled), so
            # both spellings are handled: a pinned image is upgraded one day,
            # and a silently missing setting means DoH clients get a 404 with
            # nothing to explain it.
            if [ -f "${SH}AG_CONF" ]; then
              if grep -q '^ *insecure_enabled:' "${SH}AG_CONF"; then
                sed -i 's/^\( *\)insecure_enabled: false${SH}/\1insecure_enabled: true/' "${SH}AG_CONF"
              elif grep -q '^ *allow_unencrypted_doh:' "${SH}AG_CONF"; then
                sed -i 's/^\( *\)allow_unencrypted_doh: false${SH}/\1allow_unencrypted_doh: true/' "${SH}AG_CONF"
              else
                log "${L10nServices.adguardDoHKeyMissing(lang)}"
              fi
              docker compose -p $COMPOSE_PROJECT restart >/dev/null 2>&1 || true
            fi
            """.trimIndent()
        )
    }

    /** Nothing is opened */
    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT)

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val path = context.settings.adguardPath
        val lang = context.language
        val host = hostname(context)
        return listOf("""
        echo "AdGuard Home: https://$host"
        echo "  ${L10nServices.administratorLabel(lang)}: ${context.settings.adminUsername}"
        echo "  ${L10nServices.passwordGeneratedOnServerLabel(lang)}: ${SH}(grep '^ADGUARD_ADMIN_PASSWORD=' $path/.env | cut -d= -f2-)"
        echo "  ${L10nServices.adguardDoHNote(lang)}: https://$host/dns-query"
        echo "  ${L10nServices.adguardPlainDNSNote(lang)}"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.adguardPath
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
                    dataPath = "$path/conf",
                    databases = emptyList(),
                    quiesceServices = emptyList(),
                    encryptsByDefault = true,
                    sizePaths = listOf("$path/conf")
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
        configDirectory = context.settings.adguardPath,
        dataPaths = listOf("${context.settings.adguardPath}/conf.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "adguardhome"
        const val CONTAINER = "adguardhome"

        const val WEB_UI_PORT = 8087

        const val CONTAINER_WEB_PORT = 3000
        val WRAPPER_TARGET = ServiceID.ADGUARD_HOME.rawValue

        /** Exact patch tag */
        const val IMAGE = "adguard/adguardhome:v0.107.78"
    }
}
