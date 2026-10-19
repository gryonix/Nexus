public struct SeafileService: ManagedService {
    public static let composeProject = "seafile"
    public static let container = "seafile"
    /// Loopback port Caddy proxies to
    public static let webUIPort = 8088
    public static let wrapperTarget = ServiceID.seafile.rawValue
    public static let image = "seafileltd/seafile-mc:13.0.25"
    public static let databaseImage = "mariadb:10.11"
    /// Cache only
    public static let cacheImage = "redis:7-alpine"
    /// Rewrites links for apps at home
    public static let homeDoorImage = "nginx:1.29-alpine"
    /// Loopback port of the home link rewriter
    public static let homeDoorPort = 8188

    public let id = ServiceID.seafile
    public let displayName = "Seafile"
    public let systemImage = "folder.badge.person.crop"
    public let category = ServiceCategory.files
    public let usesSharedAdminLogin = true
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 1024, diskGB: 4)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.seafileHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.seafile, context) : custom
    }

    public func adminLogin(_ context: ServiceContext) -> String {
        "\(context.settings.adminUsername)@\(context.domain)"
    }

    private func dataPath(_ context: ServiceContext) -> String {
        "\(context.settings.seafilePath)/data"
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.seafilePath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              db:
                image: \(Self.databaseImage)
                restart: unless-stopped
                environment:
                  # The shared backup wrapper dumps through this variable, read
                  # out of the container's OWN environment — a password passed
                  # from the host would sit in the argv of docker exec, where
                  # /proc hands it to every account. There is deliberately no
                  # MYSQL_DATABASE: Seafile owns three, and the backup plan
                  # names each one instead.
                  MYSQL_ROOT_PASSWORD: ${SEAFILE_DB_ROOT_PASSWORD}
                  MARIADB_AUTO_UPGRADE: "1"
                volumes:
                  - \(path)/db:/var/lib/mysql
              redis:
                image: \(Self.cacheImage)
                restart: unless-stopped
                # Cache only, so persistence is off: an appendonly file here
                # would be disk traffic for data that is rebuilt on demand.
                # No password either — redis takes it as a command-line
                # argument, which puts it in the process table where the host
                # can read it, and it buys nothing over a port that is never
                # published outside this project's own network.
                command: ["redis-server", "--save", "", "--appendonly", "no"]
              seafile:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                depends_on:
                  - db
                  - redis
                environment:
                  SEAFILE_MYSQL_DB_HOST: db
                  SEAFILE_MYSQL_DB_PORT: "3306"
                  SEAFILE_MYSQL_DB_USER: seafile
                  SEAFILE_MYSQL_DB_PASSWORD: ${SEAFILE_DB_PASSWORD}
                  # Only used on the first start, to create the three schemas
                  # and the unprivileged user above.
                  INIT_SEAFILE_MYSQL_ROOT_PASSWORD: ${SEAFILE_DB_ROOT_PASSWORD}
                  SEAFILE_MYSQL_DB_CCNET_DB_NAME: ccnet_db
                  SEAFILE_MYSQL_DB_SEAFILE_DB_NAME: seafile_db
                  SEAFILE_MYSQL_DB_SEAHUB_DB_NAME: seahub_db
                  # The administrator, created on the first start. Left unset,
                  # Seafile creates me@example.com with the password `asecret`
                  # — a documented credential on a public hostname.
                  INIT_SEAFILE_ADMIN_EMAIL: \(adminLogin(context))
                  INIT_SEAFILE_ADMIN_PASSWORD: ${SEAFILE_ADMIN_PASSWORD}
                  # SERVICE_URL and FILE_SERVER_ROOT are derived from these two
                  # on every start, so they stay SINGLE-valued at the canonical
                  # name even though the Caddy site answers on the aliases too.
                  # The protocol must be https: it is what the browser speaks,
                  # and an http value here makes every download link a
                  # mixed-content block.
                  SEAFILE_SERVER_HOSTNAME: \(hostname(context))
                  SEAFILE_SERVER_PROTOCOL: https
                  SITE_ROOT: /
                  NON_ROOT: "false"
                  TIME_ZONE: Etc/UTC
                  JWT_PRIVATE_KEY: ${SEAFILE_JWT_PRIVATE_KEY}
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
                  - \(dataPath(context)):/shared
                ports:
                  # The container runs its own nginx on 80, which fronts
                  # seahub, the file server and WebDAV on one port.
                  - "127.0.0.1:\(Self.webUIPort):80"
            """ + homeDoor(context),
            envTemplate: """
            SEAFILE_DB_ROOT_PASSWORD=__RANDOM__
            SEAFILE_DB_PASSWORD=__RANDOM__
            SEAFILE_JWT_PRIVATE_KEY=__RANDOM__
            SEAFILE_ADMIN_PASSWORD=__RANDOM__
            """
        )
    }

    /// Apps at home get links on the plain address
    private func homeDoor(_ context: ServiceContext) -> String {
        guard context.usesInternalTLS else { return "" }
        let name = "https://\(hostname(context))"
        return """

          home-door:
            image: \(Self.homeDoorImage)
            restart: unless-stopped
            depends_on:
              - seafile
            # Seafile's links carry its HTTPS name; apps at home
            # reach it by address, so the links follow the address.
            command:
              - /bin/sh
              - -c
              - |
                cat > /etc/nginx/conf.d/default.conf <<'CONF'
                server {
                    listen 80;
                    client_max_body_size 0;
                    proxy_request_buffering off;
                    location / {
                        proxy_pass http://seafile:80;
                        proxy_http_version 1.1;
                        proxy_set_header Host $$http_host;
                        proxy_set_header X-Forwarded-For $$proxy_add_x_forwarded_for;
                        proxy_set_header X-Forwarded-Proto http;
                        proxy_set_header Accept-Encoding "";
                        proxy_redirect \(name)/ /;
                        proxy_read_timeout 1200s;
                        sub_filter_types application/json text/javascript application/javascript;
                        sub_filter_once off;
                        sub_filter "\(name)" "http://$$http_host";
                    }
                }
                CONF
                exec nginx -g 'daemon off;'
            ports:
              - "127.0.0.1:\(Self.homeDoorPort):80"
        """
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.seafilePath
        let data = dataPath(context)
        let lang = context.language
        let trustedOrigins = context.servedHostnames(of: hostname(context))
            .map { "'https://\($0)'" }
            .joined(separator: ", ")
        return [
            #"""
            log "Seafile: \#(L10nServices.serviceStarting(lang))"
            # Modes spelled out rather than left to the umask: the container
            # writes into /shared as its own user.
            install -d -m 755 \#(data) \#(path)/db
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#,
            #"""
            # Trusted CSRF origins — see the type comment. Without them the
            # sign-in POST is refused by Django with a CSRF error that reads
            # like a wrong password, because Caddy terminates TLS and the
            # container's nginx never tells Django the request was https.
            #
            # Nothing below is fatal and no output is discarded: the same rule
            # the mailcow API, Nextcloud occ and Forgejo admin blocks follow.
            # This step sits in the middle of a `set -euo pipefail` script whose
            # remaining work includes revoking the install key.
            SF_CONF='\#(data)/seafile/conf/seahub_settings.py'
            SF_OUT=""
            # Why the wait is still going, bounded to one line — the server's
            # own log is the only explanation there is, and the app streams
            # this output.
            sf_why() {
              SF_OUT="$(timeout 20 docker compose -p \#(Self.composeProject) logs --tail=20 seafile 2>&1 || true)"
              printf '%s' "$SF_OUT" | tr -d '\r\n' | cut -c1-300
            }
            # A deadline, not a number of tries: the first start creates three
            # schemas and runs the whole migration set, which takes minutes on
            # a small ARM board, and every probe can burn its own timeout.
            SF_READY=0
            SF_TRY=0
            SF_DEADLINE=$(($(date +%s) + 600))
            while [ "$(date +%s)" -lt "$SF_DEADLINE" ]; do
              if [ -f "$SF_CONF" ]; then SF_READY=1; break; fi
              SF_TRY=$((SF_TRY + 1))
              # Heartbeat every ~30 s: a silent wait is indistinguishable from
              # a hung install in the app's progress view.
              if [ "$((SF_TRY % 6))" -eq 0 ]; then
                log "\#(L10nServices.seafileWaiting(lang)) ($(sf_why))"
              fi
              sleep 5
            done
            if [ "$SF_READY" -eq 1 ]; then
              # Rewritten on EVERY run, not appended once: the served name list
              # changes when the owner adds a domain, and Seafile reads this
              # file only at start. Same reason Nextcloud re-applies its
              # trusted domains instead of trusting the first install.
              sed -i '/^CSRF_TRUSTED_ORIGINS = /d' "$SF_CONF"
              printf '%s\n' "CSRF_TRUSTED_ORIGINS = [\#(trustedOrigins)]" >> "$SF_CONF"
              docker compose -p \#(Self.composeProject) restart seafile >/dev/null 2>&1 || true
            else
              log "\#(L10nServices.seafileUnavailable(lang)) ($(sf_why))"
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
        let path = context.settings.seafilePath
        let lang = context.language
        return [#"""
        echo "Seafile:      https://\#(hostname(context))"
        echo "  \#(L10nServices.administratorLabel(lang)): \#(adminLogin(context))"
        echo "  \#(L10nServices.passwordGeneratedOnServerLabel(lang)): $(grep '^SEAFILE_ADMIN_PASSWORD=' \#(path)/.env | cut -d= -f2-)"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.seafilePath
        let data = dataPath(context)
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
                    dataPath: data,
                    databases: [
                        BackupDatabase(engine: .mysql, service: "db",
                                       fileName: "ccnet_db.sql", databaseName: "ccnet_db"),
                        BackupDatabase(engine: .mysql, service: "db",
                                       fileName: "seafile_db.sql", databaseName: "seafile_db"),
                        BackupDatabase(engine: .mysql, service: "db",
                                       fileName: "seahub_db.sql", databaseName: "seahub_db")
                    ],
                    quiesceServices: ["seafile"],
                    encryptsByDefault: false,
                    sizePaths: [data, "\(path)/db"],
                    excludes: ["data/logs"]
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
        UpdateSpec(images: [Self.image, Self.databaseImage, Self.cacheImage])
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            configDirectory: context.settings.seafilePath,
            dataPaths: ["\(dataPath(context)).pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}
