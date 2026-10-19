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

class PassboltService : ManagedService {
    override val id = ServiceID.PASSBOLT
    override val displayName = "Passbolt"
    override val systemImage = "key.viewfinder"
    override val category = ServiceCategory.PASSWORDS

    override val usesSharedAdminLogin = false
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    /** The PHP app plus MariaDB; both idle modestly */
    override val resources = ServiceResources(memoryMB = 512, diskGB = 2)

    fun hostname(context: ServiceContext): String {
        val custom = context.settings.passboltHostname
        return if (custom.isEmpty()) {
            ServiceDefaultHostnames.hostname(ServiceID.PASSBOLT, context)
        } else {
            custom
        }
    }

    /** Email the admin invitation goes to */
    fun adminLogin(context: ServiceContext): String =
        "${context.settings.adminUsername}@${context.domain}"

    private fun secretsPath(context: ServiceContext): String =
        "${context.settings.passboltPath}/secrets"

    private fun gpgPrivateKeyPath(context: ServiceContext): String =
        "${secretsPath(context)}/gpg/serverkey_private.asc"

    private fun registrationURLPath(context: ServiceContext): String =
        "${context.settings.passboltPath}/.registration-url"

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.passboltPath
        val secrets = secretsPath(context)
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              db:
                image: $DATABASE_IMAGE
                restart: unless-stopped
                environment:
                  # Explicit, NOT upstream's own MYSQL_RANDOM_ROOT_PASSWORD:
                  # the shared backup wrapper always dumps as root, reading
                  # MYSQL_ROOT_PASSWORD out of the container's OWN
                  # environment — a randomized-and-discarded root password
                  # would make this service's own backups impossible.
                  MYSQL_ROOT_PASSWORD: ${SH}{PASSBOLT_DB_ROOT_PASSWORD}
                  MYSQL_DATABASE: passbolt
                  MYSQL_USER: passbolt
                  MYSQL_PASSWORD: ${SH}{PASSBOLT_DB_PASSWORD}
                volumes:
                  - $path/db:/var/lib/mysql
              passbolt:
                image: $IMAGE
                container_name: $CONTAINER
                restart: unless-stopped
                depends_on:
                  - db
                environment:
                  APP_FULL_BASE_URL: https://${hostname(context)}
                  DATASOURCES_DEFAULT_HOST: db
                  DATASOURCES_DEFAULT_USERNAME: passbolt
                  DATASOURCES_DEFAULT_PASSWORD: ${SH}{PASSBOLT_DB_PASSWORD}
                  DATASOURCES_DEFAULT_DATABASE: passbolt
                volumes:
                  - $secrets/gpg:/etc/passbolt/gpg
                  - $secrets/jwt:/etc/passbolt/jwt
                # `depends_on` only waits for the db CONTAINER to start, not
                # for MariaDB to accept connections — this is upstream's own
                # wait, kept verbatim, ahead of the entrypoint that generates
                # the GPG keypair and installs the schema.
                command:
                  [
                    "/usr/bin/wait-for.sh",
                    "-t",
                    "0",
                    "db:3306",
                    "--",
                    "/docker-entrypoint.sh",
                  ]
                ports:
                  # Caddy terminates TLS and speaks plain HTTP to this port —
                  # the community has documented this exact shape (nginx or
                  # Caddy in front on 80, Passbolt never sees the TLS layer);
                  # unlike mailcow's nginx, nothing here redirects 80 to 443
                  # on its own. Port 443 is never published: this catalog's
                  # own self-signed listener has no certificate anyone trusts
                  # and Caddy already owns the public 443.
                  - "127.0.0.1:$WEB_UI_PORT:80"
            """.trimIndent(),
            envTemplate = """
            PASSBOLT_DB_ROOT_PASSWORD=__RANDOM__
            PASSBOLT_DB_PASSWORD=__RANDOM__
            """.trimIndent()
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.passboltPath
        val secrets = secretsPath(context)
        val gpgKey = gpgPrivateKeyPath(context)
        val urlFile = registrationURLPath(context)
        val admin = adminLogin(context)
        val lang = context.language
        return listOf(
            """
            log "Passbolt: ${L10nServices.serviceStarting(lang)}"
            install -d -m 755 $path/db
            # The two secret directories are NOT 755 root:root like every other
            # directory here, and the difference is what makes the service start
            # at all. The image ships /etc/passbolt/gpg as root:www-data 0770 and
            # /etc/passbolt/jwt as root:www-data 0750, and the server drops to
            # www-data to write the GPG keypair it generates on first boot.
            # Upstream's own compose mounts NAMED volumes there, which docker
            # seeds with the image's ownership and mode; a BIND mount is never
            # seeded, so the container sees the host directory's own root:root
            # 0755 and cannot write. The server
            # crash-looped on "/etc/passbolt/gpg/serverkey_private.asc:
            # Permission denied", restarting every few seconds forever.
            # Bind mounts are not negotiable — the backup wrapper archives
            # $path, so the keys have to sit on a real host path.
            # The group is the NUMBER 33, not the name: it has to match the uid
            # map inside the container, and nothing guarantees the host even has
            # a www-data group, let alone at the same id.
            install -d -m 770 -o root -g 33 $secrets/gpg
            install -d -m 750 -o root -g 33 $secrets/jwt
            # Whether the server's GPG key already exists is ALSO whether an
            # earlier run already sent the one-time admin invitation — the
            # entrypoint generates that key exactly once, on its very first
            # start, and this service piggybacks on that same signal so a
            # repair/reinstall over the same volumes never re-invites (the
            # first invitation may already be used, and inviting a duplicate
            # "admin" the CLI would refuse anyway).
            PB_FRESH=0
            [ -f $gpgKey ] || PB_FRESH=1
            cd $path
            docker compose -p $COMPOSE_PROJECT pull -q
            docker compose -p $COMPOSE_PROJECT up -d
            """.trimIndent(),
            """
            # Nothing below is fatal and no output is discarded: the same rule
            # the mailcow API, Nextcloud occ, Forgejo and Seafile provisioning
            # blocks follow. This sits in the middle of a `set -euo pipefail`
            # script whose remaining steps include revoking the install key.
            PB_OUT=""
            pb_exec() { PB_OUT="${SH}(timeout 60 docker exec $CONTAINER "${SH}@" 2>&1)"; }
            pb_why() { printf '%s' "${SH}PB_OUT" | tr -d '\r\n' | cut -c1-300; }
            if [ "${SH}PB_FRESH" -eq 1 ]; then
              # A deadline, not a number of tries: each probe can burn its own
              # timeout. The GPG key file appearing is the readiness signal —
              # the image writes it only after the batch key generation the
              # entrypoint runs before installing the schema, so it is not
              # ready a moment before that either.
              PB_READY=0
              PB_TRY=0
              PB_DEADLINE=${SH}((${SH}(date +%s) + 300))
              while [ "${SH}(date +%s)" -lt "${SH}PB_DEADLINE" ]; do
                if [ -f $gpgKey ]; then PB_READY=1; break; fi
                PB_TRY=${SH}((PB_TRY + 1))
                if [ "${SH}((PB_TRY % 6))" -eq 0 ]; then
                  log "${L10nServices.passboltWaiting(lang)}"
                fi
                sleep 5
              done
              rm -f $urlFile
              if [ "${SH}PB_READY" -eq 1 ]; then
                # register_user creates a PENDING account and prints a
                # single-use setup URL — it does not and cannot set a
                # password: Passbolt's admin completes their own keypair in a
                # browser. First/last name are cosmetic profile fields, not
                # login material, and are editable after that first sign-in.
                if pb_exec su -m -c "/usr/share/php/passbolt/bin/cake passbolt register_user -u '$admin' -f 'Admin' -l 'Admin' -r admin" -s /bin/sh www-data; then
                  PB_URL="${SH}(printf '%s' "${SH}PB_OUT" | grep -oE 'https?://[^[:space:]]+' | tail -n1)"
                  if [ -n "${SH}PB_URL" ]; then
                    printf '%s\n' "${SH}PB_URL" > $urlFile
                    chmod 600 $urlFile
                  else
                    log "${L10nServices.passboltRegisterNoURL(lang)} (${SH}(pb_why))"
                  fi
                else
                  log "${L10nServices.passboltRegisterFailed(lang)} (${SH}(pb_why))"
                fi
              else
                log "${L10nServices.passboltUnavailable(lang)} (${SH}(pb_why))"
              fi
            fi
            """.trimIndent()
        )
    }

    override fun firewallPorts(context: ServiceContext): List<FirewallPort> = emptyList()

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = hostname(context), upstreamPort = WEB_UI_PORT)

    override fun dnsHostnames(context: ServiceContext): List<String> = listOf(hostname(context))

    override fun reportSteps(context: ServiceContext): List<String> {
        val lang = context.language
        val urlFile = registrationURLPath(context)
        return listOf("""
        echo "Passbolt:     https://${hostname(context)}"
        if [ -s $urlFile ]; then
          echo "  ${L10nServices.passboltSetupURLLabel(lang)}"
          echo "  ${SH}(cat $urlFile)"
        else
          echo "  ${L10nServices.passboltAlreadyConfiguredNote(lang)}"
        fi
        """.trimIndent())
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.passboltPath
        val secrets = secretsPath(context)
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
                    dataPath = secrets,
                    databases = listOf(BackupDatabase(
                        engine = BackupDatabase.Engine.MYSQL,
                        service = "db",
                        fileName = "passbolt.sql"
                    )),
                    quiesceServices = emptyList(),
                    encryptsByDefault = true,
                    sizePaths = listOf(secrets, "$path/db")
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
        configDirectory = context.settings.passboltPath,
        dataPaths = listOf("${secretsPath(context)}.pre-restore-*"),
        backupDirs = listOf(context.backupDirectory(id))
    )

    companion object {
        const val COMPOSE_PROJECT = "passbolt"
        const val CONTAINER = "passbolt"

        /** Loopback port Caddy proxies to */
        const val WEB_UI_PORT = 8090
        val WRAPPER_TARGET = ServiceID.PASSBOLT.rawValue

        const val IMAGE = "passbolt/passbolt:5.14.3-1-ce"

        const val DATABASE_IMAGE = "mariadb:10.11"
    }
}
