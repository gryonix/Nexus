public struct OpenWebUIService: ManagedService {
    public static let composeProject = "open-webui"
    public static let container = "open-webui"
    /// Next free loopback port in the catalog's block
    public static let webUIPort = 8097
    public static let wrapperTarget = ServiceID.openWebUI.rawValue
    /// Exact pinned tag
    public static let image = "ghcr.io/open-webui/open-webui:v0.11.3"

    public let id = ServiceID.openWebUI
    public let displayName = "Open WebUI"
    public let systemImage = "bubble.left.and.text.bubble.right"
    public let category = ServiceCategory.ai
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 1024, diskGB: 2)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.openWebUIHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.openWebUI, context) : custom
    }

    public func engineURL(_ context: ServiceContext) -> String? {
        guard context.installedServices.contains(.ollama) else { return nil }
        return AIServicesNetwork.url(OllamaService.container, OllamaService.apiPort)
    }

    /// The gateway URL, when this deployment has one
    public func gatewayURL(_ context: ServiceContext) -> String? {
        guard context.installedServices.contains(.liteLLM) else { return nil }
        return AIServicesNetwork.url(LiteLLMService.container, LiteLLMService.containerPort) + "/v1"
    }

    /// The search engine's query URL, when this deployment installs one
    public func searchURL(_ context: ServiceContext) -> String? {
        guard context.installedServices.contains(.searxng) else { return nil }
        return SearXNGService.queryURL
    }

    /// Settings the chat stores and ranks above this environment
    public func storedAddressKeys(_ context: ServiceContext) -> [String] {
        var keys: [String] = []
        if engineURL(context) != nil { keys.append("ollama.base_urls") }
        if gatewayURL(context) != nil { keys += ["openai.api_base_urls", "openai.api_keys"] }
        if searchURL(context) != nil {
            keys += ["web.search.enable", "web.search.engine", "web.search.searxng_query_url"]
        }
        return keys
    }

    /// Deletes the named settings from the chat's database
    public static let forgetKeysScript =
        #"import sqlite3, sys; db = sqlite3.connect(sys.argv[1]); "#
        + #"db.executemany("delete from config where key = ?", [(k,) for k in sys.argv[2:]]); db.commit()"#

    /// Drops those settings, so a neighbour added later is seen
    private func forgetStoredAddresses(_ context: ServiceContext, path: String) -> String {
        let keys = storedAddressKeys(context)
        guard !keys.isEmpty else { return "" }
        return #"""

        if [ -f \#(path)/data/webui.db ]; then
          docker run --rm --entrypoint python3 -v \#(path)/data:/data \#(Self.image) -c '\#(Self.forgetKeysScript)' /data/webui.db \#(keys.joined(separator: " ")) || true
        fi
        """#
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.openWebUIPath
        let signups = context.settings.openWebUIAllowSignups ? "true" : "false"
        let engine = engineURL(context).map { "\n      OLLAMA_BASE_URL: \"\($0)\"" } ?? ""
        let gateway = gatewayURL(context).map {
            """

                  OPENAI_API_BASE_URL: "\($0)"
                  OPENAI_API_KEY: ${LLM_GATEWAY_KEY}
            """
        } ?? ""
        let search = searchURL(context).map {
            """

                  ENABLE_WEB_SEARCH: "true"
                  WEB_SEARCH_ENGINE: "searxng"
                  SEARXNG_QUERY_URL: "\($0)"
            """
        } ?? ""
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              open-webui:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                environment:
                  WEBUI_URL: "https://\(hostname(context))"
                  # Session signing key. Generated on the server — regenerating
                  # it on every start would sign every existing session out.
                  WEBUI_SECRET_KEY: ${WEBUI_SECRET_KEY}
                  ENABLE_SIGNUP: "\(signups)"\(engine)\(gateway)\(search)
                volumes:
                  - \(path)/data:/app/backend/data
                ports:
                  - "127.0.0.1:\(Self.webUIPort):8080"\(AIServicesNetwork.composeTail)
            """,
            envTemplate: """
            WEBUI_SECRET_KEY=__RANDOM__
            """
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.openWebUIPath
        let gateway = gatewayURL(context) == nil ? "" : #"""

        \#(LiteLLMService.appKeySection(.openWebUI))
        \#(LiteLLMService.setEnvSection(path: "\(path)/.env",
                                        key: "LLM_GATEWAY_KEY",
                                        value: "$(cat '\(LiteLLMService.appKeyPath(.openWebUI))')"))
        """#
        return [
            #"""
            log "Open WebUI: \#(L10nServices.serviceStarting(context.language))"
            install -d -m 755 \#(path)/data\#(gateway)
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q\#(forgetStoredAddresses(context, path: path))
            \#(AIServicesNetwork.createStep)
            docker compose -p \#(Self.composeProject) up -d
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
        var lines = [
            #"echo "Open WebUI:   https://\#(hostname(context))""#,
            #"echo "  \#(L10nServices.openWebUIAdminWarning(lang))""#
        ]
        if engineURL(context) == nil, gatewayURL(context) == nil {
            lines.append(#"echo "  \#(L10nServices.openWebUINoEngineNote(lang))""#)
        }
        return [lines.joined(separator: "\n")]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.openWebUIPath
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
                    encryptsByDefault: false,
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
            configDirectory: context.settings.openWebUIPath,
            dataPaths: ["\(context.settings.openWebUIPath)/data.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}
