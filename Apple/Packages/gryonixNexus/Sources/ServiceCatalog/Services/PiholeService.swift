public struct PiholeService: ManagedService {
    public static let composeProject = "pihole"
    public static let container = "pihole"
    public static let webUIPort = 8092
    /// Port the admin interface binds INSIDE the container
    public static let containerWebPort = 80
    public static let wrapperTarget = ServiceID.pihole.rawValue
    /// Exact patch tag
    public static let image = "pihole/pihole:2026.07.2"

    public let id = ServiceID.pihole
    public let displayName = "Pi-hole"
    public let systemImage = "shield.lefthalf.filled"
    public let category = ServiceCategory.network
    public let usesSharedAdminLogin = false
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 256, diskGB: 2)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.piholeHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.pihole, context) : custom
    }

    /// The upstreams as the container's own resolvers
    static func containerDNS(_ upstreams: String) -> String {
        let servers = upstreams.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("#") }
        guard !servers.isEmpty else { return "" }
        return "\n    # Blocklist downloads resolve here, not at the router\n    dns:"
            + servers.map { "\n      - \($0)" }.joined()
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.piholePath
        let dnsBind = context.settings.piholeServesNetwork ? "" : "127.0.0.1:"
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              pihole:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped\(Self.containerDNS(context.settings.piholeUpstreams))
                environment:
                  # Read by FTL itself: every `FTLCONF_<section>_<key>` maps to
                  # the matching key of pihole.toml. Verified in the pinned
                  # image's own `bash_functions.sh`, not assumed.
                  FTLCONF_webserver_api_password: ${PIHOLE_ADMIN_PASSWORD}
                  # `local` — FTL's default — answers only the subnets of its
                  # own interfaces, and inside a container that is the docker
                  # bridge alone: every forwarded query would be refused, which
                  # reads as "the filter does not work" rather than as a bind
                  # setting. What is actually reachable is decided by the
                  # published address below.
                  FTLCONF_dns_listeningMode: all
                  FTLCONF_dns_upstreams: \(context.settings.piholeUpstreams)
                volumes:
                  - \(path)/etc-pihole:/etc/pihole
                ports:
                  - "127.0.0.1:\(Self.webUIPort):\(Self.containerWebPort)/tcp"
                  # See the type comment: a published port is reachable
                  # regardless of our nftables ruleset, so an open resolver is
                  # prevented by the bind address or nowhere.
                  - "\(dnsBind)53:53/tcp"
                  - "\(dnsBind)53:53/udp"
            """,
            envTemplate: """
            PIHOLE_ADMIN_PASSWORD=__RANDOM__
            """
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.piholePath
        let lang = context.language
        return [
            #"""
            log "Pi-hole: \#(L10nServices.serviceStarting(lang))"
            install -d -m 755 \#(path)/etc-pihole
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#,
            #"""
            # Wait for the resolver to actually answer, by a DEADLINE rather
            # than a number of tries: each probe can burn its own timeout, so
            # counting tries makes the real wait unbounded (the same lesson the
            # mailcow API block was written from).
            #
            # The probe is a DNS query, not "the container is up": Pi-hole
            # downloads its blocklists on first start (`gravity`), and until
            # that finishes it is running and answering nothing. Nothing here
            # is fatal — a filter that is still building its list is a working
            # install a few minutes early, and failing the whole setup over it
            # would take the remaining services and the install-key revocation
            # with it.
            PH_DEADLINE=$(($(date +%s) + 300))
            PH_TRY=0
            PH_READY=0
            while [ "$(date +%s)" -lt "$PH_DEADLINE" ]; do
              if docker exec \#(Self.container) dig +short +norecurse +retry=0 \
                   @127.0.0.1 pi.hole >/dev/null 2>&1; then
                PH_READY=1
                break
              fi
              PH_TRY=$((PH_TRY + 1))
              # Heartbeat every ~30 s: a silent wait is indistinguishable from
              # a hung install in the app's progress view.
              if [ "$((PH_TRY % 6))" -eq 0 ]; then
                log "\#(L10nServices.piholeWaiting(lang))"
              fi
              sleep 5
            done
            if [ "$PH_READY" -ne 1 ]; then
              log "\#(L10nServices.piholeUnavailable(lang))"
            fi
            """#
        ]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] {
        guard context.settings.piholeServesNetwork else { return [] }
        return [FirewallPort(53, comment: "DNS"), FirewallPort(53, .udp, comment: "DNS")]
    }

    public func webIngress(_ context: ServiceContext) -> WebIngress? {
        WebIngress(hostname: hostname(context), upstreamPort: Self.webUIPort)
    }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.piholePath
        let lang = context.language
        let host = hostname(context)
        return [#"""
        echo "Pi-hole: https://\#(host)/admin"
        echo "  \#(L10nServices.passwordGeneratedOnServerLabel(lang)): $(grep '^PIHOLE_ADMIN_PASSWORD=' \#(path)/.env | cut -d= -f2-)"
        \#(context.settings.piholeServesNetwork
            ? #"echo "  \#(L10nServices.piholeServesNetworkNote(lang))""#
            : #"echo "  \#(L10nServices.piholeLoopbackNote(lang))""#)
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.piholePath
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
                    dataPath: "\(path)/etc-pihole",
                    databases: [],
                    quiesceServices: [],
                    encryptsByDefault: true,
                    sizePaths: ["\(path)/etc-pihole"]
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
            configDirectory: context.settings.piholePath,
            dataPaths: ["\(context.settings.piholePath)/etc-pihole.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}
