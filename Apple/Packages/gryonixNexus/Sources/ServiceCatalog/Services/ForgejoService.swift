public struct ForgejoService: ManagedService {
    public static let composeProject = "forgejo"
    /// Loopback port Caddy proxies to
    public static let webUIPort = 8083
    public static let containerName = "forgejo"
    public static let wrapperTarget = ServiceID.forgejo.rawValue
    public static let image = "codeberg.org/forgejo/forgejo:15.0"
    public static let databaseImage = "postgres:16-alpine"

    public let id = ServiceID.forgejo
    public let displayName = "Forgejo"
    public let systemImage = "arrow.triangle.branch"
    public let category = ServiceCategory.code
    public let usesSharedAdminLogin = true
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 512, diskGB: 3)

    public init() {}

    /// Full web UI hostname
    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.forgejoHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.forgejo, context) : custom
    }

    static let reservedUsernames: Set<String> = [
        "admin", "api", "assets", "attachments", "avatar", "avatars", "captcha",
        "commits", "debug", "devtest", "error", "explore", "ghost", "issues",
        "login", "metrics", "milestones", "new", "notifications", "org",
        "pulls", "raw", "repo", "repo-avatars", "search", "ssh_info", "user",
        "v2"
    ]

    public func adminUsername(_ context: ServiceContext) -> String {
        let shared = context.settings.adminUsername
        return Self.reservedUsernames.contains(shared.lowercased())
            ? "\(shared)-gryonix" : shared
    }

    public func sshPort(_ context: ServiceContext) -> Int? {
        let port = context.settings.forgejoSSHPort
        return port > 0 ? port : nil
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.forgejoPath
        let host = hostname(context)
        let ssh = sshPort(context)
        let sshSettings = ssh.map { port in
            """

                  # The image runs its OWN OpenSSH on 22 (an s6 service), and
                  # Forgejo's built-in server cannot have that port: it exits
                  # with "address already in use" and systemd-restarts forever. The
                  # container's sshd is the path upstream's own compose takes —
                  # Forgejo writes the authorized_keys it serves.
                  FORGEJO__server__START_SSH_SERVER: "false"
                  FORGEJO__server__SSH_DOMAIN: \(host)
                  FORGEJO__server__SSH_LISTEN_PORT: "22"
                  FORGEJO__server__SSH_PORT: "\(port)"
            """
        } ?? """

              FORGEJO__server__START_SSH_SERVER: "false"
        """
        let sshPublish = ssh.map { "\n      - \"\($0):22\"" } ?? ""
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              db:
                image: \(Self.databaseImage)
                restart: unless-stopped
                environment:
                  POSTGRES_USER: forgejo
                  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
                  POSTGRES_DB: forgejo
                volumes:
                  - \(path)/db:/var/lib/postgresql/data
              server:
                image: \(Self.image)
                container_name: \(Self.containerName)
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
                  FORGEJO__database__PASSWD: ${POSTGRES_PASSWORD}
                  FORGEJO__server__DOMAIN: \(host)
                  FORGEJO__server__ROOT_URL: https://\(host)/
                  FORGEJO__server__HTTP_PORT: "3000"\(sshSettings)
                  # No web installer: the setup script has already provided the
                  # database and the administrator, and an unlocked instance
                  # hands its own configuration to whoever opens the page first.
                  FORGEJO__security__INSTALL_LOCK: "true"
                  # Closed by default — this is a personal forge on a public
                  # URL. Further users are invited from Site Administration.
                  FORGEJO__service__DISABLE_REGISTRATION: "true"
                volumes:
                  - \(path)/data:/var/lib/gitea
                  - /etc/localtime:/etc/localtime:ro
                ports:
                  - "127.0.0.1:\(Self.webUIPort):3000"\(sshPublish)
            """,
            envTemplate: """
            POSTGRES_PASSWORD=__RANDOM__
            FORGEJO_ADMIN_PASSWORD=__RANDOM__
            """
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.forgejoPath
        let lang = context.language
        let admin = adminUsername(context)
        return [
            #"""
            log "Forgejo: \#(L10nServices.serviceStarting(lang))"
            install -d -m 755 \#(path)
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#,
            #"""
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
            fj_exec() { FJ_OUT="$(timeout 120 docker exec -u git \#(Self.containerName) "$@" 2>&1)"; }
            # Why the last call failed, bounded to one line: Forgejo answers
            # with multi-line Go logs, and the app streams this log live.
            fj_why() { printf '%s' "$FJ_OUT" | tr -d '\r\n' | cut -c1-300; }
            # A deadline, not a number of tries: each attempt can burn its own
            # timeout, so counting attempts makes the real wait unbounded.
            # `user list` doubles as the readiness probe: unlike `--version` it
            # has to reach the database, which is the thing that is actually
            # not ready yet while the containers already report up.
            FJ_READY=0
            FJ_TRY=0
            FJ_DEADLINE=$(($(date +%s) + 300))
            while [ "$(date +%s)" -lt "$FJ_DEADLINE" ]; do
              if fj_exec forgejo admin user list; then FJ_READY=1; break; fi
              # Heartbeat every ~30 s: a silent wait is indistinguishable from
              # a hung install in the app's progress view.
              FJ_TRY=$((FJ_TRY + 1))
              if [ "$((FJ_TRY % 6))" -eq 0 ]; then
                log "\#(L10nServices.forgejoWaiting(lang)) ($(fj_why))"
              fi
              sleep 5
            done
            if [ "$FJ_READY" -eq 1 ]; then
              # The probe's own output IS the user list — fj_exec captures
              # stdout into FJ_OUT, so piping the function would read nothing.
              # Anchored to the Username COLUMN (id, then the name): a bare
              # word match also hits the Email column, so any unrelated account
              # at \#(admin)@... would look like the administrator already
              # existing and this step would silently skip creating it — a
              # forge nobody can log into, with one line in the log to say so.
              # `|| true`: under pipefail a grep that matches nothing would
              # fail the assignment and errexit would take the whole install.
              FJ_HAS_ADMIN="$(printf '%s' "$FJ_OUT" | grep -cE '^[0-9]+[[:space:]]+\#(admin)[[:space:]]' || true)"
              FJ_ADMIN_PASSWORD="$(grep '^FORGEJO_ADMIN_PASSWORD=' \#(path)/.env | cut -d= -f2- || true)"
              if [ "$FJ_HAS_ADMIN" -eq 0 ] && [ -n "$FJ_ADMIN_PASSWORD" ]; then
                # The password is NOT reset on a re-run: the .env value is
                # stable, so the report keeps matching, and one the user has
                # changed in the web UI is left alone.
                fj_exec forgejo admin user create --admin --username \#(admin) \
                  --password "$FJ_ADMIN_PASSWORD" --email \#(admin)@\#(context.domain) \
                  --must-change-password=false \
                  || log "\#(L10nServices.forgejoAdminCreateFailed(lang)) ($(fj_why))"
              fi
            else
              log "\#(L10nServices.forgejoUnavailable(lang)) ($(fj_why))"
            fi
            """#
        ]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] {
        guard let port = sshPort(context) else { return [] }
        return [FirewallPort(port, .tcp, comment: "git SSH")]
    }

    public func webIngress(_ context: ServiceContext) -> WebIngress? {
        WebIngress(hostname: hostname(context), upstreamPort: Self.webUIPort)
    }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.forgejoPath
        let lang = context.language
        let host = hostname(context)
        var lines = [
            #"echo "Forgejo:      https://\#(host)""#,
            #"echo "  \#(L10nServices.administratorLabel(lang)): \#(adminUsername(context))""#,
            #"""
            echo "  \#(L10nServices.passwordGeneratedOnServerLabel(lang)): $(grep '^FORGEJO_ADMIN_PASSWORD=' \#(path)/.env | cut -d= -f2-)"
            """#,
            #"echo "  \#(L10nServices.forgejoRegistrationClosedNote(lang))""#
        ]
        if let port = sshPort(context) {
            lines.append(#"echo "  \#(L10nServices.forgejoSSHNote(lang, host: host, port: port))""#)
        } else {
            lines.append(#"echo "  \#(L10nServices.forgejoSSHDisabledNote(lang))""#)
        }
        return [lines.joined(separator: "\n")]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.forgejoPath
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
                    dataPath: "\(path)/data",
                    databases: [BackupDatabase(engine: .postgres, service: "db",
                                               fileName: "forgejo.sql")],
                    quiesceServices: ["server"],
                    encryptsByDefault: false,
                    sizePaths: ["\(path)/data", "\(path)/db"]
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
            configDirectory: context.settings.forgejoPath,
            dataPaths: ["\(context.settings.forgejoPath)/data.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}
