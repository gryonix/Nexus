public struct PassboltService: ManagedService {
    public static let composeProject = "passbolt"
    public static let container = "passbolt"
    /// Loopback port Caddy proxies to
    public static let webUIPort = 8090
    public static let wrapperTarget = ServiceID.passbolt.rawValue
    public static let image = "passbolt/passbolt:5.14.3-1-ce"
    public static let databaseImage = "mariadb:10.11"

    public let id = ServiceID.passbolt
    public let displayName = "Passbolt"
    public let systemImage = "key.viewfinder"
    public let category = ServiceCategory.passwords
    public let usesSharedAdminLogin = false
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    /// The PHP app plus MariaDB; both idle modestly
    public let resources = ServiceResources(memoryMB: 512, diskGB: 2)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.passboltHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.passbolt, context) : custom
    }

    /// Email the admin invitation goes to
    public func adminLogin(_ context: ServiceContext) -> String {
        "\(context.settings.adminUsername)@\(context.domain)"
    }

    private func secretsPath(_ context: ServiceContext) -> String {
        "\(context.settings.passboltPath)/secrets"
    }

    private func gpgPrivateKeyPath(_ context: ServiceContext) -> String {
        "\(secretsPath(context))/gpg/serverkey_private.asc"
    }

    private func registrationURLPath(_ context: ServiceContext) -> String {
        "\(context.settings.passboltPath)/.registration-url"
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.passboltPath
        let secrets = secretsPath(context)
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              db:
                image: \(Self.databaseImage)
                restart: unless-stopped
                environment:
                  # Explicit, NOT upstream's own MYSQL_RANDOM_ROOT_PASSWORD:
                  # the shared backup wrapper always dumps as root, reading
                  # MYSQL_ROOT_PASSWORD out of the container's OWN
                  # environment — a randomized-and-discarded root password
                  # would make this service's own backups impossible.
                  MYSQL_ROOT_PASSWORD: ${PASSBOLT_DB_ROOT_PASSWORD}
                  MYSQL_DATABASE: passbolt
                  MYSQL_USER: passbolt
                  MYSQL_PASSWORD: ${PASSBOLT_DB_PASSWORD}
                volumes:
                  - \(path)/db:/var/lib/mysql
              passbolt:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                depends_on:
                  - db
                environment:
                  APP_FULL_BASE_URL: https://\(hostname(context))
                  DATASOURCES_DEFAULT_HOST: db
                  DATASOURCES_DEFAULT_USERNAME: passbolt
                  DATASOURCES_DEFAULT_PASSWORD: ${PASSBOLT_DB_PASSWORD}
                  DATASOURCES_DEFAULT_DATABASE: passbolt
                volumes:
                  - \(secrets)/gpg:/etc/passbolt/gpg
                  - \(secrets)/jwt:/etc/passbolt/jwt
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
                  - "127.0.0.1:\(Self.webUIPort):80"
            """,
            envTemplate: """
            PASSBOLT_DB_ROOT_PASSWORD=__RANDOM__
            PASSBOLT_DB_PASSWORD=__RANDOM__
            """
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.passboltPath
        let secrets = secretsPath(context)
        let gpgKey = gpgPrivateKeyPath(context)
        let urlFile = registrationURLPath(context)
        let admin = adminLogin(context)
        let lang = context.language
        return [
            #"""
            log "Passbolt: \#(L10nServices.serviceStarting(lang))"
            install -d -m 755 \#(path)/db
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
            # \#(path), so the keys have to sit on a real host path.
            # The group is the NUMBER 33, not the name: it has to match the uid
            # map inside the container, and nothing guarantees the host even has
            # a www-data group, let alone at the same id.
            install -d -m 770 -o root -g 33 \#(secrets)/gpg
            install -d -m 750 -o root -g 33 \#(secrets)/jwt
            # Whether the server's GPG key already exists is ALSO whether an
            # earlier run already sent the one-time admin invitation — the
            # entrypoint generates that key exactly once, on its very first
            # start, and this service piggybacks on that same signal so a
            # repair/reinstall over the same volumes never re-invites (the
            # first invitation may already be used, and inviting a duplicate
            # "admin" the CLI would refuse anyway).
            PB_FRESH=0
            [ -f \#(gpgKey) ] || PB_FRESH=1
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#,
            #"""
            # Nothing below is fatal and no output is discarded: the same rule
            # the mailcow API, Nextcloud occ, Forgejo and Seafile provisioning
            # blocks follow. This sits in the middle of a `set -euo pipefail`
            # script whose remaining steps include revoking the install key.
            PB_OUT=""
            pb_exec() { PB_OUT="$(timeout 60 docker exec \#(Self.container) "$@" 2>&1)"; }
            pb_why() { printf '%s' "$PB_OUT" | tr -d '\r\n' | cut -c1-300; }
            if [ "$PB_FRESH" -eq 1 ]; then
              # A deadline, not a number of tries: each probe can burn its own
              # timeout. The GPG key file appearing is the readiness signal —
              # the image writes it only after the batch key generation the
              # entrypoint runs before installing the schema, so it is not
              # ready a moment before that either.
              PB_READY=0
              PB_TRY=0
              PB_DEADLINE=$(($(date +%s) + 300))
              while [ "$(date +%s)" -lt "$PB_DEADLINE" ]; do
                if [ -f \#(gpgKey) ]; then PB_READY=1; break; fi
                PB_TRY=$((PB_TRY + 1))
                if [ "$((PB_TRY % 6))" -eq 0 ]; then
                  log "\#(L10nServices.passboltWaiting(lang))"
                fi
                sleep 5
              done
              rm -f \#(urlFile)
              if [ "$PB_READY" -eq 1 ]; then
                # register_user creates a PENDING account and prints a
                # single-use setup URL — it does not and cannot set a
                # password: Passbolt's admin completes their own keypair in a
                # browser. First/last name are cosmetic profile fields, not
                # login material, and are editable after that first sign-in.
                if pb_exec su -m -c "/usr/share/php/passbolt/bin/cake passbolt register_user -u '\#(admin)' -f 'Admin' -l 'Admin' -r admin" -s /bin/sh www-data; then
                  PB_URL="$(printf '%s' "$PB_OUT" | grep -oE 'https?://[^[:space:]]+' | tail -n1)"
                  if [ -n "$PB_URL" ]; then
                    printf '%s\n' "$PB_URL" > \#(urlFile)
                    chmod 600 \#(urlFile)
                  else
                    log "\#(L10nServices.passboltRegisterNoURL(lang)) ($(pb_why))"
                  fi
                else
                  log "\#(L10nServices.passboltRegisterFailed(lang)) ($(pb_why))"
                fi
              else
                log "\#(L10nServices.passboltUnavailable(lang)) ($(pb_why))"
              fi
            fi
            """#
        ]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { [] }

    public func webIngress(_ context: ServiceContext) -> WebIngress? {
        WebIngress(hostname: hostname(context), upstreamPort: Self.webUIPort)
    }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let lang = context.language
        let urlFile = registrationURLPath(context)
        return [#"""
        echo "Passbolt:     https://\#(hostname(context))"
        if [ -s \#(urlFile) ]; then
          echo "  \#(L10nServices.passboltSetupURLLabel(lang))"
          echo "  $(cat \#(urlFile))"
        else
          echo "  \#(L10nServices.passboltAlreadyConfiguredNote(lang))"
        fi
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.passboltPath
        let secrets = secretsPath(context)
        return ServiceActions(
            statusProbe: .composeProject(
                project: Self.composeProject,
                list: PrivilegedCommand(binaryPath: "/usr/bin/docker",
                                        arguments: "compose -p \(Self.composeProject) ps")
            ),
            restart: ServicePower.compose(project: Self.composeProject, "restart", timeoutClass: .restart),
            start: ServicePower.compose(project: Self.composeProject, "start", timeoutClass: .restart),
            stop: ServicePower.compose(project: Self.composeProject, "stop", timeoutClass: .restart),
            backup: .wrapperScript(BackupWrapperSpec(
                wrapperTarget: Self.wrapperTarget,
                backupDir: context.backupDirectory(for: id),
                run: ServiceCommand(
                    PrivilegedCommand(binaryPath: BackupWrapperSpec.wrapperPath, arguments: ""),
                    timeoutClass: .long,
                    streamsOutput: true
                ),
                plan: .archive(ArchiveBackupPlan(
                    composeProject: Self.composeProject,
                    dataPath: secrets,
                    databases: [BackupDatabase(engine: .mysql, service: "db",
                                               fileName: "passbolt.sql")],
                    quiesceServices: [],
                    encryptsByDefault: true,
                    sizePaths: [secrets, "\(path)/db"]
                ))
            )),
            restore: RestoreSpec(
                wrapperTarget: Self.wrapperTarget,
                backupDir: context.backupDirectory(for: id),
                needsPassphrase: false,
                privileged: PrivilegedCommand(binaryPath: RestoreSpec.wrapperPath, arguments: "")
            )
        )
    }

    public func updateSpec(_ context: ServiceContext) -> UpdateSpec {
        UpdateSpec(images: [Self.image, Self.databaseImage])
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            configDirectory: context.settings.passboltPath,
            dataPaths: ["\(secretsPath(context)).pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}
