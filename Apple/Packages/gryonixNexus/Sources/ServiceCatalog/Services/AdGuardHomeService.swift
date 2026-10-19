public struct AdGuardHomeService: ManagedService {
    public static let composeProject = "adguardhome"
    public static let container = "adguardhome"
    public static let webUIPort = 8087
    public static let containerWebPort = 3000
    public static let wrapperTarget = ServiceID.adguardHome.rawValue
    /// Exact patch tag
    public static let image = "adguard/adguardhome:v0.107.78"

    public let id = ServiceID.adguardHome
    public let displayName = "AdGuard Home"
    public let systemImage = "shield.lefthalf.filled"
    public let category = ServiceCategory.network
    public let usesSharedAdminLogin = true
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    /// One small Go daemon: it idles around 100 MiB
    public let resources = ServiceResources(memoryMB: 256, diskGB: 2)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.adguardHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.adguardHome, context) : custom
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.adguardPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              adguardhome:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                volumes:
                  - \(path)/conf:/opt/adguardhome/conf
                  - \(path)/work:/opt/adguardhome/work
                ports:
                  - "127.0.0.1:\(Self.webUIPort):\(Self.containerWebPort)"
                  # Loopback ONLY — see the type comment. A published port is
                  # reachable from the internet regardless of our nftables
                  # ruleset, so an open resolver is prevented here or nowhere.
                  - "127.0.0.1:53:53/tcp"
                  - "127.0.0.1:53:53/udp"
            """,
            envTemplate: """
            ADGUARD_ADMIN_PASSWORD=__RANDOM__
            """
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.adguardPath
        let lang = context.language
        let admin = context.settings.adminUsername
        return [
            #"""
            log "AdGuard Home: \#(L10nServices.serviceStarting(lang))"
            install -d -m 755 \#(path)/conf \#(path)/work
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#,
            #"""
            # Initial configuration through AdGuard's own installation API.
            #
            # Without it AdGuard serves its SETUP WIZARD to whoever opens the
            # page, and this page is on a public hostname — the first visitor
            # would name the administrator and own the resolver. The password
            # is generated on the server, travels in a request BODY (never in
            # argv, where /proc hands it to every account) and is stored by
            # AdGuard as a bcrypt hash.
            #
            # Nothing below is fatal and no output is discarded: the same rule
            # the mailcow API and Nextcloud occ blocks follow. Under
            # `set -euo pipefail` a failure here would take the remaining
            # steps — including the install key revocation — with it.
            AG_CODE=""
            AG_BODY=""
            ag_api() {
              local method="$1" path="$2" data="${3:-}" out=""
              if [ -n "$data" ]; then
                out="$(timeout 20 curl -sS -X "$method" -H 'Content-Type: application/json' \
                       --data-binary "@$data" -w '\nGD_HTTP:%{http_code}' \
                       "http://127.0.0.1:\#(Self.webUIPort)$path" 2>&1)" || true
              else
                out="$(timeout 20 curl -sS -X "$method" -w '\nGD_HTTP:%{http_code}' \
                       "http://127.0.0.1:\#(Self.webUIPort)$path" 2>&1)" || true
              fi
              AG_CODE="$(printf '%s' "$out" | sed -n 's/^GD_HTTP://p' | tail -n1)"
              AG_BODY="$(printf '%s' "$out" | sed '/^GD_HTTP:/d')"
              case "$AG_CODE" in 2*) return 0 ;; *) return 1 ;; esac
            }
            # Why the last call failed, bounded to one line — the body IS the
            # explanation, which is exactly what `curl -f` throws away.
            ag_why() { printf '%s %s' "${AG_CODE:-no-response}" "$(printf '%s' "$AG_BODY" | tr -d '\r\n' | cut -c1-300)"; }
            AG_CONF=\#(path)/conf/AdGuardHome.yaml
            if [ ! -f "$AG_CONF" ]; then
              # A deadline, not a number of tries: every attempt can burn its
              # own timeout, so counting attempts makes the real wait unbounded.
              AG_READY=0
              AG_TRY=0
              AG_DEADLINE=$(($(date +%s) + 300))
              while [ "$(date +%s)" -lt "$AG_DEADLINE" ]; do
                if ag_api GET /control/install/get_addresses; then AG_READY=1; break; fi
                AG_TRY=$((AG_TRY + 1))
                # Heartbeat every ~30 s: a silent wait is indistinguishable
                # from a hung install in the app's progress view.
                if [ "$((AG_TRY % 6))" -eq 0 ]; then
                  log "\#(L10nServices.adguardWaiting(lang)) ($(ag_why))"
                fi
                sleep 5
              done
              if [ "$AG_READY" -eq 1 ]; then
                AG_PASSWORD="$(grep '^ADGUARD_ADMIN_PASSWORD=' \#(path)/.env | cut -d= -f2- || true)"
                if [ -n "$AG_PASSWORD" ]; then
                  AG_REQ="$(mktemp)"
                  chmod 600 "$AG_REQ"
                  # The web port MUST be the one the compose file publishes to,
                  # and the DNS port the one bound inside the container: this
                  # call is what AdGuard writes into its config and listens on
                  # from here on.
                  printf '{"web":{"ip":"0.0.0.0","port":%s},"dns":{"ip":"0.0.0.0","port":53},"username":"%s","password":"%s"}' \
                    \#(Self.containerWebPort) '\#(admin)' "$AG_PASSWORD" > "$AG_REQ"
                  if ! ag_api POST /control/install/configure "$AG_REQ"; then
                    log "\#(L10nServices.adguardConfigureFailed(lang)) ($(ag_why))"
                  fi
                  rm -f "$AG_REQ"
                fi
              else
                log "\#(L10nServices.adguardUnavailable(lang)) ($(ag_why))"
              fi
            fi
            # Plain-HTTP DoH, so the filter can be used from anywhere through
            # Caddy without a public UDP resolver. The key MOVED in v0.107.74
            # (tls.allow_unencrypted_doh became http.doh.insecure_enabled), so
            # both spellings are handled: a pinned image is upgraded one day,
            # and a silently missing setting means DoH clients get a 404 with
            # nothing to explain it.
            if [ -f "$AG_CONF" ]; then
              if grep -q '^ *insecure_enabled:' "$AG_CONF"; then
                sed -i 's/^\( *\)insecure_enabled: false$/\1insecure_enabled: true/' "$AG_CONF"
              elif grep -q '^ *allow_unencrypted_doh:' "$AG_CONF"; then
                sed -i 's/^\( *\)allow_unencrypted_doh: false$/\1allow_unencrypted_doh: true/' "$AG_CONF"
              else
                log "\#(L10nServices.adguardDoHKeyMissing(lang))"
              fi
              docker compose -p \#(Self.composeProject) restart >/dev/null 2>&1 || true
            fi
            """#
        ]
    }

    /// Nothing is opened
    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { [] }

    public func webIngress(_ context: ServiceContext) -> WebIngress? {
        WebIngress(hostname: hostname(context), upstreamPort: Self.webUIPort)
    }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.adguardPath
        let lang = context.language
        let host = hostname(context)
        return [#"""
        echo "AdGuard Home: https://\#(host)"
        echo "  \#(L10nServices.administratorLabel(lang)): \#(context.settings.adminUsername)"
        echo "  \#(L10nServices.passwordGeneratedOnServerLabel(lang)): $(grep '^ADGUARD_ADMIN_PASSWORD=' \#(path)/.env | cut -d= -f2-)"
        echo "  \#(L10nServices.adguardDoHNote(lang)): https://\#(host)/dns-query"
        echo "  \#(L10nServices.adguardPlainDNSNote(lang))"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.adguardPath
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
                    dataPath: "\(path)/conf",
                    databases: [],
                    quiesceServices: [],
                    encryptsByDefault: true,
                    sizePaths: ["\(path)/conf"]
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
        UpdateSpec(images: [Self.image])
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            configDirectory: context.settings.adguardPath,
            dataPaths: ["\(context.settings.adguardPath)/conf.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}
