/// Nextcloud (files/calendar/contacts): nextcloud + mariadb + redis behind
/// the shared Caddy ingress. Fully configured by the setup script: the admin
/// account is created on first start from env (NEXTCLOUD_ADMIN_*), the
/// password and DB secrets are generated ON THE SERVER (__RANDOM__ markers) —
/// no secrets in the artifacts, nothing to configure by hand.
public struct NextcloudService: ManagedService {
    public static let composeProject = "nextcloud"
    public static let webUIPort = 8081
    /// Label the backup and restore wrappers case on
    public static let wrapperTarget = ServiceID.nextcloud.rawValue
    public static let image = "nextcloud:35-apache"
    public static let databaseImage = "mariadb:11"
    public static let cacheImage = "redis:7-alpine"

    public let id = ServiceID.nextcloud
    public let displayName = "Nextcloud"
    public let systemImage = "icloud"
    public let category = ServiceCategory.files
    public let usesSharedAdminLogin = true
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 768, diskGB: 3)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.nextcloudHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.nextcloud, context) : custom
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.nextcloudPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              db:
                image: \(Self.databaseImage)
                restart: unless-stopped
                command: --transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW
                environment:
                  MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
                  MYSQL_PASSWORD: ${MYSQL_PASSWORD}
                  MYSQL_DATABASE: nextcloud
                  MYSQL_USER: nextcloud
                volumes:
                  - \(path)/db:/var/lib/mysql
              redis:
                image: \(Self.cacheImage)
                restart: unless-stopped
              app:
                image: \(Self.image)
                restart: unless-stopped
                depends_on:
                  - db
                  - redis
                environment:
                  MYSQL_HOST: db
                  MYSQL_PASSWORD: ${MYSQL_PASSWORD}
                  MYSQL_DATABASE: nextcloud
                  MYSQL_USER: nextcloud
                  REDIS_HOST: redis
                  NEXTCLOUD_ADMIN_USER: \(context.settings.adminUsername)
                  NEXTCLOUD_ADMIN_PASSWORD: ${NEXTCLOUD_ADMIN_PASSWORD}
                  NEXTCLOUD_TRUSTED_DOMAINS: \(context.servedHostnames(of: hostname(context)).joined(separator: " "))
                  \(proxyEnvironment(context))
                volumes:
                  - \(path)/data:/var/www/html
                ports:
                  - "127.0.0.1:\(Self.webUIPort):80"
              cron:
                image: \(Self.image)
                restart: unless-stopped
                entrypoint: /cron.sh
                depends_on:
                  - app
                volumes:
                  - \(path)/data:/var/www/html
            """,
            envTemplate: """
            MYSQL_ROOT_PASSWORD=__RANDOM__
            MYSQL_PASSWORD=__RANDOM__
            NEXTCLOUD_ADMIN_PASSWORD=__RANDOM__
            """
        )
    }

    /// Caddy's headers, and HTTPS links on a public server
    func proxyEnvironment(_ context: ServiceContext) -> String {
        context.usesInternalTLS
            ? "TRUSTED_PROXIES: \(Self.trustedProxies)"
            : "TRUSTED_PROXIES: \(Self.trustedProxies)\n      OVERWRITEPROTOCOL: https"
    }

    /// Caddy and the Docker network its requests come from
    static let trustedProxies = "127.0.0.1 172.16.0.0/12 192.168.0.0/16"

    /// Links follow the address the request used
    func linkSetters(_ context: ServiceContext) -> String {
        let key = { (name: String) in L10nServices.nextcloudConfigSetFailed(context.language, key: name) }
        guard context.usesInternalTLS else {
            return "nc_occ config:system:delete overwritehost\n"
                + "    nc_occ config:system:set overwriteprotocol --value=https \\\n"
                + "      || log \"\(key("overwriteprotocol")) ($(nc_why))\""
        }
        let slot = context.servedHostnames(of: hostname(context)).count + 1
        return "nc_occ config:system:set trusted_domains \(slot) --value='*' \\\n"
            + "      || log \"\(key("trusted_domains \(slot)")) ($(nc_why))\"\n"
            + "    nc_occ config:system:delete overwritehost\n"
            + "    nc_occ config:system:delete overwriteprotocol"
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.nextcloudPath
        let trustedDomainSetters = context.servedHostnames(of: hostname(context))
            .enumerated()
            .map {
                "nc_occ config:system:set trusted_domains \($0.offset + 1) --value=\($0.element) \\\n"
                + "      || log \"\(L10nServices.nextcloudConfigSetFailed(context.language, key: "trusted_domains \($0.offset + 1)")) ($(nc_why))\""
            }
            .joined(separator: "\n    ")
        return [
            #"""
            log "Nextcloud: \#(L10nServices.serviceStarting(context.language))"
            install -d \#(path)
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#,
            #"""
            cd \#(path)
            # Nextcloud writes trusted_domains/overwritehost into config.php only
            # when it FIRST initialises the instance; the compose environment is
            # ignored afterwards. A reinstall onto another domain would therefore
            # be met with "Access through untrusted domain". Re-apply the
            # current hostname on every run — a no-op when it already matches.
            NC_APP="$(docker compose -p \#(Self.composeProject) ps -q app 2>/dev/null | head -n1)"
            if [ -n "$NC_APP" ]; then
              # occ's output is CAPTURED, never discarded, and no call here is
              # fatal — the same rule the mailcow API block follows. This ran
              # `occ … >/dev/null 2>&1` outside any `if`, so a freshly started
              # instance that answered `status` but was not ready for
              # config:system:set killed the whole install through errexit: on
              # a real run it died at step 9 of 22 with exit 1 and NOT ONE line
              # of explanation, leaving a half-configured server. A trusted
              # domain can be fixed from the admin UI; a half-install cannot.
              NC_OUT=""
              nc_occ() { NC_OUT="$(docker exec -u www-data "$NC_APP" php occ "$@" 2>&1)"; }
              # Why the last call failed, bounded to one line: occ can answer
              # with a stack trace, and the app streams this log.
              nc_why() { printf '%s' "$NC_OUT" | tr -d '\r\n' | cut -c1-300; }
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
                printf '%s' "$NC_OUT" | grep -q 'installed: true'
              }
              for _ in $(seq 1 60); do
                nc_ready && break
                sleep 5
              done
              if nc_ready; then
                # Index 1, never 0: slot 0 holds "localhost" from the image's own
                # installer and dropping it would cut local access off.
                # One slot per name the Caddy site serves — the alias domains
                # included, or Nextcloud answers them "untrusted domain" while
                # Caddy happily holds a certificate for them.
                \#(trustedDomainSetters)
                \#(linkSetters(context))
                nc_occ config:system:set overwrite.cli.url --value=https://\#(hostname(context)) \
                  || log "\#(L10nServices.nextcloudConfigSetFailed(context.language, key: "overwrite.cli.url")) ($(nc_why))"
                # Background jobs by the cron container, heavy jobs at night.
                nc_occ config:system:set maintenance_window_start --type=integer --value=1 \
                  || log "\#(L10nServices.nextcloudConfigSetFailed(context.language, key: "maintenance_window_start")) ($(nc_why))"
                nc_occ background:cron \
                  || log "\#(L10nServices.nextcloudConfigSetFailed(context.language, key: "background:cron")) ($(nc_why))"
                nc_occ db:add-missing-indices \
                  || log "\#(L10nServices.nextcloudConfigSetFailed(context.language, key: "db:add-missing-indices")) ($(nc_why))"
                nc_occ maintenance:repair --include-expensive \
                  || log "\#(L10nServices.nextcloudConfigSetFailed(context.language, key: "maintenance:repair")) ($(nc_why))"
              else
                log "\#(L10nServices.nextcloudOccUnavailable(context.language)) ($(nc_why))"
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
        let path = context.settings.nextcloudPath
        let lang = context.language
        let passwordLabel = L10nServices.passwordGeneratedOnServerLabel(lang)
        return [#"""
        echo "Nextcloud:    https://\#(hostname(context))"
        echo "  \#(L10nServices.administratorLabel(lang)): \#(context.settings.adminUsername)"
        echo "  \#(passwordLabel): $(grep '^NEXTCLOUD_ADMIN_PASSWORD=' \#(path)/.env | cut -d= -f2-)"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.nextcloudPath
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
                    databases: [BackupDatabase(engine: .mysql, service: "db",
                                               fileName: "nextcloud.sql")],
                    quiesceServices: ["app"],
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
        UpdateSpec(images: [Self.image, Self.databaseImage, Self.cacheImage])
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            configDirectory: context.settings.nextcloudPath,
            dataPaths: ["\(context.settings.nextcloudPath)/data.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}
