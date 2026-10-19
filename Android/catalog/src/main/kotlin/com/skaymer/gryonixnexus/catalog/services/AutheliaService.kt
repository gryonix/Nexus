package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.ArchiveBackupPlan
import com.skaymer.gryonixnexus.catalog.AutheliaDefaults
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
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.ServiceResources
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress
import com.skaymer.gryonixnexus.catalog.embedding

class AutheliaService : ManagedService {
    override val id = ServiceID.AUTHELIA
    override val displayName = "Authelia"
    override val systemImage = "person.badge.key"
    override val category = ServiceCategory.SINGLE_SIGN_ON

    override val usesSharedAdminLogin = true
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    /** One Go binary with a SQLite file behind it */
    override val resources = ServiceResources(memoryMB = 256, diskGB = 1)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.autheliaHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.AUTHELIA, context)
        } else {
            custom
        }
    }

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.autheliaPath
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              authelia:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                environment:
                  # The 4.39 names. Every one of them can also be given in the
                  # file; they are here so the file itself carries no secret
                  # and can be read by whoever debugs a login failure.
                  AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET: ${SH}{AUTHELIA_JWT_SECRET}
                  AUTHELIA_SESSION_SECRET: ${SH}{AUTHELIA_SESSION_SECRET}
                  AUTHELIA_STORAGE_ENCRYPTION_KEY: ${SH}{AUTHELIA_STORAGE_ENCRYPTION_KEY}
                volumes:
                  - $path/config:/config
                ports:
                  - "127.0.0.1:$WEB_UI_PORT:$CONTAINER_WEB_PORT"
            """.trimIndent(),
            envTemplate = """
            AUTHELIA_JWT_SECRET=__RANDOM__
            AUTHELIA_SESSION_SECRET=__RANDOM__
            AUTHELIA_STORAGE_ENCRYPTION_KEY=__RANDOM__
            """.trimIndent()
        )
    }

    /** The whole configuration file */
    fun configurationYAML(context: ServiceContext): String {
        val portal = hostname(context)
        val protectedNames = protectedHostnames(context)
        val defaultPolicy = if (protectedNames.isEmpty()) "two_factor" else "deny"
        val rules = if (protectedNames.isEmpty()) {
            "  rules: []"
        } else {
            "  rules:\n" + protectedNames.joinToString("\n") {
                "    - domain: '$it'\n      policy: one_factor"
            }
        }
        return """
        ---
        theme: light
        server:
          address: 'tcp://0.0.0.0:$CONTAINER_WEB_PORT'
        log:
          level: info
        authentication_backend:
          file:
            path: /config/users_database.yml
        access_control:
          # Anything not named below is not reachable through the portal. A
          # permissive default here would put every future site behind SSO the
          # day it is created, including the ones whose mobile apps cannot use
          # it.
          default_policy: $defaultPolicy
        @RULES@
        session:
          cookies:
        @COOKIES@
        storage:
          local:
            path: /config/db.sqlite3
        notifier:
          # A file, not mail: password reset is the only thing this notifies
          # about, and a mail server is not something this deployment is
          # guaranteed to have. The file is inside the config volume and
          # readable only by root.
          filesystem:
            filename: /config/notification.txt
        """.trimIndent().embedding("RULES" to rules, "COOKIES" to sessionCookies(context, portal))
    }

    /** One sign-in cookie per domain, with its own portal */
    private fun sessionCookies(context: ServiceContext, portal: String): String {
        val domains = listOf(context.domain) + context.additionalDomains
        return domains.zip(context.servedHostnames(portal)).joinToString("\n") { (domain, url) ->
            "    - name: authelia_session\n      domain: '$domain'\n      authelia_url: 'https://$url'"
        }
    }

    fun protectedHostnames(context: ServiceContext): List<String> =
        ServiceRegistry.services(context.settings.autheliaProtectedServices)
            .filter { it.id in context.installedServices }
            .filter { guards(it.id, context.settings) }
            .mapNotNull { it.webIngress(context)?.hostname }
            .flatMap { context.servedHostnames(it) }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.autheliaPath
        val lang = context.language
        val admin = context.settings.adminUsername
        return listOf(
            """
            log "Authelia: ${L10nServices.serviceStarting(lang)}"
            install -d -m 755 $path
            # The config volume holds the session database, the notification
            # file and the user database with its password hashes.
            install -d -m 700 $path/config
            cd $path
            backup $path/config/configuration.yml
            cat > $path/config/configuration.yml <<'EOF_AUTHELIA_CONFIG'
            @CONFIG@
            EOF_AUTHELIA_CONFIG
            """.trimIndent().embedding("CONFIG" to configurationYAML(context)),
            """
        # The first account, created ONCE. A rerun must not rotate the
        # password of an administrator who already wrote it down, and must
        # not overwrite a user database somebody has since added people to.
        #
        # The second test is a REPAIR, and it is safe for exactly that
        # reason: a file with no `${SH}`-prefixed hash in it is one Authelia
        # refuses to load at all, so nobody has ever signed in through it
        # and nobody can have added a person to it.
        AUTH_USERS="$path/config/users_database.yml"
        if [ ! -f "${SH}AUTH_USERS" ] || ! grep -qF "password: '\${SH}" "${SH}AUTH_USERS"; then
          # PULL FIRST. `docker run` on an image this host does not have
          # yet prints its own `Digest: sha256:…` line while fetching it,
          # and with 2>&1 that line lands in AUTH_OUT ahead of the real
          # one — which is how a fresh install wrote a users database whose
          # password was a docker digest, leaving the portal in a restart
          # loop. It also keeps the image
          # download out of the 60s budget below, which is meant for the
          # hashing, not for a 100 MB pull.
          docker pull -q $IMAGE >/dev/null 2>&1 || true
          # The image makes the password AND its hash and prints both, so
          # nothing secret is ever an argument — `/proc` hands argv to
          # every account on this machine. Captured into a variable rather
          # than redirected into a file: `docker run … > file` creates the
          # file BEFORE the command runs, so a failure would leave an empty
          # user database that the guard above then treats as done.
          AUTH_OUT="${SH}(timeout 60 docker run --rm $IMAGE \
            authelia crypto hash generate argon2 --random 2>&1 || true)"
          AUTH_PASSWORD="${SH}(printf '%s\n' "${SH}AUTH_OUT" | sed -n 's/^Random Password: //p' | tail -n1)"
          # Anchored on the leading `${SH}` every crypt digest carries: that is
          # what tells the hash apart from anything else that prints a
          # `Digest:` line, and an unanchored read is what broke above.
          AUTH_DIGEST="${SH}(printf '%s\n' "${SH}AUTH_OUT" | sed -n 's/^Digest: \([${SH}].*\)${SH}/\1/p' | tail -n1)"
          if [ -n "${SH}AUTH_PASSWORD" ] && [ -n "${SH}AUTH_DIGEST" ]; then
            umask 077
            cat > "${SH}AUTH_USERS" <<EOF_AUTHELIA_USERS
        ---
        users:
          $admin:
            disabled: false
            displayname: '$admin'
            password: '${SH}AUTH_DIGEST'
            email: '$admin@${context.domain}'
            groups:
              - admins
        EOF_AUTHELIA_USERS
            # Dropped first: on the repair path the .env already carries the
            # password of the account that never worked, and two lines
            # would leave the install report quoting whichever one it read
            # first.
            sed -i '/^AUTHELIA_ADMIN_PASSWORD=/d' $path/.env 2>/dev/null || true
            printf 'AUTHELIA_ADMIN_PASSWORD=%s\n' "${SH}AUTH_PASSWORD" >> $path/.env
            umask 022
          else
            log "${L10nServices.autheliaHashFailed(lang)}"
          fi
        fi
        docker compose -p $COMPOSE_PROJECT pull -q
        docker compose -p $COMPOSE_PROJECT up -d
            """.trimIndent()
        )
    }

    /** Nothing */
    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) = WebIngress(
        hostname = hostname(context),
        upstreamPort = WEB_UI_PORT,
        adminGuard = false
    )

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val path = context.settings.autheliaPath
        val lang = context.language
        val names = protectedHostnames(context)
        val protects = if (names.isEmpty()) "—" else names.joinToString(", ")
        return listOf("""
        echo "Authelia: https://${hostname(context)}"
        echo "  ${L10nServices.administratorLabel(lang)}: ${context.settings.adminUsername}"
        echo "  ${L10nServices.passwordGeneratedOnServerLabel(lang)}: ${SH}(grep '^AUTHELIA_ADMIN_PASSWORD=' $path/.env | cut -d= -f2-)"
        echo "  ${L10nServices.autheliaProtectsNote(lang)}: $protects"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.autheliaPath
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
                    dataPath = "$path/config",
                    databases = emptyList(),
                    quiesceServices = listOf(COMPOSE_PROJECT),
                    encryptsByDefault = true,
                    sizePaths = listOf("$path/config")
                ))
            )),
            restore = RestoreSpec(
                wrapperTarget = WRAPPER_TARGET,
                backupDir = context.backupDirectory(id),
                needsPassphrase = true,
                privileged = PrivilegedCommand(RestoreSpec.WRAPPER_PATH, "")
            )
        )
    }

    override fun updateSpec(context: ServiceContext) = UpdateSpec(images = listOf(IMAGE))

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        configDirectory = context.settings.autheliaPath,
        dataPaths = listOf("${context.settings.autheliaPath}/config.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "authelia"
        const val CONTAINER = "authelia"

        const val WEB_UI_PORT = 8094

        const val CONTAINER_WEB_PORT = 9091
        val WRAPPER_TARGET = ServiceID.AUTHELIA.rawValue

        /** Exact pinned tag */
        const val IMAGE = "ghcr.io/authelia/authelia:4.39.20"

        val DEFAULT_PROTECTED: Set<ServiceID> = AutheliaDefaults.PROTECTED

        val NEVER_PROTECTED: Set<ServiceID> = setOf(ServiceID.HEADSCALE)

        /** The services whose FIRST-PARTY APPS a forward-auth gate breaks */
        val BREAKS_APP_CLIENTS: Set<ServiceID> = setOf(
            ServiceID.NEXTCLOUD, ServiceID.SEAFILE, ServiceID.IMMICH,
            ServiceID.PHOTOPRISM, ServiceID.VAULTWARDEN, ServiceID.PSONO,
            ServiceID.PASSBOLT, ServiceID.JELLYFIN, ServiceID.MAILCOW,
            ServiceID.MAILU, ServiceID.DOCKER_MAILSERVER
        )

        /** The Caddy directive a protected site imports */
        fun forwardAuthBlock(hostname: String): String = """
        forward_auth 127.0.0.1:$WEB_UI_PORT {
                uri /api/authz/forward-auth
                copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
            }
        """.trimIndent()

        fun guards(id: ServiceID, settings: ServiceSettings): Boolean =
            id in settings.autheliaProtectedServices && id !in NEVER_PROTECTED
    }
}
