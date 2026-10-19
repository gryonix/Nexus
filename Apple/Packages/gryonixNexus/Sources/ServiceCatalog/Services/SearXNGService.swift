public struct SearXNGService: ManagedService {
    public static let composeProject = "searxng"
    public static let container = "searxng"
    /// Next free loopback port in the catalog's block
    public static let webUIPort = 8101
    /// The port inside the container
    public static let containerPort = 8080
    public static let wrapperTarget = ServiceID.searxng.rawValue
    public static let image = "searxng/searxng:2026.9.7-3e454637f"

    public static func settingsPath(_ context: ServiceContext) -> String {
        "\(context.settings.searxngPath)/config/settings.yml"
    }

    /// The URL a neighbour on this host queries
    public static let queryURL =
        AIServicesNetwork.url(container, containerPort) + "/search?q=<query>"

    public let id = ServiceID.searxng
    public let displayName = "SearXNG"
    public let systemImage = "magnifyingglass.circle"
    public let category = ServiceCategory.ai
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 512, diskGB: 1)

    public init() {}

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.searxngPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              searxng:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                environment:
                  # Signs the form state their pages carry. Generated on the
                  # server; regenerating it on every start would invalidate
                  # every open tab, which is why it lives in `.env`.
                  SEARXNG_SECRET: ${SEARXNG_SECRET}
                  SEARXNG_PORT: \(Self.containerPort)
                  # Their default is the rate limiter OFF, and this deployment
                  # is the case it was written for: the port answers on
                  # loopback only, so the callers are the containers on this
                  # host. A limiter here would also need the datastore it
                  # counts in, which is a second container for a queue nobody
                  # outside can join.
                  SEARXNG_LIMITER: "false"
                volumes:
                  # Their entrypoint writes a settings file here when it finds
                  # none. The install below always leaves one, so what runs is
                  # always the file this repository generated.
                  - \(path)/config:/etc/searxng
                  - \(path)/cache:/var/cache/searxng
                ports:
                  # Loopback. The neighbours reach it on the shared AI
                  # network; nothing publishes it.
                  - "127.0.0.1:\(Self.webUIPort):\(Self.containerPort)"\(AIServicesNetwork.composeTail)
            """,
            envTemplate: """
            SEARXNG_SECRET=__RANDOM__
            """
        )
    }

    public func settingsFile(_ context: ServiceContext) -> String {
        """
        # Written by gryonixNexus. Upstream's defaults are NOT copied here —
        # they are read out of the image, and only what this deployment
        # changes is named below.
        use_default_settings: true

        search:
          # A program asks for JSON; the default is html only, and a chat that
          # queries this engine gets a refusal without this line.
          formats:
            - html
            - json
        """
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.searxngPath
        return [
            #"""
            log "SearXNG: \#(L10nServices.serviceStarting(context.language))"
            # Ownership is deliberately not set here: their entrypoint starts
            # as root, chowns both mounts to the container's own user and drops
            # privileges itself. A uid guessed on the host would be a uid to
            # keep in step with their image.
            install -d -m 755 \#(path) \#(path)/config \#(path)/cache
            cat > '\#(Self.settingsPath(context))' <<'EOF_SEARXNG_SETTINGS'
            \#(settingsFile(context))
            EOF_SEARXNG_SETTINGS
            chmod 644 '\#(Self.settingsPath(context))'
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            \#(AIServicesNetwork.createStep)
            docker compose -p \#(Self.composeProject) up -d
            """#
        ]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { [] }

    /// None
    public func webIngress(_ context: ServiceContext) -> WebIngress? { nil }

    public func dnsHostnames(_ context: ServiceContext) -> [String] { [] }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        [#"""
        echo "SearXNG:      127.0.0.1:\#(Self.webUIPort)"
        echo "  \#(L10nServices.searxngLoopbackNote(context.language))"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        ServiceActions(
            statusProbe: .container(
                name: Self.container,
                list: PrivilegedCommand(binaryPath: "/usr/bin/docker", arguments: "ps -a")
            ),
            restart: ServicePower.container(Self.container, "restart", timeoutClass: .restart),
            start: ServicePower.container(Self.container, "start", timeoutClass: .restart),
            stop: ServicePower.container(Self.container, "stop", timeoutClass: .restart)
        )
    }

    public func updateSpec(_ context: ServiceContext) -> UpdateSpec {
        UpdateSpec(images: [Self.image])
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            configDirectory: context.settings.searxngPath,
            dataPaths: [],
            backupDirs: []
        )
    }
}
