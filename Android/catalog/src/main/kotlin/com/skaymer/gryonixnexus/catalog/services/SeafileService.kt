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

class SeafileService : ManagedService {
    override val id = ServiceID.SEAFILE
    override val displayName = "Seafile"
    override val systemImage = "folder.badge.person.crop"
    override val category = ServiceCategory.FILES
    override val usesSharedAdminLogin = true
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    override val resources = ServiceResources(memoryMB = 1024, diskGB = 4)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.seafileHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.SEAFILE, context)
        } else {
            custom
        }
    }

    fun adminLogin(context: ServiceContext): String =
        "${context.settings.adminUsername}@${context.domain}"

    private fun dataPath(context: ServiceContext): String = "${context.settings.seafilePath}/data"

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.seafilePath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              db:
                image: $DATABASE_IMAGE
                restart: unless-stopped
                environment:
                  # The shared backup wrapper dumps through this variable, read
                  # out of the container's OWN environment — a password passed
                  # from the host would sit in the argv of docker exec, where
                  # /proc hands it to every account. There is deliberately no
                  # MYSQL_DATABASE: Seafile owns three, and the backup plan
                  # names each one instead.
                  MYSQL_ROOT_PASSWORD: ${SH}{SEAFILE_DB_ROOT_PASSWORD}
                  MARIADB_AUTO_UPGRADE: "1"
                volumes:
                  - $path/db:/var/lib/mysql
              redis:
                image: $CACHE_IMAGE
                restart: unless-stopped
                # Cache only, so persistence is off: an appendonly file here
                # would be disk traffic for data that is rebuilt on demand.
                # No password either — redis takes it as a command-line
                # argument, which puts it in the process table where the host
                # can read it, and it buys nothing over a port that is never
                # published outside this project's own network.
                command: ["redis-server", "--save", "", "--appendonly", "no"]
              seafile:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                depends_on:
                  - db
                  - redis
                environment:
                  SEAFILE_MYSQL_DB_HOST: db
                  SEAFILE_MYSQL_DB_PORT: "3306"
                  SEAFILE_MYSQL_DB_USER: seafile
                  SEAFILE_MYSQL_DB_PASSWORD: ${SH}{SEAFILE_DB_PASSWORD}
                  # Only used on the first start, to create the three schemas
                  # and the unprivileged user above.
                  INIT_SEAFILE_MYSQL_ROOT_PASSWORD: ${SH}{SEAFILE_DB_ROOT_PASSWORD}
                  SEAFILE_MYSQL_DB_CCNET_DB_NAME: ccnet_db
                  SEAFILE_MYSQL_DB_SEAFILE_DB_NAME: seafile_db
                  SEAFILE_MYSQL_DB_SEAHUB_DB_NAME: seahub_db
                  # The administrator, created on the first start. Left unset,
                  # Seafile creates me@example.com with the password `asecret`
                  # — a documented credential on a public hostname.
                  INIT_SEAFILE_ADMIN_EMAIL: ${adminLogin(context)}
                  INIT_SEAFILE_ADMIN_PASSWORD: ${SH}{SEAFILE_ADMIN_PASSWORD}
                  # SERVICE_URL and FILE_SERVER_ROOT are derived from these two
                  # on every start, so they stay SINGLE-valued at the canonical
                  # name even though the Caddy site answers on the aliases too.
                  # The protocol must be https: it is what the browser speaks,
                  # and an http value here makes every download link a
                  # mixed-content block.
                  SEAFILE_SERVER_HOSTNAME: ${hostname(context)}
                  SEAFILE_SERVER_PROTOCOL: https
                  SITE_ROOT: /
                  NON_ROOT: "false"
                  TIME_ZONE: Etc/UTC
                  JWT_PRIVATE_KEY: ${SH}{SEAFILE_JWT_PRIVATE_KEY}
                  # SeaDoc is a SEPARATE container upstream ships in its own
                  # compose file. Left at its default (true) the server
                  # advertises a /sdoc-server endpoint that nothing answers, so
                  # opening a document fails with no explanation — off is the
                  # honest state of an install that does not include it.
                  ENABLE_SEADOC: "false"
                  CACHE_PROVIDER: redis
                  REDIS_HOST: redis
                  REDIS_PORT: "6379"
                volumes:
                  - ${dataPath(context)}:/shared
                ports:
                  # The container runs its own nginx on 80, which fronts
                  # seahub, the file server and WebDAV on one port.
                  - "127.0.0.1:$WEB_UI_PORT:80"
            """.trimIndent() + homeDoor(context),
            envTemplate = """
            SEAFILE_DB_ROOT_PASSWORD=__RANDOM__
            SEAFILE_DB_PASSWORD=__RANDOM__
            SEAFILE_JWT_PRIVATE_KEY=__RANDOM__
            SEAFILE_ADMIN_PASSWORD=__RANDOM__
            """.trimIndent()
        )
    }

    /** Apps at home get links on the plain address */
    private fun homeDoor(context: ServiceContext): String {
        if (!context.usesInternalTLS) return ""
        val name = "https://${hostname(context)}"
        val v = "\$\$"
        return """
            |
            |  home-door:
            |    image: $HOME_DOOR_IMAGE
            |    restart: unless-stopped
            |    depends_on:
            |      - seafile
            |    # Seafile's links carry its HTTPS name; apps at home
            |    # reach it by address, so the links follow the address.
            |    command:
            |      - /bin/sh
            |      - -c
            |      - |
            |        cat > /etc/nginx/conf.d/default.conf <<'CONF'
            |        server {
            |            listen 80;
            |            client_max_body_size 0;
            |            proxy_request_buffering off;
            |            location / {
            |                proxy_pass http://seafile:80;
            |                proxy_http_version 1.1;
            |                proxy_set_header Host ${v}http_host;
            |                proxy_set_header X-Forwarded-For ${v}proxy_add_x_forwarded_for;
            |                proxy_set_header X-Forwarded-Proto http;
            |                proxy_set_header Accept-Encoding "";
            |                proxy_redirect $name/ /;
            |                proxy_read_timeout 1200s;
            |                sub_filter_types application/json text/javascript application/javascript;
            |                sub_filter_once off;
            |                sub_filter "$name" "http://${v}http_host";
            |            }
            |        }
            |        CONF
            |        exec nginx -g 'daemon off;'
            |    ports:
            |      - "127.0.0.1:$HOME_DOOR_PORT:80"
            """.trimMargin()
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.seafilePath
        val data = dataPath(context)
        val lang = context.language
        val trustedOrigins = context.servedHostnames(hostname(context))
            .joinToString(", ") { "'https://$it'" }
        return listOf(
            """
            log "Seafile: ${L10nServices.serviceStarting(lang)}"
            # Modes spelled out rather than left to the umask: the container
            # writes into /shared as its own user.
            install -d -m 755 $data $path/db
            cd $path
            docker compose -p $COMPOSE_PROJECT pull -q
            docker compose -p $COMPOSE_PROJECT up -d
            """.trimIndent(),
            """
            # Trusted CSRF origins — see the type comment. Without them the
            # sign-in POST is refused by Django with a CSRF error that reads
            # like a wrong password, because Caddy terminates TLS and the
            # container's nginx never tells Django the request was https.
            #
            # Nothing below is fatal and no output is discarded: the same rule
            # the mailcow API, Nextcloud occ and Forgejo admin blocks follow.
            # This step sits in the middle of a `set -euo pipefail` script whose
            # remaining work includes revoking the install key.
            SF_CONF='$data/seafile/conf/seahub_settings.py'
            SF_OUT=""
            # Why the wait is still going, bounded to one line — the server's
            # own log is the only explanation there is, and the app streams
            # this output.
            sf_why() {
              SF_OUT="${SH}(timeout 20 docker compose -p $COMPOSE_PROJECT logs --tail=20 seafile 2>&1 || true)"
              printf '%s' "${SH}SF_OUT" | tr -d '\r\n' | cut -c1-300
            }
            # A deadline, not a number of tries: the first start creates three
            # schemas and runs the whole migration set, which takes minutes on
            # a small ARM board, and every probe can burn its own timeout.
            SF_READY=0
            SF_TRY=0
            SF_DEADLINE=${SH}((${SH}(date +%s) + 600))
            while [ "${SH}(date +%s)" -lt "${SH}SF_DEADLINE" ]; do
              if [ -f "${SH}SF_CONF" ]; then SF_READY=1; break; fi
              SF_TRY=${SH}((SF_TRY + 1))
              # Heartbeat every ~30 s: a silent wait is indistinguishable from
              # a hung install in the app's progress view.
              if [ "${SH}((SF_TRY % 6))" -eq 0 ]; then
                log "${L10nServices.seafileWaiting(lang)} (${SH}(sf_why))"
              fi
              sleep 5
            done
            if [ "${SH}SF_READY" -eq 1 ]; then
              # Rewritten on EVERY run, not appended once: the served name list
              # changes when the owner adds a domain, and Seafile reads this
              # file only at start. Same reason Nextcloud re-applies its
              # trusted domains instead of trusting the first install.
              sed -i '/^CSRF_TRUSTED_ORIGINS = /d' "${SH}SF_CONF"
              printf '%s\n' "CSRF_TRUSTED_ORIGINS = [$trustedOrigins]" >> "${SH}SF_CONF"
              docker compose -p $COMPOSE_PROJECT restart seafile >/dev/null 2>&1 || true
            else
              log "${L10nServices.seafileUnavailable(lang)} (${SH}(sf_why))"
            fi
            """.trimIndent()
        )
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT)

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val path = context.settings.seafilePath
        val lang = context.language
        return listOf("""
        echo "Seafile:      https://${hostname(context)}"
        echo "  ${L10nServices.administratorLabel(lang)}: ${adminLogin(context)}"
        echo "  ${L10nServices.passwordGeneratedOnServerLabel(lang)}: ${SH}(grep '^SEAFILE_ADMIN_PASSWORD=' $path/.env | cut -d= -f2-)"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.seafilePath
        val data = dataPath(context)
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
                    dataPath = data,
                    databases = listOf(
                        BackupDatabase(BackupDatabase.Engine.MYSQL, "db",
                                       "ccnet_db.sql", "ccnet_db"),
                        BackupDatabase(BackupDatabase.Engine.MYSQL, "db",
                                       "seafile_db.sql", "seafile_db"),
                        BackupDatabase(BackupDatabase.Engine.MYSQL, "db",
                                       "seahub_db.sql", "seahub_db")
                    ),
                    quiesceServices = listOf("seafile"),
                    encryptsByDefault = false,
                    sizePaths = listOf(data, "$path/db"),
                    excludes = listOf("data/logs")
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
        configDirectory = context.settings.seafilePath,
        dataPaths = listOf("${dataPath(context)}.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "seafile"
        const val CONTAINER = "seafile"

        /** Loopback port Caddy proxies to */
        const val WEB_UI_PORT = 8088
        val WRAPPER_TARGET = ServiceID.SEAFILE.rawValue

        const val IMAGE = "seafileltd/seafile-mc:13.0.25"

        const val DATABASE_IMAGE = "mariadb:10.11"

        /** Cache only */
        const val CACHE_IMAGE = "redis:7-alpine"

        /** Rewrites links for apps at home */
        const val HOME_DOOR_IMAGE = "nginx:1.29-alpine"

        /** Loopback port of the home link rewriter */
        const val HOME_DOOR_PORT = 8188
    }
}
