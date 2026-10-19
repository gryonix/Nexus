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

class ForgejoService : ManagedService {
    override val id = ServiceID.FORGEJO
    override val displayName = "Forgejo"
    override val systemImage = "arrow.triangle.branch"
    override val category = ServiceCategory.CODE
    override val usesSharedAdminLogin = true
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    override val resources = ServiceResources(memoryMB = 512, diskGB = 3)

    /** Full web UI hostname */
    fun hostname(context: ServiceContext): String {
        val custom = context.settings.forgejoHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.FORGEJO, context)
        } else {
            custom
        }
    }

    fun adminUsername(context: ServiceContext): String {
        val shared = context.settings.adminUsername
        return if (shared.lowercase() in RESERVED_USERNAMES) "$shared-gryonix" else shared
    }

    fun sshPort(context: ServiceContext): Int? =
        context.settings.forgejoSSHPort.takeIf { it > 0 }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.forgejoPath
        val host = hostname(context)
        val ssh = sshPort(context)
        val sshSettings = if (ssh != null) {
            "\n" + listOf(
                "      # The image runs its OWN OpenSSH on 22 (an s6 service), and",
                "      # Forgejo's built-in server cannot have that port: it exits",
                "      # with \"address already in use\" and systemd-restarts forever. The",
                "      # container's sshd is the path upstream's own compose takes —",
                "      # Forgejo writes the authorized_keys it serves.",
                "      FORGEJO__server__START_SSH_SERVER: \"false\"",
                "      FORGEJO__server__SSH_DOMAIN: $host",
                "      FORGEJO__server__SSH_LISTEN_PORT: \"22\"",
                "      FORGEJO__server__SSH_PORT: \"$ssh\""
            ).joinToString("\n")
        } else {
            "\n      FORGEJO__server__START_SSH_SERVER: \"false\""
        }
        val sshPublish = ssh?.let { "\n      - \"$it:22\"" } ?: ""
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              db:
                image: $DATABASE_IMAGE
                restart: unless-stopped
                environment:
                  POSTGRES_USER: forgejo
                  POSTGRES_PASSWORD: ${SH}{POSTGRES_PASSWORD}
                  POSTGRES_DB: forgejo
                volumes:
                  - $path/db:/var/lib/postgresql/data
              server:
                image: $IMAGE
                container_name: $CONTAINER_NAME
                restart: unless-stopped
                depends_on:
                  - db
                environment:
                  USER_UID: 1000
                  USER_GID: 1000
                  FORGEJO__database__DB_TYPE: postgres
                  FORGEJO__database__HOST: db:5432
                  FORGEJO__database__NAME: forgejo
                  FORGEJO__database__USER: forgejo
                  FORGEJO__database__PASSWD: ${SH}{POSTGRES_PASSWORD}
                  FORGEJO__server__DOMAIN: $host
                  FORGEJO__server__ROOT_URL: https://$host/
                  FORGEJO__server__HTTP_PORT: "3000"@SSHSETTINGS@
                  # No web installer: the setup script has already provided the
                  # database and the administrator, and an unlocked instance
                  # hands its own configuration to whoever opens the page first.
                  FORGEJO__security__INSTALL_LOCK: "true"
                  # Closed by default — this is a personal forge on a public
                  # URL. Further users are invited from Site Administration.
                  FORGEJO__service__DISABLE_REGISTRATION: "true"
                volumes:
                  - $path/data:/var/lib/gitea
                  - /etc/localtime:/etc/localtime:ro
                ports:
                  - "127.0.0.1:$WEB_UI_PORT:3000"@SSHPUBLISH@
            """.trimIndent()
                .embedding("SSHSETTINGS" to sshSettings, "SSHPUBLISH" to sshPublish),
            envTemplate = """
            POSTGRES_PASSWORD=__RANDOM__
            FORGEJO_ADMIN_PASSWORD=__RANDOM__
            """.trimIndent()
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.forgejoPath
        val lang = context.language
        val admin = adminUsername(context)
        return listOf(
            """
            log "Forgejo: ${L10nServices.serviceStarting(lang)}"
            install -d -m 755 $path
            cd $path
            docker compose -p $COMPOSE_PROJECT pull -q
            docker compose -p $COMPOSE_PROJECT up -d
            """.trimIndent(),
            """
            # The administrator is created over the CLI, because with
            # INSTALL_LOCK set there is no web wizard left to create one — an
            # instance without this step has no way in at all.
            #
            # Nothing in this block is fatal and no output is discarded: the
            # same rule the mailcow API and the Nextcloud occ blocks follow.
            # A forge that came up without its admin account is fixable from
            # the server; an install killed at this step by errexit leaves the
            # remaining services unconfigured and the install key unrevoked.
            FJ_OUT=""
            fj_exec() { FJ_OUT="${SH}(timeout 120 docker exec -u git $CONTAINER_NAME "${SH}@" 2>&1)"; }
            # Why the last call failed, bounded to one line: Forgejo answers
            # with multi-line Go logs, and the app streams this log live.
            fj_why() { printf '%s' "${SH}FJ_OUT" | tr -d '\r\n' | cut -c1-300; }
            # A deadline, not a number of tries: each attempt can burn its own
            # timeout, so counting attempts makes the real wait unbounded.
            # `user list` doubles as the readiness probe: unlike `--version` it
            # has to reach the database, which is the thing that is actually
            # not ready yet while the containers already report up.
            FJ_READY=0
            FJ_TRY=0
            FJ_DEADLINE=${SH}((${SH}(date +%s) + 300))
            while [ "${SH}(date +%s)" -lt "${SH}FJ_DEADLINE" ]; do
              if fj_exec forgejo admin user list; then FJ_READY=1; break; fi
              # Heartbeat every ~30 s: a silent wait is indistinguishable from
              # a hung install in the app's progress view.
              FJ_TRY=${SH}((FJ_TRY + 1))
              if [ "${SH}((FJ_TRY % 6))" -eq 0 ]; then
                log "${L10nServices.forgejoWaiting(lang)} (${SH}(fj_why))"
              fi
              sleep 5
            done
            if [ "${SH}FJ_READY" -eq 1 ]; then
              # The probe's own output IS the user list — fj_exec captures
              # stdout into FJ_OUT, so piping the function would read nothing.
              # Anchored to the Username COLUMN (id, then the name): a bare
              # word match also hits the Email column, so any unrelated account
              # at $admin@... would look like the administrator already
              # existing and this step would silently skip creating it — a
              # forge nobody can log into, with one line in the log to say so.
              # `|| true`: under pipefail a grep that matches nothing would
              # fail the assignment and errexit would take the whole install.
              FJ_HAS_ADMIN="${SH}(printf '%s' "${SH}FJ_OUT" | grep -cE '^[0-9]+[[:space:]]+$admin[[:space:]]' || true)"
              FJ_ADMIN_PASSWORD="${SH}(grep '^FORGEJO_ADMIN_PASSWORD=' $path/.env | cut -d= -f2- || true)"
              if [ "${SH}FJ_HAS_ADMIN" -eq 0 ] && [ -n "${SH}FJ_ADMIN_PASSWORD" ]; then
                # The password is NOT reset on a re-run: the .env value is
                # stable, so the report keeps matching, and one the user has
                # changed in the web UI is left alone.
                fj_exec forgejo admin user create --admin --username $admin \
                  --password "${SH}FJ_ADMIN_PASSWORD" --email $admin@${context.domain} \
                  --must-change-password=false \
                  || log "${L10nServices.forgejoAdminCreateFailed(lang)} (${SH}(fj_why))"
              fi
            else
              log "${L10nServices.forgejoUnavailable(lang)} (${SH}(fj_why))"
            fi
            """.trimIndent()
        )
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> {
        val port = sshPort(context) ?: return emptyList()
        return listOf(FirewallPort(port, FirewallPort.Proto.TCP, comment = "git SSH"))
    }

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT)

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val path = context.settings.forgejoPath
        val lang = context.language
        val host = hostname(context)
        val lines = mutableListOf(
            """echo "Forgejo:      https://$host"""",
            """echo "  ${L10nServices.administratorLabel(lang)}: ${adminUsername(context)}"""",
            """echo "  ${L10nServices.passwordGeneratedOnServerLabel(lang)}: ${SH}(grep '^FORGEJO_ADMIN_PASSWORD=' $path/.env | cut -d= -f2-)"""",
            """echo "  ${L10nServices.forgejoRegistrationClosedNote(lang)}""""
        )
        val port = sshPort(context)
        if (port != null) {
            lines.add("""echo "  ${L10nServices.forgejoSSHNote(lang, host, port)}"""")
        } else {
            lines.add("""echo "  ${L10nServices.forgejoSSHDisabledNote(lang)}"""")
        }
        return listOf(lines.joinToString("\n"))
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.forgejoPath
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
                        engine = BackupDatabase.Engine.POSTGRES,
                        service = "db",
                        fileName = "forgejo.sql"
                    )),
                    quiesceServices = listOf("server"),
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
        UpdateSpec(images = listOf(IMAGE, DATABASE_IMAGE))

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        configDirectory = context.settings.forgejoPath,
        dataPaths = listOf("${context.settings.forgejoPath}/data.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "forgejo"

        val RESERVED_USERNAMES = setOf(
            "admin", "api", "assets", "attachments", "avatar", "avatars", "captcha",
            "commits", "debug", "devtest", "error", "explore", "ghost", "issues",
            "login", "metrics", "milestones", "new", "notifications", "org",
            "pulls", "raw", "repo", "repo-avatars", "search", "ssh_info", "user",
            "v2"
        )

        /** Loopback port Caddy proxies to */
        const val WEB_UI_PORT = 8083
        const val CONTAINER_NAME = "forgejo"

        val WRAPPER_TARGET = ServiceID.FORGEJO.rawValue

        const val IMAGE = "codeberg.org/forgejo/forgejo:15.0"

        const val DATABASE_IMAGE = "postgres:16-alpine"
    }
}
