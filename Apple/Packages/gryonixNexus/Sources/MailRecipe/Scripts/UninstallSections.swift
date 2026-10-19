import gryonixNexusCore
import ServiceCatalog

/// Generates the root-owned uninstall wrapper
enum UninstallSections {
    static let scriptPath = "/opt/gryonixnexus-uninstall.sh"
    static let doneMarker = "GRYONIXNEXUS_UNINSTALL_DONE"
    static let vpnTarget = "vpn"
    static let allTarget = "--all"
    static let purgeDataFlag = "--purge-data"
    static let purgeBackupsFlag = "--purge-backups"

    static func quotedPath(_ path: String) -> String {
        path.split(separator: "*", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "'\($0)'" }
            .joined(separator: "*")
    }

    static func purgeBlock(_ spec: UninstallSpec, indent: String) -> [String] {
        var lines: [String] = []
        let dataTargets = ([spec.configDirectory].compactMap { $0 }) + spec.dataPaths
        if !dataTargets.isEmpty {
            lines.append("\(indent)if [ \"$PURGE_DATA\" -eq 1 ]; then")
            for target in dataTargets { lines.append("\(indent)  purge_path \(quotedPath(target))") }
            lines.append("\(indent)fi")
        }
        if !spec.backupDirs.isEmpty {
            lines.append("\(indent)if [ \"$PURGE_BACKUPS\" -eq 1 ]; then")
            for target in spec.backupDirs { lines.append("\(indent)  rm -rf \(quotedPath(target))") }
            lines.append("\(indent)fi")
        }
        return lines
    }

    private static func sudoersOwners(_ services: [any ManagedService],
                                      context: ServiceContext) -> [String: Set<ServiceID>] {
        var owners: [String: Set<ServiceID>] = [:]
        for service in services {
            for line in service.sudoersLines(context) {
                owners[line, default: []].insert(service.id)
            }
        }
        return owners
    }

    private static func removableSudoersLines(for unit: [any ManagedService],
                                               owners: [String: Set<ServiceID>],
                                               context: ServiceContext) -> [String] {
        let unitIDs = Set(unit.map(\.id))
        var seen = Set<String>()
        var result: [String] = []
        for service in unit {
            for line in service.sudoersLines(context) {
                guard seen.insert(line).inserted else { continue }
                guard let owningIDs = owners[line], owningIDs.subtracting(unitIDs).isEmpty else { continue }
                result.append(line)
            }
        }
        return result
    }

    private static func sudoersRemovalCall(_ lines: [String]) -> [String] {
        guard !lines.isEmpty else { return [] }
        let quoted = lines.map { "'\($0)'" }
        return ["  remove_sudoers_lines \\", "    " + quoted.joined(separator: " \\\n    ")]
    }

