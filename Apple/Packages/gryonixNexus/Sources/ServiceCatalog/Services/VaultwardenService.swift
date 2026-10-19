/// Vaultwarden (Bitwarden-compatible password store) as a single-container
/// compose project behind the shared Caddy ingress. Fully configured by the
/// setup script: domain, signups policy and an admin token generated on the
/// server — nothing to edit after the run.
public struct VaultwardenService: ManagedService {
    public static let composeProject = "vaultwarden"
    public static let composeDirectory = "/opt/vaultwarden"
    public static let webUIPort = 8082
    /// Paths the Bitwarden apps use
    public static let bitwardenAPIPaths = ["/api/*", "/identity/*", "/notifications/*", "/icons/*", "/attachments/*",
                                             "/.well-known/*", "/alive", "/app-id.json"]
    /// Legacy path pinned by the original spec's sudoers list
    public static let image = "vaultwarden/server:latest"

    public let id = ServiceID.vaultwarden
    public let displayName = "Vaultwarden"
    public let systemImage = "key"
    public let category = ServiceCategory.passwords
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)

    public init() {}

    public func hostname(_ context: ServiceContext) -> String {
        let custom = context.settings.vaultwardenHostname
        return custom.isEmpty
            ? ServiceDefaultHostnames.hostname(.vaultwarden, context) : custom
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let container = context.settings.vaultwardenContainer
        let dataPath = context.settings.vaultwardenDataPath
        let signups = context.settings.vaultwardenAllowSignups ? "true" : "false"
        return ComposeFile(
            directory: Self.composeDirectory,
            composeContents: """
            services:
              vaultwarden:
                image: \(Self.image)
                container_name: \(container)
                restart: unless-stopped
                environment:
                  DOMAIN: "https://\(hostname(context))"
                  SIGNUPS_ALLOWED: "\(signups)"
                  ADMIN_TOKEN: ${ADMIN_TOKEN}
                  IP_HEADER: X-Forwarded-For
                volumes:
                  - \(dataPath):/data
                ports:
                  - "127.0.0.1:\(Self.webUIPort):80"
            """,
            envTemplate: """
            ADMIN_TOKEN=__RANDOM__
            """
        )
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let signups = context.settings.vaultwardenAllowSignups ? "true" : "false"
        let dataPath = context.settings.vaultwardenDataPath
        let container = context.settings.vaultwardenContainer
        return [#"""
        log "Vaultwarden: \#(L10nServices.serviceStarting(context.language))"
        cd /opt/vaultwarden
        VW_CONFIG="\#(dataPath)/config.json"
        VW_DOMAIN="https://\#(hostname(context))"
        VW_RESTART=0
        if [ -f "$VW_CONFIG" ]; then
          # The stored domain is only compared when the key is present: absent
          # means the compose environment still rules and needs no rewrite. When
          # it IS present it outranks env, so a reinstall onto another domain
          # would keep serving links to the old one.
          if ! jq -e --arg d "$VW_DOMAIN" \
               '.signups_allowed == \#(signups) and ((.domain // $d) == $d)' \
               "$VW_CONFIG" >/dev/null 2>&1; then
            VW_TMP="$(mktemp)"
            jq --arg d "$VW_DOMAIN" \
               '.signups_allowed = \#(signups) | if has("domain") then .domain = $d else . end' \
               "$VW_CONFIG" > "$VW_TMP"
            mv "$VW_TMP" "$VW_CONFIG"
            chmod 600 "$VW_CONFIG"
            VW_RESTART=1
          fi
        fi
        docker compose -p \#(Self.composeProject) pull -q
        docker compose -p \#(Self.composeProject) up -d
        if [ "$VW_RESTART" = "1" ]; then
          docker restart \#(container)
        fi
        """#]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { [] }

    public func webIngress(_ context: ServiceContext) -> WebIngress? {
        WebIngress(hostname: hostname(context), upstreamPort: Self.webUIPort,
                   publicPaths: Self.bitwardenAPIPaths)
    }

    public func dnsHostnames(_ context: ServiceContext) -> [String] {
        [hostname(context)]
    }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let signups = context.settings.vaultwardenAllowSignups
        let lang = context.language
        return [#"""
        echo "Vaultwarden:  https://\#(hostname(context))"
        echo "  \#(L10nServices.adminPanelLabel(lang)): https://\#(hostname(context))/admin"
        echo "  \#(L10nServices.vaultwardenAdminTokenLabel(lang)): $(grep '^ADMIN_TOKEN=' /opt/vaultwarden/.env | cut -d= -f2-)"
        echo "  \#(L10nServices.vaultwardenRegisterNote(lang))"
        echo "  \#(signups ? L10nServices.vaultwardenSignupsOpen(lang) : L10nServices.vaultwardenSignupsClosed(lang))"
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let container = context.settings.vaultwardenContainer
        return ServiceActions(
            statusProbe: .container(
                name: container,
                list: PrivilegedCommand(binaryPath: "/usr/bin/docker", arguments: "ps -a")
            ),
            restart: ServicePower.container(container, "restart", timeoutClass: .restart),
            start: ServicePower.container(container, "start", timeoutClass: .restart),
            stop: ServicePower.container(container, "stop", timeoutClass: .restart),
            backup: .encryptedVolume(
                container: container,
                dataPath: context.settings.vaultwardenDataPath,
                backupDir: context.settings.vaultwardenBackupDir,
                stopStart: EncryptedVolumeCommands(
                    stop: PrivilegedCommand(binaryPath: "/usr/bin/docker",
                                            arguments: "stop \(container)"),
                    start: PrivilegedCommand(binaryPath: "/usr/bin/docker",
                                             arguments: "start \(container)")
                )
            ),
            restore: RestoreSpec(
                wrapperTarget: "vaultwarden",
                backupDir: context.settings.vaultwardenBackupDir,
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
            configDirectory: Self.composeDirectory,
            dataPaths: [context.settings.vaultwardenDataPath,
                        "\(context.settings.vaultwardenDataPath).pre-restore-*"],
            backupDirs: [context.settings.vaultwardenBackupDir],
            postSteps: ["rm -f /opt/vaultwarden-update.sh /opt/vaultwarden-update.sh.bak.* || true"]
        )
    }
}
