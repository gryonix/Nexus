package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.ArchiveBackupPlan
import com.skaymer.gryonixnexus.catalog.BackupDatabase
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
import com.skaymer.gryonixnexus.catalog.embedding

/** Nextcloud (files/calendar/contacts): nextcloud + mariadb + redis behind the shared Caddy ingress */
class NextcloudService : ManagedService {
    override val id = ServiceID.NEXTCLOUD
    override val displayName = "Nextcloud"
    override val systemImage = "icloud"
    override val category = ServiceCategory.FILES
    override val usesSharedAdminLogin = true
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    override val resources = ServiceResources(memoryMB = 768, diskGB = 3)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.nextcloudHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.NEXTCLOUD, context)
        } else {
            custom
        }
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.nextcloudPath
        val trusted = context.servedHostnames(hostname(context)).joinToString(" ")
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              db:
                image: $DATABASE_IMAGE
                restart: unless-stopped
                command: --transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW
                environment:
                  MYSQL_ROOT_PASSWORD: ${SH}{MYSQL_ROOT_PASSWORD}
                  MYSQL_PASSWORD: ${SH}{MYSQL_PASSWORD}
                  MYSQL_DATABASE: nextcloud
                  MYSQL_USER: nextcloud
                volumes:
                  - $path/db:/var/lib/mysql
              redis:
                image: $CACHE_IMAGE
                restart: unless-stopped
              app:
                image: $IMAGE
                restart: unless-stopped
                depends_on:
                  - db
                  - redis
                environment:
                  MYSQL_HOST: db
                  MYSQL_PASSWORD: ${SH}{MYSQL_PASSWORD}
                  MYSQL_DATABASE: nextcloud
                  MYSQL_USER: nextcloud
                  REDIS_HOST: redis
                  NEXTCLOUD_ADMIN_USER: ${context.settings.adminUsername}
                  NEXTCLOUD_ADMIN_PASSWORD: ${SH}{NEXTCLOUD_ADMIN_PASSWORD}
                  NEXTCLOUD_TRUSTED_DOMAINS: $trusted
                  @PROXY@
                volumes:
                  - $path/data:/var/www/html
                ports:
                  - "127.0.0.1:$WEB_UI_PORT:80"
              cron:
                image: $IMAGE
                restart: unless-stopped
                entrypoint: /cron.sh
                depends_on:
                  - app
                volumes:
                  - $path/data:/var/www/html
            """.trimIndent().embedding("PROXY" to proxyEnvironment(context)),
            envTemplate = """
            MYSQL_ROOT_PASSWORD=__RANDOM__
            MYSQL_PASSWORD=__RANDOM__
            NEXTCLOUD_ADMIN_PASSWORD=__RANDOM__
            """.trimIndent()
        )
    }

    /** Caddy's headers, and HTTPS links on a public server */
    private fun proxyEnvironment(context: ServiceContext): String =
        if (context.usesInternalTLS) "TRUSTED_PROXIES: $TRUSTED_PROXIES"
        else "TRUSTED_PROXIES: $TRUSTED_PROXIES\n      OVERWRITEPROTOCOL: https"

    /** Links follow the address the request used */
    private fun linkSetters(context: ServiceContext): String {
        val lang = context.language
        if (!context.usesInternalTLS) {
            return "nc_occ config:system:delete overwritehost\n" +
                "    nc_occ config:system:set overwriteprotocol --value=https \\\n" +
                "      || log \"${L10nServices.nextcloudConfigSetFailed(lang, "overwriteprotocol")} (${SH}(nc_why))\""
        }
        val slot = context.servedHostnames(hostname(context)).size + 1
        return "nc_occ config:system:set trusted_domains $slot --value='*' \\\n" +
            "      || log \"${L10nServices.nextcloudConfigSetFailed(lang, "trusted_domains $slot")} (${SH}(nc_why))\"\n" +
            "    nc_occ config:system:delete overwritehost\n" +
            "    nc_occ config:system:delete overwriteprotocol"
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.nextcloudPath
        val lang = context.language
        val trustedDomainSetters = context.servedHostnames(hostname(context))
            .mapIndexed { index, host ->
                val key = "trusted_domains ${index + 1}"
                "nc_occ config:system:set trusted_domains ${index + 1} --value=$host \\\n" +
                "      || log \"${L10nServices.nextcloudConfigSetFailed(lang, key)} (${SH}(nc_why))\""
            }
            .joinToString("\n    ")
        return listOf(
            """
            log "Nextcloud: ${L10nServices.serviceStarting(lang)}"
            install -d $path
            cd $path
            docker compose -p $COMPOSE_PROJECT pull -q
            docker compose -p $COMPOSE_PROJECT up -d
            """.trimIndent(),
            """
            cd $path
            # Nextcloud writes trusted_domains/overwritehost into config.php only
            # when it FIRST initialises the instance; the compose environment is
            # ignored afterwards. A reinstall onto another domain would therefore
            # be met with "Access through untrusted domain". Re-apply the
            # current hostname on every run — a no-op when it already matches.
            NC_APP="${SH}(docker compose -p $COMPOSE_PROJECT ps -q app 2>/dev/null | head -n1)"
            if [ -n "${SH}NC_APP" ]; then
              # occ's output is CAPTURED, never discarded, and no call here is
              # fatal — the same rule the mailcow API block follows. This ran
              # `occ … >/dev/null 2>&1` outside any `if`, so a freshly started
              # instance that answered `status` but was not ready for
              # config:system:set killed the whole install through errexit: on
              # a real run it died at step 9 of 22 with exit 1 and NOT ONE line
              # of explanation, leaving a half-configured server. A trusted
              # domain can be fixed from the admin UI; a half-install cannot.
              NC_OUT=""
              nc_occ() { NC_OUT="${SH}(docker exec -u www-data "${SH}NC_APP" php occ "${SH}@" 2>&1)"; }
              # Why the last call failed, bounded to one line: occ can answer
              # with a stack trace, and the app streams this log.
              nc_why() { printf '%s' "${SH}NC_OUT" | tr -d '\r\n' | cut -c1-300; }
              # **`occ status` EXITS 0 on an instance that is not installed,
              # and reading its status as readiness is why every setting below
              # was lost.** On a fresh container it answers
              # "Nextcloud is not installed - only a limited number of commands
              # are available" and returns success, so the wait broke out on
              # its very first try and every `config:system:set` after it died
              # with "There are no commands defined in the config:system
              # namespace". The visible cost was an instance left on the
              # image's own `overwrite.cli.url` — https://localhost — with the
              # log carrying three failures nobody could act on. The ANSWER is what has to be read, not
              # the status: `installed: true` is printed only once the
              # installer has finished.
              nc_ready() {
                nc_occ status || return 1
                printf '%s' "${SH}NC_OUT" | grep -q 'installed: true'
              }
              for _ in ${SH}(seq 1 60); do
                nc_ready && break
                sleep 5
              done
              if nc_ready; then
                # Index 1, never 0: slot 0 holds "localhost" from the image's own
                # installer and dropping it would cut local access off.
                # One slot per name the Caddy site serves — the alias domains
                # included, or Nextcloud answers them "untrusted domain" while
                # Caddy happily holds a certificate for them.
                @TRUSTED@
                @LINKS@
                nc_occ config:system:set overwrite.cli.url --value=https://${hostname(context)} \
                  || log "${L10nServices.nextcloudConfigSetFailed(lang, "overwrite.cli.url")} (${SH}(nc_why))"
                # Background jobs by the cron container, heavy jobs at night.
                nc_occ config:system:set maintenance_window_start --type=integer --value=1 \
                  || log "${L10nServices.nextcloudConfigSetFailed(lang, "maintenance_window_start")} (${SH}(nc_why))"
                nc_occ background:cron \
                  || log "${L10nServices.nextcloudConfigSetFailed(lang, "background:cron")} (${SH}(nc_why))"
                nc_occ db:add-missing-indices \
                  || log "${L10nServices.nextcloudConfigSetFailed(lang, "db:add-missing-indices")} (${SH}(nc_why))"
                nc_occ maintenance:repair --include-expensive \
                  || log "${L10nServices.nextcloudConfigSetFailed(lang, "maintenance:repair")} (${SH}(nc_why))"
              else
                log "${L10nServices.nextcloudOccUnavailable(lang)} (${SH}(nc_why))"
              fi
            fi
            """.trimIndent().embedding("TRUSTED" to trustedDomainSetters, "LINKS" to linkSetters(context))
        )
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT)

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val path = context.settings.nextcloudPath
        val lang = context.language
        val passwordLabel = L10nServices.passwordGeneratedOnServerLabel(lang)
        return listOf("""
        echo "Nextcloud:    https://${hostname(context)}"
        echo "  ${L10nServices.administratorLabel(lang)}: ${context.settings.adminUsername}"
        echo "  $passwordLabel: ${SH}(grep '^NEXTCLOUD_ADMIN_PASSWORD=' $path/.env | cut -d= -f2-)"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.nextcloudPath
        return ServiceActions(
            statusProbe = StatusProbe.ComposeProject(
                project = COMPOSE_PROJECT,
                list = PrivilegedCommand("/usr/bin/docker", "compose -p $COMPOSE_PROJECT ps")
            ),
            restart = ServicePower.compose(COMPOSE_PROJECT, "restart"),
            start = ServicePower.compose(COMPOSE_PROJECT, "start"),
            stop = ServicePower.compose(COMPOSE_PROJECT, "stop"),
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
                    databases = listOf(BackupDatabase(
                        engine = BackupDatabase.Engine.MYSQL,
                        service = "db",
                        fileName = "nextcloud.sql"
                    )),
                    quiesceServices = listOf("app"),
                    encryptsByDefault = false,
                    sizePaths = listOf("$path/data", "$path/db")
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

    override fun updateSpec(context: ServiceContext) =
        UpdateSpec(images = listOf(IMAGE, DATABASE_IMAGE, CACHE_IMAGE))

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        configDirectory = context.settings.nextcloudPath,
        dataPaths = listOf("${context.settings.nextcloudPath}/data.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val TRUSTED_PROXIES = "127.0.0.1 172.16.0.0/12 192.168.0.0/16"
        const val COMPOSE_PROJECT = "nextcloud"
        const val WEB_UI_PORT = 8081

        /** Label the backup and restore wrappers case on */
        val WRAPPER_TARGET = ServiceID.NEXTCLOUD.rawValue

        const val IMAGE = "nextcloud:35-apache"
        const val DATABASE_IMAGE = "mariadb:11"
        const val CACHE_IMAGE = "redis:7-alpine"
    }
}
