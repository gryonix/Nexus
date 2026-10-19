public struct HeadscaleService: ManagedService {
    public static let composeProject = "headscale"
    public static let container = "headscale"
    public static let webUIPort = 8091
    /// The port headscale serves on INSIDE the container
    public static let containerPort = 8080
    /// STUN, for the embedded DERP relay
    public static let stunPort = 3478
    public static let wrapperTarget = ServiceID.headscale.rawValue
    /// Exact patch tag
    public static let image = "headscale/headscale:v0.29.3"

    public let id = ServiceID.headscale
    public let displayName = "Headscale"
    public let systemImage = "point.3.filled.connected.trianglepath.dotted"
    public let category = ServiceCategory.mesh
    public let usesSharedAdminLogin = false
    public let requiresPublicDomain = true
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    /// One Go daemon with a SQLite file
    public let resources = ServiceResources(memoryMB: 256, diskGB: 2)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.headscaleHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.headscale, context) : custom
    }

    public func baseDomain(_ context: ServiceContext) -> String {
        let custom = context.settings.headscaleBaseDomain
        return custom.isEmpty ? "ts.\(context.domain)" : custom
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.headscalePath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              headscale:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                command: serve
                volumes:
                  - \(path)/config:/etc/headscale
                  - \(path)/data:/var/lib/headscale
                ports:
                  # Loopback only: Caddy terminates TLS in front of it, which
                  # also puts it under the lockdown guard like every other UI.
                  # The clients REQUIRE the control server over HTTPS, and the
                  # certificate is Caddy's.
                  - "127.0.0.1:\(Self.webUIPort):\(Self.containerPort)"
                  # Public on purpose — STUN for the embedded DERP relay. A
                  # relay only reachable from this host relays nothing.
                  - "\(Self.stunPort):\(Self.stunPort)/udp"
            """
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.headscalePath
        let lang = context.language
        let host = hostname(context)
        let base = baseDomain(context)
        return [
            #"""
            log "Headscale: \#(L10nServices.serviceStarting(lang))"
            install -d -m 755 \#(path)/config \#(path)/data
            # Written every run: the file is ours, and a domain or hostname
            # change has to reach it. Headscale generates its own noise key
            # into the data directory on first start and never rewrites it.
            cat > \#(path)/config/config.yaml <<'EOF_HEADSCALE'
            server_url: https://\#(host)
            listen_addr: 0.0.0.0:\#(Self.containerPort)
            metrics_listen_addr: 127.0.0.1:9090
            noise:
              private_key_path: /var/lib/headscale/noise_private.key
            prefixes:
              v4: 100.64.0.0/10
              v6: fd7a:115c:a1e0::/48
              allocation: sequential
            derp:
              server:
                # The point of self-hosting: without this, a node that cannot
                # reach its peer directly falls back to Tailscale's public
                # relays. Measured — a lab node reported a relay region abroad
                # while this was off.
                enabled: true
                region_id: 999
                region_code: "gryonix"
                region_name: "\#(host)"
                stun_listen_addr: "0.0.0.0:\#(Self.stunPort)"
                private_key_path: /var/lib/headscale/derp_server_private.key
              # No public relay map: everything stays on this host.
              urls: []
              auto_update_enabled: false
            database:
              type: sqlite
              sqlite:
                path: /var/lib/headscale/db.sqlite
            log:
              level: info
            dns:
              magic_dns: true
              base_domain: \#(base)
              # Service names inside the mesh, pointed at this server's own
              # mesh address. A separate FILE rather than an inline
              # `extra_records` block (the two are mutually exclusive) because
              # the addresses are not known now: a node's mesh address is
              # handed out when it joins, which is after this file is written.
              extra_records_path: /etc/headscale/extra-records.json
              nameservers:
                global:
                  - 1.1.1.1
            policy:
              mode: database
            EOF_HEADSCALE
            chmod 600 \#(path)/config/config.yaml
            # Created only when ABSENT, unlike config.yaml: this file holds the
            # published names, and rewriting it on every run would drop them on
            # the next re-install.
            #
            # The second test REPAIRS what older builds wrote here.
            # "unmarshalling records, content: [] backslash n"). A file that
            # does not parse cannot be holding published names, so replacing
            # exactly that content loses nothing; anything else is left alone.
            HS_RECORDS=\#(path)/config/extra-records.json
            if [ ! -f "$HS_RECORDS" ] || [ "$(cat "$HS_RECORDS")" = '[]\n' ]; then
              printf '[]\n' > "$HS_RECORDS"
              chmod 644 "$HS_RECORDS"
            fi
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#
        ]
    }

    /// STUN only
    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] {
        [FirewallPort(Self.stunPort, .udp, comment: "Headscale DERP STUN")]
    }

    public func webIngress(_ context: ServiceContext) -> WebIngress? {
        WebIngress(hostname: hostname(context), upstreamPort: Self.webUIPort, adminGuard: false)
    }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let lang = context.language
        let host = hostname(context)
        let base = baseDomain(context)
        return [#"""
        echo "Headscale: https://\#(host)"
        echo "  \#(L10nServices.headscaleNoWebUINote(lang))"
        echo "  \#(L10nServices.headscaleCreateUserNote(lang)):"
        echo "    sudo docker exec \#(Self.container) headscale users create <name>"
        echo "    sudo docker exec \#(Self.container) headscale preauthkeys create --user <id> --reusable --expiration 24h"
        echo "  \#(L10nServices.headscaleJoinNote(lang)):"
        echo "    tailscale up --login-server https://\#(host) --authkey <key>"
        echo "  \#(L10nServices.headscaleMagicDNSNote(lang)): <device>.\#(base)"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.headscalePath
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
                    dataPath: "\(path)/data",
                    databases: [],
                    quiesceServices: [Self.container],
                    encryptsByDefault: true,
                    sizePaths: ["\(path)/data"]
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
            configDirectory: context.settings.headscalePath,
            dataPaths: ["\(context.settings.headscalePath)/data.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}
