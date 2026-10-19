public struct AutheliaService: ManagedService {
    public static let composeProject = "authelia"
    public static let container = "authelia"
    public static let webUIPort = 8094
    public static let containerWebPort = 9091
    public static let wrapperTarget = ServiceID.authelia.rawValue
    /// Exact pinned tag
    public static let image = "ghcr.io/authelia/authelia:4.39.20"

    public static let defaultProtected: Set<ServiceID> = [
        .adguardHome, .pihole, .homepage, .craftyController
    ]

    public static let neverProtected: Set<ServiceID> = [.headscale]

    /// The services whose FIRST-PARTY APPS a forward-auth gate breaks
    public static let breaksAppClients: Set<ServiceID> = [
        .nextcloud, .seafile, .immich, .photoprism, .vaultwarden, .psono, .passbolt,
        .jellyfin, .mailcow, .mailu, .dockerMailserver
    ]

    public let id = ServiceID.authelia
    public let displayName = "Authelia"
    public let systemImage = "person.badge.key"
    public let category = ServiceCategory.singleSignOn
    public let usesSharedAdminLogin = true
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    /// One Go binary with a SQLite file behind it
    public let resources = ServiceResources(memoryMB: 256, diskGB: 1)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.autheliaHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.authelia, context) : custom
    }

    /// The Caddy directive a protected site imports
    public static func forwardAuthBlock(hostname: String) -> String {
        """
        forward_auth 127.0.0.1:\(webUIPort) {
                uri /api/authz/forward-auth
                copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
            }
        """
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.autheliaPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              authelia:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                environment:
                  # The 4.39 names. Every one of them can also be given in the
                  # file; they are here so the file itself carries no secret
                  # and can be read by whoever debugs a login failure.
                  AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET: ${AUTHELIA_JWT_SECRET}
                  AUTHELIA_SESSION_SECRET: ${AUTHELIA_SESSION_SECRET}
                  AUTHELIA_STORAGE_ENCRYPTION_KEY: ${AUTHELIA_STORAGE_ENCRYPTION_KEY}
                volumes:
                  - \(path)/config:/config
                ports:
                  - "127.0.0.1:\(Self.webUIPort):\(Self.containerWebPort)"
            """,
            envTemplate: """
            AUTHELIA_JWT_SECRET=__RANDOM__
            AUTHELIA_SESSION_SECRET=__RANDOM__
            AUTHELIA_STORAGE_ENCRYPTION_KEY=__RANDOM__
            """
        )
    }

    /// The whole configuration file
    public func configurationYAML(_ context: ServiceContext) -> String {
        let portal = hostname(context)
        let protectedNames = protectedHostnames(context)
        let defaultPolicy = protectedNames.isEmpty ? "two_factor" : "deny"
        let rules = protectedNames.isEmpty
            ? "  rules: []"
            : "  rules:\n" + protectedNames.map {
                "    - domain: '\($0)'\n      policy: one_factor"
            }.joined(separator: "\n")
        return """
        ---
        theme: light
        server:
          address: 'tcp://0.0.0.0:\(Self.containerWebPort)'
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
          default_policy: \(defaultPolicy)
        \(rules)
        session:
          cookies:
        \(Self.sessionCookies(context, portal: portal))
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
        """
    }

    /// One sign-in cookie per domain, with its own portal
    static func sessionCookies(_ context: ServiceContext, portal: String) -> String {
        let domains = [context.domain] + context.additionalDomains
        let portals = context.servedHostnames(of: portal)
        return zip(domains, portals).map { domain, url in
            "    - name: authelia_session\n      domain: '\(domain)'\n      authelia_url: 'https://\(url)'"
        }.joined(separator: "\n")
    }

    public static func guards(_ id: ServiceID, settings: ServiceSettings) -> Bool {
        settings.autheliaProtectedServices.contains(id) && !neverProtected.contains(id)
    }

    public func protectedHostnames(_ context: ServiceContext) -> [String] {
        ServiceRegistry.services(context.settings.autheliaProtectedServices)
            .filter { context.installedServices.contains($0.id) }
            .filter { Self.guards($0.id, settings: context.settings) }
            .compactMap { $0.webIngress(context)?.hostname }
            .flatMap { context.servedHostnames(of: $0) }
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.autheliaPath
        let lang = context.language
        let admin = context.settings.adminUsername
        return [
            #"""
            log "Authelia: \#(L10nServices.serviceStarting(lang))"
            install -d -m 755 \#(path)
            # The config volume holds the session database, the notification
            # file and the user database with its password hashes.
            install -d -m 700 \#(path)/config
            cd \#(path)
            backup \#(path)/config/configuration.yml
            cat > \#(path)/config/configuration.yml <<'EOF_AUTHELIA_CONFIG'
            \#(configurationYAML(context))
            EOF_AUTHELIA_CONFIG
            """#,
            #"""
            # The first account, created ONCE. A rerun must not rotate the
            # password of an administrator who already wrote it down, and must
            # not overwrite a user database somebody has since added people to.
            #
            # The second test is a REPAIR, and it is safe for exactly that
            # reason: a file with no `$`-prefixed hash in it is one Authelia
            # refuses to load at all, so nobody has ever signed in through it
            # and nobody can have added a person to it.
            AUTH_USERS="\#(path)/config/users_database.yml"
            if [ ! -f "$AUTH_USERS" ] || ! grep -qF "password: '\$" "$AUTH_USERS"; then
              # PULL FIRST. `docker run` on an image this host does not have
              # yet prints its own `Digest: sha256:…` line while fetching it,
              # and with 2>&1 that line lands in AUTH_OUT ahead of the real
              # one — which is how a fresh install wrote a users database whose
              # password was a docker digest, leaving the portal in a restart
              # loop. It also keeps the image
              # download out of the 60s budget below, which is meant for the
              # hashing, not for a 100 MB pull.
              docker pull -q \#(Self.image) >/dev/null 2>&1 || true
              # The image makes the password AND its hash and prints both, so
              # nothing secret is ever an argument — `/proc` hands argv to
              # every account on this machine. Captured into a variable rather
              # than redirected into a file: `docker run … > file` creates the
              # file BEFORE the command runs, so a failure would leave an empty
              # user database that the guard above then treats as done.
              AUTH_OUT="$(timeout 60 docker run --rm \#(Self.image) \
                authelia crypto hash generate argon2 --random 2>&1 || true)"
              AUTH_PASSWORD="$(printf '%s\n' "$AUTH_OUT" | sed -n 's/^Random Password: //p' | tail -n1)"
              # Anchored on the leading `$` every crypt digest carries: that is
              # what tells the hash apart from anything else that prints a
              # `Digest:` line, and an unanchored read is what broke above.
              AUTH_DIGEST="$(printf '%s\n' "$AUTH_OUT" | sed -n 's/^Digest: \([$].*\)$/\1/p' | tail -n1)"
              if [ -n "$AUTH_PASSWORD" ] && [ -n "$AUTH_DIGEST" ]; then
                umask 077
                cat > "$AUTH_USERS" <<EOF_AUTHELIA_USERS
            ---
            users:
              \#(admin):
                disabled: false
                displayname: '\#(admin)'
                password: '$AUTH_DIGEST'
                email: '\#(admin)@\#(context.domain)'
                groups:
                  - admins
            EOF_AUTHELIA_USERS
                # Dropped first: on the repair path the .env already carries the
                # password of the account that never worked, and two lines
                # would leave the install report quoting whichever one it read
                # first.
                sed -i '/^AUTHELIA_ADMIN_PASSWORD=/d' \#(path)/.env 2>/dev/null || true
                printf 'AUTHELIA_ADMIN_PASSWORD=%s\n' "$AUTH_PASSWORD" >> \#(path)/.env
                umask 022
              else
                log "\#(L10nServices.autheliaHashFailed(lang))"
              fi
            fi
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#
        ]
    }

    /// Nothing
    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { [] }

    public func webIngress(_ context: ServiceContext) -> WebIngress? {
        WebIngress(hostname: hostname(context), upstreamPort: Self.webUIPort, adminGuard: false)
    }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.autheliaPath
        let lang = context.language
        let names = protectedHostnames(context)
        return [#"""
        echo "Authelia: https://\#(hostname(context))"
        echo "  \#(L10nServices.administratorLabel(lang)): \#(context.settings.adminUsername)"
        echo "  \#(L10nServices.passwordGeneratedOnServerLabel(lang)): $(grep '^AUTHELIA_ADMIN_PASSWORD=' \#(path)/.env | cut -d= -f2-)"
        echo "  \#(L10nServices.autheliaProtectsNote(lang)): \#(names.isEmpty ? "—" : names.joined(separator: ", "))"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.autheliaPath
        return ServiceActions(
            statusProbe: .container(
                name: Self.container,
                list: PrivilegedCommand(binaryPath: "/usr/bin/docker", arguments: "ps -a")
            ),
            restart: ServicePower.container(Self.container, "restart", timeoutClass: .restart),
            start: ServicePower.container(Self.container, "start", timeoutClass: .restart),
            stop: ServicePower.container(Self.container, "stop", timeoutClass: .restart),
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
                    dataPath: "\(path)/config",
                    databases: [],
                    quiesceServices: [Self.composeProject],
                    encryptsByDefault: true,
                    sizePaths: ["\(path)/config"]
                ))
            )),
            restore: RestoreSpec(
                wrapperTarget: Self.wrapperTarget,
                backupDir: context.backupDirectory(for: id),
                needsPassphrase: true,
                privileged: PrivilegedCommand(binaryPath: RestoreSpec.wrapperPath, arguments: "")
            )
        )
    }

    public func updateSpec(_ context: ServiceContext) -> UpdateSpec {
        UpdateSpec(images: [Self.image])
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            configDirectory: context.settings.autheliaPath,
            dataPaths: ["\(context.settings.autheliaPath)/config.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}