    /// The bash function body removing one service, from its UninstallSpec
    private static func uninstallFunction(name: String, spec: UninstallSpec,
                                          siteHeaders: [String], sudoersLines: [String] = []) -> String {
        var lines: [String] = ["uninstall_\(name)() {"]
        for step in spec.preSteps { lines.append("  \(step)") }
        if let project = spec.composeProject {
            lines.append("  compose_down '\(project)'")
        }
        for header in siteHeaders {
            lines.append("  remove_caddy_site '\(header)'")
        }
        for step in spec.postSteps { lines.append("  \(step)") }
        lines += purgeBlock(spec, indent: "  ")
        lines += sudoersRemovalCall(sudoersLines)
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private static func functionName(_ id: ServiceID) -> String {
        id.rawValue.replacingOccurrences(of: "-", with: "_")
    }

    private static func siteHeaders(_ service: any ManagedService,
                                    context: MailContext) -> [String] {
        guard let ingress = service.webIngress(context.serviceContext) else { return [] }
        let names = ([ingress.hostname] + context.mirroredHostnames(of: ingress.hostname))
            .joined(separator: ", ")
        return [names]
    }

    static func servicesHostWrapper(_ access: DashboardAccessInput, context: MailContext,
                                    includeWireGuard: Bool) -> String {
        let serviceContext = context.serviceContext
        var sudoersContext = serviceContext
        sudoersContext.sshUser = access.sshUser
        let services = context.allSelectedServices
        let vpnServices = services.filter {
            ServiceID.vpnProtocols.contains($0.id) || $0.id == .vpnPanel
        }
        let meshServices = services.filter { $0.id == .headscale || $0.id == .tailscaleNode }
        let appServices = services.filter {
            !ServiceID.vpnProtocols.contains($0.id) && $0.id != .vpnPanel
                && $0.id != .headscale && $0.id != .tailscaleNode
        }

        var functions: [String] = []
        var caseArms: [String] = []
        var allCalls: [String] = []

        let sudoersOwnersByLine = sudoersOwners(services, context: sudoersContext)

        for service in appServices {
            let name = functionName(service.id)
            functions.append(uninstallFunction(name: name,
                                               spec: service.uninstallSpec(serviceContext),
                                               siteHeaders: siteHeaders(service, context: context),
                                               sudoersLines: removableSudoersLines(for: [service],
                                                                                   owners: sudoersOwnersByLine,
                                                                                   context: sudoersContext)))
            caseArms.append("  \(service.id.rawValue)) uninstall_\(name) ;;")
            allCalls.append("  uninstall_\(name)")
        }

        if !meshServices.isEmpty {
            var meshLines: [String] = ["uninstall_headscale() {"]
            var seenProjects = Set<String>()
            for service in meshServices {
                let spec = service.uninstallSpec(serviceContext)
                for step in spec.preSteps { meshLines.append("  \(step)") }
                if let project = spec.composeProject, seenProjects.insert(project).inserted {
                    meshLines.append("  compose_down '\(project)'")
                }
                for header in siteHeaders(service, context: context) {
                    meshLines.append("  remove_caddy_site '\(header)'")
                }
                for step in spec.postSteps { meshLines.append("  \(step)") }
            }
            for service in meshServices {
                meshLines += purgeBlock(service.uninstallSpec(serviceContext), indent: "  ")
            }
            meshLines += sudoersRemovalCall(removableSudoersLines(for: meshServices,
                                                                   owners: sudoersOwnersByLine,
                                                                   context: sudoersContext))
            meshLines.append("}")
            functions.append(meshLines.joined(separator: "\n"))
            caseArms.append("  \(ServiceID.headscale.rawValue)) uninstall_headscale ;;")
            allCalls.append("  uninstall_headscale")
        }

        if !vpnServices.isEmpty {
            var vpnLines: [String] = ["uninstall_vpn() {"]
            var seenProjects = Set<String>()
            for service in vpnServices {
                let spec = service.uninstallSpec(serviceContext)
                for step in spec.preSteps { vpnLines.append("  \(step)") }
                if let project = spec.composeProject, seenProjects.insert(project).inserted {
                    vpnLines.append("  compose_down '\(project)'")
                }
                for header in siteHeaders(service, context: context) {
                    vpnLines.append("  remove_caddy_site '\(header)'")
                }
                for step in spec.postSteps { vpnLines.append("  \(step)") }
            }
            for service in vpnServices {
                vpnLines += purgeBlock(service.uninstallSpec(serviceContext), indent: "  ")
            }
            vpnLines += sudoersRemovalCall(removableSudoersLines(for: vpnServices,
                                                                  owners: sudoersOwnersByLine,
                                                                  context: sudoersContext))
            vpnLines.append("}")
            functions.append(vpnLines.joined(separator: "\n"))
            caseArms.append("  \(vpnTarget)) uninstall_vpn ;;")
            allCalls.append("  uninstall_vpn")
        }

        let tunnelCleanup = includeWireGuard ? """
        \(TunnelWatchdogSections.uninstallLines(indent: "  ").joined(separator: "\n"))
          systemctl disable --now wg-quick@\(WireGuardDefaults.interfaceName) >/dev/null 2>&1 || true
          rm -f '/etc/wireguard/\(WireGuardDefaults.interfaceName).conf'
          # The oneshot that pinned the relay outside the tunnel. Stopping it
          # takes the route with it (ExecStop), and the unit goes the way every
          # other root-owned file this product wrote goes — the DDNS lesson.
          systemctl disable --now gryonixnexus-tunnel-endpoint.service >/dev/null 2>&1 || true
          rm -f /etc/systemd/system/gryonixnexus-tunnel-endpoint.service
          systemctl daemon-reload || true
          rm -f /etc/ssh/sshd_config.d/60-gryonixnexus-tunnel.conf
          systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
        \(RelayRouteSyncSections.uninstallLines(indent: "  ").joined(separator: "\n"))
          rm -f /etc/sysctl.d/99-gryonixnexus-rpfilter.conf
        """ : ""

        let script = """
        #!/bin/bash
        # Managed by gryonixNexus — remove services or the whole gryonixNexus install.
        # Usage: gryonixnexus-uninstall.sh <service|\(vpnTarget)|\(allTarget)> [\(purgeDataFlag)] [\(purgeBackupsFlag)]
        # Default keeps data and backups on disk; the flags delete them (independently).
        set -euo pipefail

        TARGET="${1:-}"
        PURGE_DATA=0
        PURGE_BACKUPS=0
        shift || true
        for arg in "$@"; do
          case "$arg" in
            \(purgeDataFlag)) PURGE_DATA=1 ;;
            \(purgeBackupsFlag)) PURGE_BACKUPS=1 ;;
          esac
        done

        compose_down() {
          if [ "$PURGE_DATA" -eq 1 ]; then
            # --rmi all also reclaims the images, but only the ones THIS
            # project's services use — the scoped replacement for the
            # `docker system prune -af` that used to run once at the end and
            # took every unused image and stopped container on the host with
            # it, ours or not. Images still referenced elsewhere are skipped
            # by docker itself.
            docker compose -p "$1" down --remove-orphans --volumes --rmi all >/dev/null 2>&1 || true
          else
            docker compose -p "$1" down --remove-orphans >/dev/null 2>&1 || true
          fi
        }

        # Unmounts fast storage bound inside each path, then deletes it.
        purge_path() {
          local target mount source
          for target in "$@"; do
            [ -e "$target" ] || continue
            while read -r mount; do
              source="$(awk -v m="$mount" '$2 == m && $3 == "none" {print $1}' /etc/fstab)"
              umount "$mount" 2>/dev/null || true
              sed -i "\\|[[:space:]]${mount}[[:space:]]none[[:space:]]|d" /etc/fstab
              if [ -n "$source" ]; then rm -rf "$source"; fi
            done < <(awk -v t="$target/" 'index($2, t) == 1 {print $2}' /proc/mounts | sort -r)
            rm -rf "$target"
          done
        }

        # Removes one site block from the Caddyfile. The header is the exact
        # first line of the block as writeCaddyfile emits it (top-level `}` on
        # its own line closes it) — wrapper and Caddyfile are regenerated
        # together on every setup run, so the format cannot drift between them.
        remove_caddy_site() {
          local f=/etc/caddy/Caddyfile
          [ -f "$f" ] || return 0
          awk -v start="$1 {" '
            $0 == start {skip=1; next}
            skip && $0 == "}" {skip=0; next}
            !skip {print}
          ' "$f" > "$f.gryonixnexus" && mv "$f.gryonixnexus" "$f"
          systemctl reload caddy 2>/dev/null || true
        }

        # Drops exactly the sudoers lines named — baked in by the generator
        # from the SAME sudoersLines a service was whitelisted with, never
        # rediscovered here. Staged and validated with visudo, the same way
        # the whitelist is written: a set of lines that fails to parse (should
        # never happen — they are asked in the format already on disk) leaves
        # the whitelist untouched rather than risk one sudo cannot read.
        remove_sudoers_lines() {
          local f=/etc/sudoers.d/gryonixnexus-control
          [ -f "$f" ] || return 0
          local tmp="$f.gryonixnexus"
          printf '%s\\n' "$@" | grep -vFxf - "$f" > "$tmp" || true
          if [ -s "$tmp" ] && visudo -cf "$tmp" >/dev/null 2>&1; then
            mv "$tmp" "$f"
          else
            rm -f "$tmp"
          fi
        }

        \(functions.joined(separator: "\n\n"))

        uninstall_all() {
        \(allCalls.joined(separator: "\n"))
        \(UpdateControlSections.uninstallLines(indent: "  ").joined(separator: "\n"))
        \(BackupControlSections.uninstallLines(indent: "  ").joined(separator: "\n"))
        \(dynamicDNSUninstallLines(indent: "  ").joined(separator: "\n"))
        \(agentRemoval(indent: "  ").joined(separator: "\n"))
          # Host metrics collector + its history
          systemctl disable --now gryonixnexus-metrics >/dev/null 2>&1 || true
          rm -f /etc/systemd/system/gryonixnexus-metrics.service /opt/gryonixnexus-metrics-collector.sh
          systemctl daemon-reload || true
          rm -rf /var/lib/gryonixnexus
          # Caddy: only the sites this app wrote are removed
          rest="$(mktemp)"
          { [ -f /etc/caddy/Caddyfile ] && awk '
            BEGIN{d=0;b="";own=0}
            d==0&&b==""&&index($0,"{")==0{print;next}
            {b=b $0 "\\n"; if(index($0,"# gryonixnexus:"))own=1; t=$0; o=gsub(/[{]/,"",t); t=$0; c=gsub(/[}]/,"",t); d+=o-c;
             if(d<=0){ if(!own) printf "%s",b; b=""; own=0; d=0}}
            END{printf "%s",b}' /etc/caddy/Caddyfile > "$rest"; } || : > "$rest"
          if grep -Eq '^[^#[:space:]{}].*[{][[:space:]]*$' "$rest"; then
            cat "$rest" > /etc/caddy/Caddyfile
            { caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1 && systemctl reload caddy >/dev/null 2>&1; } || true
          else
            systemctl disable --now caddy >/dev/null 2>&1 || true
            rm -f /etc/caddy/Caddyfile
          fi
          rm -f "$rest" '\(VPNPanelService.adminGuardPath)'
        \(tunnelCleanup)
          # No host-wide `docker system prune` here: image reclamation is done
          # per compose project by compose_down --rmi all, which cannot
          # reach Docker state this deployment did not create.
          # Dashboard wrappers, then our own whitelist last — after this line
          # the app's sudo access is gone, which is the point.
          rm -f '\(DashboardAccessSections.containerControlScriptPath)' '\(DashboardAccessSections.restoreScriptPath)'
          # The agent bootstrap wrapper and whatever sources it unpacked. A
          # root-owned script the erase leaves behind is the DDNS lesson: the
          # erased machine still carrying something only root can remove.
          rm -f '\(AgentBootstrapSections.scriptPath)'
          rm -rf '\(AgentBootstrapSections.unpackRoot)'
        \(backupCopyRemoval(indent: "  ", globs: homeBackupCopyGlobs))
        \(DashboardAccessSections.passwordAuthCloseUninstallLines(indent: "  ").joined(separator: "\n"))
        \(appKeyRemoval(access))
          rm -f /etc/sudoers.d/gryonixnexus-control
          rm -f '\(scriptPath)'
        }

        case "$TARGET" in
        \(caseArms.joined(separator: "\n"))
          \(allTarget)) uninstall_all ;;
          *) echo "unsupported target: ${TARGET}" >&2; exit 2 ;;
        esac
        echo '\(doneMarker)'
        """
        return installSection(script: script, language: context.language)
    }

    static func vpsWrapper(_ access: DashboardAccessInput, language: AppLanguage) -> String {
        let script = """
        #!/bin/bash
        # Managed by gryonixNexus — remove the gryonixNexus install from this relay.
        # Usage: gryonixnexus-uninstall.sh \(allTarget)
        set -euo pipefail

        TARGET="${1:-}"
        if [ "$TARGET" != "\(allTarget)" ]; then
          echo "unsupported target: ${TARGET}" >&2; exit 2
        fi

        systemctl disable --now wg-quick@\(WireGuardDefaults.interfaceName) >/dev/null 2>&1 || true
        rm -f '/etc/wireguard/\(WireGuardDefaults.interfaceName).conf'
        rm -f /etc/sysctl.d/99-gryonixnexus-forwarding.conf
        \(agentRemoval(indent: "").joined(separator: "\n"))
        systemctl disable --now gryonixnexus-metrics >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/gryonixnexus-metrics.service /opt/gryonixnexus-metrics-collector.sh
        systemctl daemon-reload || true
        rm -rf /var/lib/gryonixnexus
        \(UpdateControlSections.uninstallLines(indent: "").joined(separator: "\n"))
        \(BackupControlSections.uninstallLines(indent: "").joined(separator: "\n"))
        \(dynamicDNSUninstallLines(indent: "").joined(separator: "\n"))
        \(backupCopyRemoval(indent: "", globs: vpsBackupCopyGlobs))
        \(DashboardAccessSections.passwordAuthCloseUninstallLines(indent: "").joined(separator: "\n"))
        \(appKeyRemoval(access))
        rm -f /etc/sudoers.d/gryonixnexus-control
        rm -f '\(scriptPath)'
        echo '\(doneMarker)'
        """
        return installSection(script: script, language: language)
    }

    /// Paths the control-plane agent's bootstrap puts on a host
    private static let agentUnit = "gryonixnexusd.service"
    private static let agentBinaryPath = "/usr/local/bin/gryonixnexusd"
    private static let agentSocketPath = "/run/gryonixnexusd.sock"
    private static let agentStateDirectory = "/var/lib/gryonixnexus/agent"
    private static let agentMDNSUnit = "gryonixnexus-mdns.service"
    private static let agentMDNSScript = "/usr/local/lib/gryonixnexus/mdns-aliases.sh"
    private static let agentHomeNetworkSnippet = "/etc/caddy/gryonixnexus-home-network.caddy"
    private static let predecessorUnit = "gryonixnexus.service"
    private static let predecessorBinaryPath = "/usr/local/bin/gryonixd"
    private static let predecessorSocketPath = "/run/gryonixd.sock"

    /// Dynamic DNS: the updater, its units and its configuration
    static func dynamicDNSUninstallLines(indent: String) -> [String] {
        [
            "\(indent)# Dynamic DNS: the timer is armed by the panel long after setup,",
            "\(indent)# so it outlives the services unless it is stopped here.",
            "\(indent)systemctl disable --now 'gryonixnexus-ddns.timer' >/dev/null 2>&1 || true",
            "\(indent)rm -f /etc/systemd/system/gryonixnexus-ddns.timer /etc/systemd/system/gryonixnexus-ddns.service",
            "\(indent)rm -f '/etc/gryonixnexus/ddns.conf' '/var/lib/gryonixnexus/ddns-status.txt'",
            "\(indent)rm -f '/opt/gryonixnexus-ddns.sh'",
        ]
    }

    private static func agentRemoval(indent: String) -> [String] {
        func unitRemoval(unit: String, binary: String, socket: String) -> [String] {
            [
                "\(indent)if [ -f /etc/systemd/system/\(unit) ]; then",
                "\(indent)  systemctl disable --now '\(unit)' >/dev/null 2>&1 || true",
                "\(indent)  rm -f '/etc/systemd/system/\(unit)'",
                "\(indent)  systemctl daemon-reload || true",
                "\(indent)fi",
                "\(indent)rm -f '\(binary)' '\(socket)'"
            ]
        }
        return [
            "\(indent)# Control-plane agent: installed by its own bootstrap, outside this",
            "\(indent)# setup, and therefore invisible to everything else here. Stopped",
            "\(indent)# before the state directory below is removed — the unit's",
            "\(indent)# StateDirectory= re-creates it on every start."
        ]
            + unitRemoval(unit: agentUnit, binary: agentBinaryPath, socket: agentSocketPath)
            + [
                "\(indent)rm -rf '\(agentStateDirectory)'",
                "\(indent)# The agent's mDNS names and home-network doors.",
                "\(indent)systemctl disable --now '\(agentMDNSUnit)' >/dev/null 2>&1 || true",
                "\(indent)rm -f '/etc/systemd/system/\(agentMDNSUnit)' '\(agentMDNSScript)' '\(agentHomeNetworkSnippet)'",
                "\(indent)# The agent's system updater and its start and shutdown units.",
                "\(indent)systemctl disable --now 'gryonixnexus-update-at-start.service' >/dev/null 2>&1 || true",
                "\(indent)rm -f '/etc/gryonixnexus/update-at-start.conf'",
                "\(indent)systemctl disable --now 'gryonixnexus-update-at-stop.service' >/dev/null 2>&1 || true",
                "\(indent)systemctl disable --now 'gryonixnexus-system-scheduled.timer' >/dev/null 2>&1 || true",
                "\(indent)rm -f '/opt/gryonixnexus-system-ctl.sh' '/etc/systemd/system/gryonixnexus-update-at-start.service' '/etc/systemd/system/gryonixnexus-update-at-stop.service' '/var/log/gryonixnexus-system-update.log'",
                "\(indent)rm -f '/etc/systemd/system/gryonixnexus-system-scheduled.timer' '/etc/systemd/system/gryonixnexus-system-scheduled.service' '/etc/gryonixnexus/system-schedule.conf'",
                "\(indent)# The daemon before the rename (gryonixd). install-agent.sh removes",
                "\(indent)# it, but a host that never re-ran the bootstrap still has it, and",
                "\(indent)# its unit is Restart=always too.",
            ]
            + unitRemoval(unit: predecessorUnit,
                          binary: predecessorBinaryPath,
                          socket: predecessorSocketPath)
    }

    /// Removes the `<path>.bak.<epoch>` copies the setup leaves behind
    private static func backupCopyRemoval(indent: String, globs: [String]) -> String {
        [
            "\(indent)# Backup copies the setup makes before overwriting a managed file.",
            "\(indent)rm -f \(globs.joined(separator: " ")) || true"
        ].joined(separator: "\n")
    }

    private static let sharedBackupCopyGlobs = [
        "/etc/nftables.conf.bak.*",
        "/etc/wireguard/wg0.conf.bak.*",
        "/etc/systemd/system/gryonixnexus-*.service.bak.*"
    ]

    /// Managed-file backup copies on the host that runs the services
    private static let homeBackupCopyGlobs = sharedBackupCopyGlobs + [
        "/opt/gryonixnexus-*.bak.*",
        "/opt/vaultwarden-update.sh.bak.*",
        "/etc/caddy/Caddyfile.bak.*",
        "/etc/systemd/system/gryonixnexus-*.timer.bak.*",
        "/etc/sysctl.d/99-gryonixnexus-rpfilter.conf.bak.*"
    ]

    private static let vpsBackupCopyGlobs = sharedBackupCopyGlobs + [
        "/opt/gryonixnexus-*.bak.*",
        "/etc/sysctl.d/99-gryonixnexus-forwarding.conf.bak.*"
    ]

    private static func appKeyRemoval(_ access: DashboardAccessInput) -> String {
        guard access.createUser else { return "  :" }
        return """
          APP_KEY='\(access.appPublicKey)'
          USER_HOME="$(getent passwd '\(access.sshUser)' | cut -d: -f6 || true)"
          if [ -n "$USER_HOME" ] && [ -f "$USER_HOME/.ssh/authorized_keys" ]; then
            grep -vxF "$APP_KEY" "$USER_HOME/.ssh/authorized_keys" > "$USER_HOME/.ssh/authorized_keys.gryonixnexus" || true
            mv "$USER_HOME/.ssh/authorized_keys.gryonixnexus" "$USER_HOME/.ssh/authorized_keys"
            chmod 600 "$USER_HOME/.ssh/authorized_keys"
            # Root wrote the replacement, and sshd reads authorized_keys as
            # the account: leaving it root-owned makes the file unreadable to
            # sshd and kills every OTHER key the account has. Same reason the
            # revoke step chowns; see revokeInstallKey.
            chown '\(access.sshUser)' "$USER_HOME/.ssh/authorized_keys"
          fi
        """
    }

    private static func installSection(script: String, language: AppLanguage) -> String {
        #"""
        log "\#(L10nScripts.uninstallWrapperLog(language))"
        \#(BashSections.writeFile(path: scriptPath, contents: script, delimiter: "EOF_UNINSTALL"))
        chmod 750 '\#(scriptPath)'
        """#
    }
}
