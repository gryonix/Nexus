import gryonixNexusCore
import ServiceCatalog

enum ServiceInfraSections {
    static func installDocker(language: AppLanguage) -> String {
        #"""
        log "\#(L10nScripts.installingDocker(language))"
        if ! command -v docker >/dev/null 2>&1; then
          curl -fsSL https://get.docker.com | sh
        fi
        systemctl enable --now docker >/dev/null 2>&1 || true
        """#
    }

    /// Installs the release .deb, verified against its sha512 list
    static func installCaddy(profile: any DistributionProfile, language: AppLanguage) -> String {
        #"""
        log "\#(L10nScripts.installingCaddy(language))"
        \#(Apt.dropRetiredSources)
        if ! command -v caddy >/dev/null 2>&1 || ! id caddy >/dev/null 2>&1; then
          caddy_arch="$(dpkg --print-architecture)"
          case "$caddy_arch" in armhf) caddy_arch=armv6 ;; armel) caddy_arch=armv5 ;; esac
          caddy_tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/caddyserver/caddy/releases/latest)"
          caddy_tag="${caddy_tag##*/}"
          caddy_deb="caddy_${caddy_tag#v}_linux_${caddy_arch}.deb"
          caddy_url="https://github.com/caddyserver/caddy/releases/download/$caddy_tag"
          caddy_tmp="$(mktemp -d)"
          curl -fsSL -o "$caddy_tmp/$caddy_deb" "$caddy_url/$caddy_deb"
          curl -fsSL -o "$caddy_tmp/sums" "$caddy_url/caddy_${caddy_tag#v}_checksums.txt"
          (cd "$caddy_tmp" && grep "  $caddy_deb\$" sums | sha512sum -c -)
          \#(Apt.quiet) install -yq --no-install-recommends --reinstall "$caddy_tmp/$caddy_deb"
          id caddy >/dev/null
          rm -rf "$caddy_tmp"
        fi
        """#
    }

    static func caddySite(owner: String, hostname: String, upstreamPort: Int,
                          adminGuard: Bool = false,
                          upstreamHTTPS: Bool = false, tlsInternal: Bool = false,
                          sso: Bool = false, publicPaths: [String] = [],
                          overwriteForwardedFor: Bool = false) -> String {
        let proxy = upstreamHTTPS
            ? #"""
            reverse_proxy https://127.0.0.1:\#(upstreamPort) {
                    header_up Host {host}
                    transport http {
                        tls_insecure_skip_verify
                    }
                }
            """#
            : (overwriteForwardedFor
               ? #"""
               reverse_proxy 127.0.0.1:\#(upstreamPort) {
                       header_up X-Forwarded-For {remote_host}
                   }
               """#
               : "reverse_proxy 127.0.0.1:\(upstreamPort)")
        let tlsLine = tlsInternal ? "tls internal\n    " : ""
        let ssoLine = sso ? AutheliaService.forwardAuthBlock(hostname: hostname) + "\n    " : ""
        let ownerLine = "# \(caddyOwnerTag) \(owner)\n    "
        let guardLine = adminGuard ? "import \(VPNPanelService.adminGuardPath)\n        " : ""
        let portal = sso ? portalPaths(owner) : []
        if !portal.isEmpty, publicPaths.isEmpty {
            return portalSplitSite(hostname: hostname, head: ownerLine + tlsLine, paths: portal,
                                   guardLine: guardLine, sso: ssoLine, proxy: proxy)
        }
        if !publicPaths.isEmpty, !portal.isEmpty {
            return #"""
            \#(hostname) {
                \#(ownerLine)\#(tlsLine)@\#(caddyPublicPathsMatcher) path \#(publicPaths.joined(separator: " "))
                @\#(portalPathsMatcher) path \#(portal.joined(separator: " "))
                handle @\#(caddyPublicPathsMatcher) {
                    \#(nested(proxy))
                }
                handle @\#(portalPathsMatcher) {
                    \#(guardLine)\#(nested(ssoLine))\#(nested(proxy))
                }
                handle {
                    \#(guardLine)\#(nested(proxy))
                }
            }
            """#
        }
        if !publicPaths.isEmpty, adminGuard || sso {
            return #"""
            \#(hostname) {
                \#(ownerLine)\#(tlsLine)@\#(caddyPublicPathsMatcher) path \#(publicPaths.joined(separator: " "))
                handle @\#(caddyPublicPathsMatcher) {
                    \#(nested(proxy))
                }
                handle {
                    \#(guardLine)\#(nested(ssoLine))\#(nested(proxy))
                }
            }
            """#
        }
        guard adminGuard else {
            return #"""
            \#(hostname) {
                \#(ownerLine)\#(tlsLine)\#(ssoLine)\#(proxy)
            }
            """#
        }
        return #"""
        \#(hostname) {
            \#(ownerLine)\#(tlsLine)import \#(VPNPanelService.adminGuardPath)
            \#(ssoLine)\#(proxy)
        }
        """#
    }

    static let caddyOwnerTag = "gryonixnexus:"

    /// Name of the matcher the public-path branch is selected by
    static let caddyPublicPathsMatcher = "gryonixnexus_open"

    /// Matcher for the paths the portal still covers
    static let portalPathsMatcher = "gryonixnexus_portal"

    /// Admin paths behind the portal; the rest signs in itself
    static func portalPaths(_ owner: String) -> [String] {
        guard owner == ServiceID.mailcow.rawValue else { return [] }
        return ["/admin", "/admin/*", "/domainadmin", "/domainadmin/*", "/rspamd", "/rspamd/*"]
    }

    /// A site whose portal covers only its admin paths
    private static func portalSplitSite(hostname: String, head: String, paths: [String],
                                        guardLine: String, sso: String, proxy: String) -> String {
        #"""
        \#(hostname) {
            \#(head)@\#(portalPathsMatcher) path \#(paths.joined(separator: " "))
            handle @\#(portalPathsMatcher) {
                \#(guardLine)\#(nested(sso))\#(nested(proxy))
            }
            handle {
                \#(guardLine)\#(nested(proxy))
            }
        }
        """#
    }

    /// One more level of indent after every line break
    private static func nested(_ block: String) -> String {
        block.replacingOccurrences(of: "\n", with: "\n    ")
    }

    /// The Caddyfile's global block
    static let caddyGlobalOptions = """
    {
    	order respond before forward_auth
    	servers {
    		protocols h1 h2
    	}
    }
    """

    static func caddyMergeProgram(indent: String) -> String {
        caddyMergeAWK
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : indent + $0 }
            .joined(separator: "\n")
    }

    /// The program `caddyMergeProgram` indents
    static let caddyMergeAWK = #"""
    function flush(   i, names, count, parts, id, line, keep) {
      if (n == 0) return
      names = block[1]
      sub(/[ \t]*\{[ \t]*$/, "", names)
      if (pass == 1) {
        if (names != "") {
          header[block[1]] = 1
          count = split(names, parts, ",")
          for (i = 1; i <= count; i++) {
            gsub(/^[ \t]+|[ \t]+$/, "", parts[i])
            mine[tolower(parts[i])] = 1
          }
        }
        n = 0
        return
      }
      keep = 1
      if (names == "") keep = 0
      else if (block[1] in header) keep = 0
      else {
        for (i = 2; i <= n; i++) {
          line = block[i]
          gsub(/^[ \t]+|[ \t]+$/, "", line)
          if (index(line, "# \#(caddyOwnerTag) ") == 1) {
            id = substr(line, length("# \#(caddyOwnerTag) ") + 1)
            gsub(/^[ \t]+|[ \t]+$/, "", id)
            if (index("," ourids ",", "," id ",") > 0) keep = 0
          }
        }
      }
      if (keep) {
        count = split(names, parts, ",")
        for (i = 1; i <= count; i++) {
          gsub(/^[ \t]+|[ \t]+$/, "", parts[i])
          if (tolower(parts[i]) in mine && !(parts[i] in seen)) {
            seen[parts[i]] = 1
            clashes = clashes (clashes == "" ? "" : ", ") parts[i]
          }
        }
        print "" > out
        for (i = 1; i <= n; i++) print block[i] > out
      }
      n = 0
    }
    # The end of a file is a block boundary too, and it is not marked by a
    # blank line: our file ends with the brace of its last site. Flushed here,
    # while `pass` still names the file the block came out of — FILENAME has
    # already moved on by the time the first line of the next one is read, and
    # reading it would file our last site as a stranger AND swallow the first
    # block of the file that follows.
    #
    # NO APOSTROPHES anywhere in this program: it is quoted into the script
    # inside single quotes, and one of them ends the program where it stands.
    # `bash -n` then reports an unterminated quote at the END of a 900-line
    # script, which says nothing about where it came from.
    FNR == 1 { flush(); pass++ }
    /^[ \t]*$/ { flush(); next }
    { block[++n] = $0 }
    END { flush(); if (clashes != "") print clashes }
    """#

    /// Writes /etc/caddy/Caddyfile from the web services and restarts Caddy
    static func writeCaddyfile(_ context: MailContext) -> String {
        let rendered = context.webServices.compactMap { service -> (id: String, block: String)? in
            guard let ingress = service.webIngress(context.serviceContext) else { return nil }
            let names = ([ingress.hostname] + context.mirroredHostnames(of: ingress.hostname))
                .joined(separator: ", ")
            let sso = context.serviceContext.installedServices.contains(.authelia)
                && AutheliaService.guards(service.id, settings: context.serviceContext.settings)
            let site = caddySite(owner: service.id.rawValue,
                                 hostname: names, upstreamPort: ingress.upstreamPort,
                                 adminGuard: ingress.adminGuard, upstreamHTTPS: ingress.upstreamHTTPS,
                                 tlsInternal: context.usesInternalTLS, sso: sso,
                                 publicPaths: ingress.publicPaths,
                                 overwriteForwardedFor: ingress.overwriteForwardedFor)
            let installed = context.serviceContext.installedServices
            return (service.id.rawValue,
                    CaddySetupGuard.guarding(site, owner: service.id.rawValue, installed: installed))
        }
        let sites = rendered.map(\.block)
        let ownedIDs = rendered.map(\.id).joined(separator: ",")
        let armed = CaddySetupGuard.armSection(
            rendered.filter { $0.block.contains(CaddySetupGuard.importLine($0.id)) }.map(\.id))
        return #"""
        log "\#(L10nScripts.caddyReverseProxyLog(context.language))"
        # Every site imports the admin guard, so the file must exist even when
        # no VPN panel installs the lockdown wrapper (empty = public; re-runs
        # keep the current state — a missing import is a fatal Caddy error).
        # Mode spelled out rather than left to the umask: caddy runs as its own
        # user and cannot read a root-only /etc/caddy at all.
        install -d -m 755 /etc/caddy
        [ -f \#(VPNPanelService.adminGuardPath) ] || : > \#(VPNPanelService.adminGuardPath)\#(armed)
        cat > /etc/caddy/Caddyfile.gryonixnexus <<'EOF_CADDYFILE'
        \#(caddyGlobalOptions + "\n\n" + sites.joined(separator: "\n\n"))
        EOF_CADDYFILE
        # Every block on this host that is NOT this deployment's, kept verbatim
        # and appended below ours. Blocks are separated by a blank line and open
        # with their names — the shape this file is written in on both routes,
        # and the one the agent splits on. A block is ours when its header is
        # one of ours or its owner line names a service of ours; the global
        # options block is dropped, because ours already carries it first.
        # Anything left claiming a name we serve stops the run: two blocks on
        # one name make Caddy refuse the whole file, which would take down every
        # site on the machine at the next restart.
        if [ -f /etc/caddy/Caddyfile ]; then
          caddy_clash=$(awk -v ourids='\#(ownedIDs)' \
                            -v out=/etc/caddy/Caddyfile.gryonixnexus-kept '
        \#(caddyMergeProgram(indent: "    "))
          ' /etc/caddy/Caddyfile.gryonixnexus /etc/caddy/Caddyfile)
          if [ -n "$caddy_clash" ]; then
            rm -f /etc/caddy/Caddyfile.gryonixnexus /etc/caddy/Caddyfile.gryonixnexus-kept
            fail "\#(L10nScripts.caddyNameAlreadyServed(context.language)): $caddy_clash"
          fi
          if [ -s /etc/caddy/Caddyfile.gryonixnexus-kept ]; then
            cat /etc/caddy/Caddyfile.gryonixnexus-kept >> /etc/caddy/Caddyfile.gryonixnexus
          fi
          rm -f /etc/caddy/Caddyfile.gryonixnexus-kept
        fi
        backup /etc/caddy/Caddyfile
        mv /etc/caddy/Caddyfile.gryonixnexus /etc/caddy/Caddyfile
        systemctl enable caddy >/dev/null 2>&1 || true
        if ! systemctl reload caddy 2>/dev/null && ! systemctl restart caddy; then
          journalctl -u caddy -n 25 --no-pager -o cat 2>/dev/null || true
          ss -ltnp 'sport = :80 or sport = :443' 2>/dev/null || true
          fail "\#(L10nScripts.caddyDidNotStart(context.language))"
        fi
        """#
    }

    static func composeSetup(_ service: any ManagedService, context: MailContext) -> String {
        guard let compose = service.composeFile(context.serviceContext) else {
            // The service manages its own install (mailcow: git clone + generate_config.sh).
            return service.setupSteps(context.serviceContext).joined(separator: "\n\n")
        }
        let tag = service.id.rawValue.uppercased().replacingOccurrences(of: "-", with: "_")
        var sections = [
            #"""
            log "\#(service.displayName): docker-compose"
            # Mode spelled out, not left to the umask: containers that drop to
            # a non-root user mount from here, and .env carries its own 600.
            install -d -m 755 \#(compose.directory)
            \#(BashSections.writeFile(path: "\(compose.directory)/docker-compose.yml", contents: compose.composeContents, delimiter: "EOF_COMPOSE_\(tag)"))
            """#
        ]
        if let envTemplate = compose.envTemplate {
            sections.append(#"""
            if [ ! -f "\#(compose.directory)/.env" ]; then
              \#(BashSections.writeFile(path: "\(compose.directory)/.env.template", contents: envTemplate, delimiter: "EOF_ENV_\(tag)"))
              while IFS= read -r line; do
                case "$line" in
                  *__RANDOM__*) printf '%s\n' "${line/__RANDOM__/$(openssl rand -hex 24)}" ;;
                  *) printf '%s\n' "$line" ;;
                esac
              done < "\#(compose.directory)/.env.template" > "\#(compose.directory)/.env"
              rm -f "\#(compose.directory)/.env.template"
            fi
            chmod 600 "\#(compose.directory)/.env"
            """#)
        }
        sections.append(contentsOf: withPortVerification(service, context: context))
        return sections.joined(separator: "\n\n")
    }

    static func withPortVerification(_ service: any ManagedService, context: MailContext) -> [String] {
        let steps = service.setupSteps(context.serviceContext)
        let argument = PortPreflightSections.verifyArgument(service, context: context)
        guard !argument.isEmpty, case .docker(let project) = service.runtime else { return steps }
        let check = #"""
        gd_pp_verify \#(project) "\#(argument)" "\#(service.displayName)"
        gd_pp_settled \#(project) "\#(service.displayName)"
        """#
        guard let index = steps.firstIndex(where: { $0.contains("up -d") }) else {
            return steps + [check]
        }
        var withCheck = steps
        withCheck.insert(check, at: index + 1)
        return withCheck
    }

    static func allSections(_ context: MailContext) -> [String] {
        guard context.needsDocker else { return [] }
        var sections = [installDocker(language: context.language)]
        sections.append(contentsOf: context.allSelectedServices.map { composeSetup($0, context: context) })
        if let panelData = vpnPanelServicesJSON(context) { sections.append(panelData) }
        if context.needsCaddy {
            sections.append(installCaddy(profile: context.distributionProfile(for: context.mailHostRole),
                                         language: context.language))
            sections.append(writeCaddyfile(context))
        }
        return sections
    }

    static func vpnPanelServicesJSON(_ context: MailContext) -> String? {
        guard !context.input.services.isDisjoint(with: ServiceID.vpnProtocols) else { return nil }
        let s = context.serviceContext.settings
        let vhost = s.vpnHostname.isEmpty ? "vpn.\(context.domainName)" : s.vpnHostname
        var entries: [String] = []
        func add(_ svc: ServiceID, _ jsonID: String, _ name: String, _ port: Int, _ proto: String) {
            guard context.input.services.contains(svc) else { return }
            let endpoint = "\(vhost):\(port) · \(proto)"
            entries.append("{\"id\":\"\(jsonID)\",\"name\":\"\(name)\",\"endpoint\":\"\(endpoint)\",\"host\":\"\(vhost)\",\"port\":\"\(port)\"}")
        }
        add(.wireguardVPN, "wireguard", "WireGuard", s.wireguardVPNPort, "UDP")
        add(.amneziaWG, "amneziawg", "AmneziaWG", VPNPortShare.clientPort(context.serviceContext), "UDP")
        add(.shadowsocks, "shadowsocks", "Shadowsocks", s.shadowsocksPort, "TCP+UDP")
        add(.xrayReality, "xray", "VLESS / Reality", s.xrayRealityPort, "TCP")
        add(.openVPN, "openvpn", "OpenVPN", s.openVPNPort, "UDP")
        let json = "{\"services\":[\(entries.joined(separator: ","))]}"
        return #"""
        log "VPN Panel: services.json"
        install -d \#(VPNPanelService.path)/data
        \#(BashSections.writeFile(path: "\(VPNPanelService.path)/data/services.json", contents: json, delimiter: "EOF_VPNPANEL_SVC"))
        docker restart \#(VPNPanelService.containerName) >/dev/null 2>&1 || true
        \#(VPNPortShare.section(context.serviceContext))
        """#
    }

    /// Report for a server without mail: statuses + service access credentials
    static func standaloneReport(_ context: MailContext, extraLines: [String] = []) -> String {
        let language = context.language
        let extra = extraLines.isEmpty ? "" : extraLines.map { "echo \"\($0)\"" }.joined(separator: "\n") + "\n"
        let dnsReminder = context.publishesAddressRecords
            ? "echo \"\(L10nScripts.caddyDNSReminder(language))\"\n\n"
            : ""
        return #"""
        log "\#(L10nScripts.reportTitle(language))"
        echo "\#(L10nScripts.domainLabel(language))\#(context.domainName)"
        \#(extra)echo
        echo "\#(L10nScripts.serviceStatusHeader(language))"
        for s in nftables docker caddy; do
          printf '  %-14s %s\n' "$s" "$(systemctl is-active "$s" || true)"
        done
        echo
        \#(dnsReminder)\#(servicesReport(context))
        """#
    }

    static func hostNeedsBackupPassphrase(_ context: MailContext) -> Bool {
        context.input.dashboardAccess != nil
            && BackupControlSections.needsStoredPassphrase(services: context.allSelectedServices,
                                                           context: context.serviceContext)
    }

    static func servicesReport(_ context: MailContext) -> String {
        let steps = context.allSelectedServices.flatMap { $0.reportSteps(context.serviceContext) }
        guard !steps.isEmpty else { return "" }
        return ([#"""
        echo
        echo "\#(L10nScripts.serviceCredentialsHeader(context.language))"
        """#] + steps).joined(separator: "\n")
    }
}
