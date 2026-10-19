public struct PsonoService: ManagedService {
    public static let composeProject = "psono"
    public static let container = "psono"
    /// Loopback port Caddy proxies to
    public static let webUIPort = 8089
    public static let wrapperTarget = ServiceID.psono.rawValue
    /// Exact combo tag — `<server>-<webclient>-<admin-client>` component versions, not a floating tag
    public static let image = "psono/psono-combo:7.3.0-4.7.2-1.8.2"
    public static let databaseImage = "postgres:16-alpine"

    public let id = ServiceID.psono
    public let displayName = "Psono"
    public let systemImage = "key.fill"
    public let category = ServiceCategory.passwords
    public let usesSharedAdminLogin = true
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 512, diskGB: 2)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.psonoHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.psono, context) : custom
    }

    public func adminLogin(_ context: ServiceContext) -> String {
        "\(context.settings.adminUsername)@\(context.domain)"
    }

    private func settingsPath(_ context: ServiceContext) -> String {
        "\(context.settings.psonoPath)/config/settings.yaml"
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.psonoPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              db:
                image: \(Self.databaseImage)
                restart: unless-stopped
                environment:
                  # Read by the shared backup wrapper from the container's OWN
                  # environment — compose already put it there — because
                  # passing it from the host would sit in the argv of docker
                  # exec, where /proc hands it to every account.
                  POSTGRES_DB: psono
                  POSTGRES_USER: psono
                  POSTGRES_PASSWORD: ${PSONO_DB_PASSWORD}
                volumes:
                  - \(path)/db:/var/lib/postgresql/data
              psono:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                depends_on:
                  - db
                # Upstream's own installation guide sets this on the combo
                # container; left at the kernel default, a busy instance drops
                # connections under load rather than queuing them.
                sysctls:
                  net.core.somaxconn: 65535
                volumes:
                  # settings.yaml is written by setupSteps below, not by this
                  # compose file — it is not env-templated (see the type
                  # comment: two of its keys are a matched keypair). The same
                  # config.json is mounted twice, into the web client AND the
                  # admin portal, exactly as Psono's own reference compose
                  # does — they are two apps served by the same nginx and read
                  # the same "which server do I talk to" file.
                  - \(path)/config/settings.yaml:/root/.psono_server/settings.yaml
                  - \(path)/config/webclient/config.json:/usr/share/nginx/html/config.json
                  - \(path)/config/webclient/config.json:/usr/share/nginx/html/portal/config.json
                ports:
                  # The combo image runs its OWN nginx on 80 in front of the
                  # web client, the admin portal AND the Django server (at
                  # /server) — one upstream port covers all three, and Caddy
                  # speaks plain HTTP to it like every other service here.
                  - "127.0.0.1:\(Self.webUIPort):80"
            """,
            envTemplate: """
            PSONO_DB_PASSWORD=__RANDOM__
            PSONO_ADMIN_PASSWORD=__RANDOM__
            """
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.psonoPath
        let host = hostname(context)
        let domain = context.domain
        let admin = adminLogin(context)
        let lang = context.language
        let settings = settingsPath(context)
        return [
            #"""
            log "Psono: \#(L10nServices.serviceStarting(lang))"
            install -d -m 755 \#(path)/db \#(path)/config \#(path)/config/webclient
            # The web client and the admin portal read the SAME file to learn
            # which server to talk to — see the compose double-mount above.
            # allow_custom_server is off: nobody should be able to point this
            # client at a different backend from the login screen.
            cat > \#(path)/config/webclient/config.json <<EOF_PS_CLIENT
            {
              "backend_servers": [{"title": "Psono", "url": "https://\#(host)/server"}],
              "base_url": "https://\#(host)/",
              "allow_custom_server": false,
              "allow_registration": false,
              "allow_lost_password": false,
              "disable_download_bar": false,
              "remember_me_default": false,
              "trust_device_default": false,
              "authentication_methods": ["AUTHKEY"],
              "saml_provider": []
            }
            EOF_PS_CLIENT
            """#,
            #"""
            # settings.yaml is generated ONCE. `generateserverkeys.py` prints
            # SECRET_KEY / ACTIVATION_LINK_SECRET / DB_SECRET / EMAIL_SECRET_SALT
            # (independent random values) AND PRIVATE_KEY / PUBLIC_KEY — a
            # matched Curve25519 pair the image derives with nacl, which is
            # exactly why they are not __RANDOM__ envTemplate lines: two
            # independently random hex strings would not be a valid keypair.
            # Its stdout IS already valid YAML (Python repr()-quoted), so it is
            # captured straight into the file with no re-quoting on this side.
            # Guarded by file existence, the same idempotency rule as every
            # other first-run secret in this catalog — a re-run (repair,
            # reinstall onto the same path) must never regenerate keys that
            # existing encrypted datastores already depend on.
            PS_FRESH=0
            if [ ! -f \#(settings) ]; then
              PS_FRESH=1
              docker run --rm \#(Self.image) python3 ./psono/generateserverkeys.py > \#(settings)
              PS_DB_PASSWORD="$(grep '^PSONO_DB_PASSWORD=' \#(path)/.env | cut -d= -f2-)"
              # Everything generateserverkeys.py does not cover. Registration
              # is closed from this first write, never opened later — an
              # instance that was briefly open is a window this catalog does
              # not accept for any service (Forgejo's INSTALL_LOCK is the same
              # rule). The favicon service defaults to a THIRD PARTY endpoint
              # (Psono's own privacy-friendly proxy, or Google's) that the
              # client calls per stored URL to fetch an icon — left blank so
              # nothing here calls out on its own.
              cat >> \#(settings) <<EOF_PS_SETTINGS
            WEB_CLIENT_URL: 'https://\#(host)'
            HOST_URL: 'https://\#(host)/server'
            # Two hops in front of the Django app: Caddy, then the combo
            # image's own nginx. Psono's own docs name this exact number for
            # this exact topology.
            NUM_PROXIES: 2
            ALLOWED_HOSTS: ['*']
            ALLOWED_DOMAINS: ['\#(domain)']
            ALLOW_REGISTRATION: False
            ALLOW_LOST_PASSWORD: False
            MANAGEMENT_ENABLED: True
            DEBUG: False
            FAVICON_SERVICE_URL: ''
            EMAIL_FROM: 'psono@\#(domain)'
            EMAIL_HOST: ''
            EMAIL_HOST_USER: ''
            EMAIL_HOST_PASSWORD: ''
            EMAIL_PORT: 25
            EMAIL_USE_TLS: False
            EMAIL_USE_SSL: False
            DATABASES:
              default:
                'ENGINE': 'django.db.backends.postgresql_psycopg2'
                'NAME': 'psono'
                'USER': 'psono'
                'PASSWORD': '$PS_DB_PASSWORD'
                'HOST': 'db'
                'PORT': '5432'
            EOF_PS_SETTINGS
              chmod 600 \#(settings)
            fi
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#,
            #"""
            # `presetup` installs the ltree/pgcrypto extensions Psono needs and
            # `migrate` applies the schema — both idempotent, so both run on
            # EVERY setup pass, not only a fresh install: this catalog's other
            # services update by pulling a new image and restarting alone,
            # which would silently skip a migration a new Psono version needs.
            #
            # Nothing below is fatal and no output is discarded: the same rule
            # the mailcow API, Nextcloud occ, Forgejo and Seafile provisioning
            # blocks follow. This sits in the middle of a `set -euo pipefail`
            # script whose remaining steps include revoking the install key.
            PS_OUT=""
            ps_exec() { PS_OUT="$(timeout 60 docker exec \#(Self.container) "$@" 2>&1)"; }
            ps_why() { printf '%s' "$PS_OUT" | tr -d '\r\n' | cut -c1-300; }
            # A deadline, not a number of tries: each attempt can burn its own
            # timeout. `presetup` doubles as the readiness probe — it needs a
            # working database connection, which is the thing not ready yet
            # while the container already reports up.
            PS_READY=0
            PS_TRY=0
            PS_DEADLINE=$(($(date +%s) + 300))
            while [ "$(date +%s)" -lt "$PS_DEADLINE" ]; do
              if ps_exec python3 ./psono/manage.py presetup; then PS_READY=1; break; fi
              PS_TRY=$((PS_TRY + 1))
              if [ "$((PS_TRY % 6))" -eq 0 ]; then
                log "\#(L10nServices.psonoWaiting(lang)) ($(ps_why))"
              fi
              sleep 5
            done
            if [ "$PS_READY" -eq 1 ]; then
              ps_exec python3 ./psono/manage.py migrate || log "\#(L10nServices.psonoMigrateFailed(lang)) ($(ps_why))"
              if [ "$PS_FRESH" -eq 1 ]; then
                PS_ADMIN_PASSWORD="$(grep '^PSONO_ADMIN_PASSWORD=' \#(path)/.env | cut -d= -f2- || true)"
                if [ -n "$PS_ADMIN_PASSWORD" ]; then
                  ps_exec python3 ./psono/manage.py createuser \#(admin) "$PS_ADMIN_PASSWORD" \#(admin) \
                    && ps_exec python3 ./psono/manage.py promoteuser \#(admin) superuser \
                    && ps_exec python3 ./psono/manage.py verifyuseremail \#(admin) \
                    || log "\#(L10nServices.psonoAdminCreateFailed(lang)) ($(ps_why))"
                fi
              fi
            else
              log "\#(L10nServices.psonoUnavailable(lang)) ($(ps_why))"
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
        let path = context.settings.psonoPath
        let lang = context.language
        return [#"""
        echo "Psono:        https://\#(hostname(context))"
        echo "  \#(L10nServices.administratorLabel(lang)): \#(adminLogin(context))"
        echo "  \#(L10nServices.passwordGeneratedOnServerLabel(lang)): $(grep '^PSONO_ADMIN_PASSWORD=' \#(path)/.env | cut -d= -f2-)"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.psonoPath
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
                    dataPath: "\(path)/config",
                    databases: [BackupDatabase(engine: .postgres, service: "db",
                                               fileName: "psono.sql")],
                    quiesceServices: [],
                    encryptsByDefault: true,
                    sizePaths: ["\(path)/config", "\(path)/db"]
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
            configDirectory: context.settings.psonoPath,
            dataPaths: ["\(context.settings.psonoPath)/config.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}
