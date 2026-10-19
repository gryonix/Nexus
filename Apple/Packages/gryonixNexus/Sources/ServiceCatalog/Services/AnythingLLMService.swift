public struct AnythingLLMService: ManagedService {
    public static let composeProject = "anythingllm"
    public static let container = "anythingllm"
    /// Next free loopback port in the catalog's block
    public static let webUIPort = 8100
    /// The port inside the container
    public static let containerPort = 3001
    public static let wrapperTarget = ServiceID.anythingLLM.rawValue
    /// Exact pinned tag
    public static let image = "mintplexlabs/anythingllm:1.16.1"

    /// The settings file the container reads AND writes
    public static func envPath(_ context: ServiceContext) -> String {
        "\(context.settings.anythingLLMPath)/anythingllm.env"
    }

    public let id = ServiceID.anythingLLM
    public let displayName = "AnythingLLM"
    public let systemImage = "doc.text.magnifyingglass"
    public let category = ServiceCategory.ai
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 2048, diskGB: 4)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.anythingLLMHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.anythingLLM, context) : custom
    }

    public enum ModelSource: Sendable, Hashable {
        case gateway
        case engine
    }

    public func modelSource(_ context: ServiceContext) -> ModelSource? {
        if context.installedServices.contains(.liteLLM) { return .gateway }
        if context.installedServices.contains(.ollama) { return .engine }
        return nil
    }

    public func usesQdrant(_ context: ServiceContext) -> Bool {
        context.installedServices.contains(.qdrant)
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.anythingLLMPath
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              anythingllm:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                # uid 1000, matching the directories the setup step creates.
                # Spelled out rather than left to the image so that the host
                # side and the container side cannot drift apart.
                user: "1000:1000"
                environment:
                  # The only two settings the UI must not be able to move.
                  # Everything else lives in the mounted settings file, which
                  # the container owns — see the type comment.
                  STORAGE_DIR: "/app/server/storage"
                  SERVER_PORT: \(Self.containerPort)
                  # Chromium's own sandbox needs namespace calls docker's
                  # default seccomp profile blocks, so upstream's documented
                  # runs all add a capability instead. This buys the same
                  # feature for a far smaller grant — see the service comment.
                  ANYTHINGLLM_CHROMIUM_ARGS: "--no-sandbox"
                volumes:
                  - \(path)/storage:/app/server/storage
                  - \(path)/anythingllm.env:/app/server/.env
                ports:
                  - "127.0.0.1:\(Self.webUIPort):\(Self.containerPort)"\(AIServicesNetwork.composeTail)
            """,
            envTemplate: nil
        )
    }

    public func seededSettings(_ context: ServiceContext) -> [String] {
        var lines = [
            "EMBEDDING_ENGINE='native'"
        ]
        if usesQdrant(context) {
            lines.append("VECTOR_DB='qdrant'")
            lines.append("QDRANT_ENDPOINT='\(AIServicesNetwork.url(QdrantService.container, QdrantService.apiPort))'")
        } else {
            lines.append("VECTOR_DB='lancedb'")
        }
        switch modelSource(context) {
        case .gateway:
            lines.append("LLM_PROVIDER='litellm'")
            lines.append("LITE_LLM_BASE_PATH='\(AIServicesNetwork.url(LiteLLMService.container, LiteLLMService.containerPort))'")
        case .engine:
            lines.append("LLM_PROVIDER='ollama'")
            lines.append("OLLAMA_BASE_PATH='\(AIServicesNetwork.url(OllamaService.container, OllamaService.apiPort))'")
        case nil:
            break
        }
        return lines
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.anythingLLMPath
        let env = Self.envPath(context)
        var secretLines: [String] = []
        if usesQdrant(context) {
            secretLines.append(SharedSecrets.ensureSection(path: QdrantService.apiKeyPath))
        }
        if modelSource(context) == .gateway {
            secretLines.append(LiteLLMService.appKeySection(.anythingLLM))
        }
        let secrets = secretLines.isEmpty ? "" : "\n" + secretLines.joined(separator: "\n")

        var generated = [
            #"printf "SIG_KEY='%s'\n" "$(openssl rand -hex 32)""#,
            #"printf "SIG_SALT='%s'\n" "$(openssl rand -hex 32)""#,
            #"printf "JWT_SECRET='%s'\n" "$(openssl rand -hex 32)""#
        ]
        if usesQdrant(context) {
            generated.append(#"printf "QDRANT_API_KEY='%s'\n" "$(cat '\#(QdrantService.apiKeyPath)')""#)
        }
        if modelSource(context) == .gateway {
            generated.append(#"printf "LITE_LLM_API_KEY='%s'\n" "$(cat '\#(LiteLLMService.appKeyPath(.anythingLLM))')""#)
        }
        let generatedBlock = generated.map { "      \($0)" }.joined(separator: "\n")
        let seeded = seededSettings(context).joined(separator: "\n")

        return [
            #"""
            log "AnythingLLM: \#(L10nServices.serviceStarting(context.language))"
            install -d -m 755 \#(path)
            # The image runs as uid 1000 and does not chown its own mounts.
            install -d -m 700 -o 1000 -g 1000 \#(path)/storage\#(secrets)
            # Seeded ONCE and never rewritten: what the deployment derived is
            # a starting point, and the settings somebody changes in the UI
            # are written back into this same file. A re-install that rewrote
            # it would silently undo them.
            if [ ! -s '\#(env)' ]; then
              ( umask 077
                cat > '\#(env)' <<'EOF_ANYTHINGLLM_ENV'
            \#(seeded)
            EOF_ANYTHINGLLM_ENV
                {
            \#(generatedBlock)
                } >> '\#(env)'
              )
            fi
            chown 1000:1000 '\#(env)'
            chmod 600 '\#(env)'
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
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
            #"echo "AnythingLLM:  https://\#(hostname(context))""#,
            #"echo "  \#(L10nServices.anythingLLMAdminWarning(lang))""#
        ]
        if modelSource(context) == nil {
            lines.append(#"echo "  \#(L10nServices.anythingLLMNoModelNote(lang))""#)
        }
        lines.append(#"echo "  \#(L10nServices.anythingLLMSettingsNote(lang))""#)
        return [lines.joined(separator: "\n")]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.anythingLLMPath
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
                    dataPath: path,
                    databases: [],
                    // SQLite and a vector index, both written continuously.
                    quiesceServices: [Self.container],
                    encryptsByDefault: true,
                    sizePaths: [path]
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
            configDirectory: context.settings.anythingLLMPath,
            dataPaths: ["\(context.settings.anythingLLMPath).pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}
