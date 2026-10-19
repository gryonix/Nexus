public struct HomepageService: ManagedService {
    public static let composeProject = "homepage"
    public static let container = "homepage"
    public static let webUIPort = 8093
    public static let containerWebPort = 3000
    public static let wrapperTarget = ServiceID.homepage.rawValue
    /// Exact pinned tag
    public static let image = "ghcr.io/gethomepage/homepage:v1.4.5"

    public let id = ServiceID.homepage
    public let displayName = "Homepage"
    public let systemImage = "square.grid.2x2"
    public let category = ServiceCategory.dashboard
    public let usesSharedAdminLogin = false
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    /// A small Next.js server
    public let resources = ServiceResources(memoryMB: 256, diskGB: 1)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.homepageHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.homepage, context) : custom
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.homepagePath
        let allowed = context.servedHostnames(of: hostname(context)).joined(separator: ",")
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              homepage:
                image: \(Self.image)
                container_name: \(Self.container)
                restart: unless-stopped
                environment:
                  # Read out of the image's own middleware, not its docs: a
                  # request whose Host is not in this list is answered with
                  # HTTP 400 and nothing else. Caddy forwards the real Host,
                  # so every name of the site belongs here.
                  HOMEPAGE_ALLOWED_HOSTS: \(allowed)
                volumes:
                  - \(path)/config:/app/config
                ports:
                  - "127.0.0.1:\(Self.webUIPort):\(Self.containerWebPort)"
            """
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.homepagePath
        let lang = context.language
        return [
            #"""
            log "Homepage: \#(L10nServices.serviceStarting(lang))"
            install -d -m 755 \#(path)/config
            cd \#(path)
            """#,
            #"""
            # The derived half of the configuration. Rewritten every run — a
            # start page that stopped listing a service installed last week is
            # the failure this service exists to prevent. Everything else in
            # the directory belongs to the owner and is created ONLY if absent.
            backup \#(path)/config/services.yaml
            cat > \#(path)/config/services.yaml <<'EOF_HOMEPAGE_SERVICES'
            \#(servicesYAML(context))
            EOF_HOMEPAGE_SERVICES
            backup \#(path)/config/settings.yaml
            cat > \#(path)/config/settings.yaml <<'EOF_HOMEPAGE_SETTINGS'
            \#(settingsYAML(context))
            EOF_HOMEPAGE_SETTINGS
            # Homepage refuses to start without these files existing at all, so
            # they are created empty — and never rewritten, because from the
            # first edit on they are somebody's own page.
            for f in bookmarks.yaml widgets.yaml docker.yaml; do
              if [ ! -f "\#(path)/config/$f" ]; then
                printf '%s\n' '---' > "\#(path)/config/$f"
              fi
            done
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#
        ]
    }

    public func servicesYAML(_ context: ServiceContext) -> String {
        var lines = ["---"]
        for category in ServiceRegistry.categories {
            let shelf = ServiceRegistry.services(in: category)
                + ServiceRegistry.services(in: .implicit).filter { $0.displayCategory == category }
            let members = shelf.filter { service in
                service.id != id
                    && context.installedServices.contains(service.id)
                    && service.webIngress(context) != nil
            }
            guard !members.isEmpty else { continue }
            lines.append("- \(yamlScalar(category.title)):")
            for service in members {
                guard let ingress = service.webIngress(context) else { continue }
                lines.append("    - \(yamlScalar(service.displayName)):")
                lines.append("        href: https://\(ingress.hostname)")
                lines.append("        description: \(yamlScalar(category.summary))")
            }
        }
        return lines.joined(separator: "\n")
    }

    public func settingsYAML(_ context: ServiceContext) -> String {
        """
        ---
        title: \(yamlScalar(context.domain))
        headerStyle: boxed
        layout:
          \(ServiceRegistry.categories
            .filter { category in
                context.installedServices.contains { service in
                    guard service != id, let member = ServiceRegistry.service(service),
                          member.webIngress(context) != nil else { return false }
                    return member.displayCategory == category
                }
            }
            .map { "\(yamlScalar($0.title)):\n    style: row\n    columns: 3" }
            .joined(separator: "\n  "))
        """
    }

    /// A YAML scalar that cannot be read as anything else
    public func yamlScalar(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
    }

    /// Nothing
    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { [] }

    public func webIngress(_ context: ServiceContext) -> WebIngress? {
        WebIngress(hostname: hostname(context), upstreamPort: Self.webUIPort)
    }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.homepagePath
        let lang = context.language
        return [#"""
        echo "Homepage: https://\#(hostname(context))"
        echo "  \#(L10nServices.homepageGeneratedNote(lang)): \#(path)/config/services.yaml"
        echo "  \#(L10nServices.homepageOwnEditsNote(lang)): \#(path)/config/bookmarks.yaml"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.homepagePath
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
                    dataPath: "\(path)/config",
                    databases: [],
                    quiesceServices: [],
                    encryptsByDefault: false,
                    sizePaths: ["\(path)/config"]
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
            configDirectory: context.settings.homepagePath,
            dataPaths: ["\(context.settings.homepagePath)/config.pre-restore-*"],
            backupDirs: [context.backupDirectory(for: id)]
        )
    }
}
