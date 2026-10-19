import gryonixNexusCore
import ServiceCatalog

/// Ready-to-run setup scripts — the main result of generation
enum SetupScripts {
    // jq: required by mailcow's generate_config.sh; harmless elsewhere.
    private static let hostPackages = ["nftables", "git", "ca-certificates", "curl", "jq"]

    private static func assemble(header: String, steps: [String],
                                 report: [String], finalSteps: [String] = [],
                                 reportReader: String? = nil) -> String {
        let total = steps.count + (report.isEmpty ? 0 : 1) + finalSteps.count
        var index = 0
        func marker() -> String {
            index += 1
            return "echo \"\(SetupMarkers.step) \(index)/\(total)\""
        }
        var parts = [header]
        for step in steps { parts.append(marker() + "\n" + step) }
        if !report.isEmpty {
            parts.append(marker() + "\necho \"\(SetupMarkers.reportBegin)\"\nset +e")
            parts.append("GD_REPORT_TMP=\"$(mktemp)\"\n{")
            parts.append(contentsOf: report)
            parts.append("} > \"$GD_REPORT_TMP\" 2>&1")
            parts.append(#"""
            cat "$GD_REPORT_TMP"
            set -e
            echo "\#(SetupMarkers.reportEnd)"

            \#(persistReport(reader: reportReader))
            """#)
        }
        for step in finalSteps { parts.append(marker() + "\n" + step) }
        parts.append("echo \"\(SetupMarkers.done)\"")
        return parts.joined(separator: "\n\n")
    }

    /// Wraps one step so `GRYONIXNEXUS_SKIP_SERVICES=1` turns it into a no-op
    static func gatedByServicesFlag(_ step: String) -> String {
        guard !step.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return step }
        return "if [ -z \"${GRYONIXNEXUS_SKIP_SERVICES:-}\" ]; then\n\(step)\nfi"
    }

    private static func persistReport(reader: String?) -> String {
        let path = SetupMarkers.reportFilePath
        let directory = String(path[path.startIndex..<path.lastIndex(of: "/")!])
        let chown = reader.map { "\n  chown '\($0)' \(path) 2>/dev/null || true" } ?? ""
        return #"""
        # Best effort throughout: the report has already been printed, and
        # nothing about keeping a copy of it is worth failing an install over.
        install -d -m 755 \#(directory) 2>/dev/null || true
        if cp "$GD_REPORT_TMP" \#(path) 2>/dev/null; then
          chmod 600 \#(path) 2>/dev/null || true\#(chown)
        fi
        rm -f "$GD_REPORT_TMP"
        """#
    }

    // MARK: - Scenario A: single server with a public IP

    static func mailServer(_ context: MailContext) throws -> Artifact {
        guard let host = context.mailHost, let publicIP = host.publicAddress?.value else {
            throw ValidationError.missingPublicIP(role: context.mailHostRole)
        }
        let profile = context.distributionProfile(for: host.role)
        let language = context.language

        let header = BashSections.header(
            scriptName: "setup-mail-server.sh",
            purpose: context.hasMail
                ? L10nScripts.purposeMailServer(language, hostname: context.hostname)
                : L10nScripts.purposeServicesServer(language, domain: context.domainName),
            profile: profile,
            language: language
        )
        var steps: [String] = []
        if context.hasMail {
            steps.append(BashSections.dnsCheck(hostname: context.hostname, expectedIP: publicIP,
                                               language: language))
        }
        if let preflight = PortPreflightSections.section(context) { steps.append(preflight) }
        steps.append(BashSections.installPackages(hostPackages, profile: profile, language: language))
        steps.append(BashSections.applyFirewall(ruleset: NftablesConfig.singleHostRuleset(context)))
        steps.append(CrowdSecSections.install(enabled: context.input.serviceSettings.crowdsecEnabled,
                                              language: language))
        steps.append(MetricsHistorySections.install(language: language))
        steps.append(contentsOf: ServiceInfraSections.allSections(context).map(Self.gatedByServicesFlag))
        var finalSteps: [String] = []
        if let access = context.input.dashboardAccess {
            steps.append(DashboardAccessSections.singleHostSection(access, context: context))
            finalSteps.append(Self.gatedByServicesFlag(DashboardAccessSections.revokeInstallKey(access, language: language)))
        }
        let script = assemble(
            header: header,
            steps: steps,
            report: reportSections(context, ptrIP: publicIP),
            finalSteps: finalSteps,
            reportReader: context.input.dashboardAccess?.sshUser
        )

        return Artifact(
            fileName: "setup-mail-server.sh",
            kind: .shellScript,
            contents: script,
            summary: L10nScripts.summarySingleHost(language),
            server: .singleHost
        )
    }

    private static func reportSections(_ context: MailContext, ptrIP: String,
                                       extraLines: [String] = []) -> [String] {
        let language = context.language
        var lines = extraLines
        if context.hasMail {
            lines.append(L10nScripts.mailHostLabel(language) + context.hostname)
        }
        if context.publishesAddressRecords {
            lines.append(L10nScripts.ptrReminder(language, ip: ptrIP, hostname: context.ptrHostname))
        }
        if ServiceInfraSections.hostNeedsBackupPassphrase(context) {
            lines.append(L10nScripts.backupPassphraseLabel(language)
                         + "$(cat \(BackupControlSections.passphrasePath) 2>/dev/null)")
        }
        return [ServiceInfraSections.standaloneReport(context, extraLines: lines)]
    }

    // MARK: - Scenario B: VPS entry point

    static func vps(
        _ context: MailContext,
        vpsKeys: WireGuardKeyPair,
        homePublicKey: String
    ) throws -> Artifact {
        let language = context.language
        guard let vps = context.server(.vpsRelay),
              let home = context.server(.homeBackend),
              case .ipv4(let homeWG)? = home.vpnAddress,
              let wgConf = WireGuardConfig.vpsConf(context: context, vpsKeys: vpsKeys, homePublicKey: homePublicKey),
              let ruleset = NftablesConfig.vpsRuleset(context) else {
            throw ValidationError.inconsistentTopology(L10nGeneration.errSplitAddressesMissing(language))
        }
        let profile = context.distributionProfile(for: .vpsRelay)
        let ports = context.forwardedPorts.map(String.init).joined(separator: ", ")
        let wgPort = WireGuardDefaults.listenPort
        _ = vps

        let wireGuardSection = #"""
        log "WireGuard: /etc/wireguard/wg0.conf"
        install -d -m 700 /etc/wireguard
        \#(BashSections.writeFile(path: "/etc/wireguard/wg0.conf", contents: wgConf, delimiter: "EOF_WG"))
        chmod 600 /etc/wireguard/wg0.conf
        """#

        let sysctlSection = #"""
        log "\#(L10nScripts.enableForwardingLog(language))"
        \#(BashSections.writeFile(path: "/etc/sysctl.d/99-gryonixnexus-forwarding.conf", contents: NftablesConfig.vpsSysctl, delimiter: "EOF_SYSCTL"))
        sysctl --system >/dev/null
        """#

        let firewallSection = #"""
        log "\#(L10nScripts.detectPublicInterfaceLog(language))"
        PUB_IF="$(ip -4 route get 1.1.1.1 | awk '{for (i=1;i<NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
        [ -n "${PUB_IF:-}" ] || fail "\#(L10nScripts.publicInterfaceFail(language))"
        echo "\#(L10nScripts.publicInterfaceIs(language, interface: "$PUB_IF"))"

        \#(BashSections.applyFirewall(ruleset: ruleset))
        """#
        let firewallWithInterface = firewallSection.replacingOccurrences(
            of: "nft -c -f /etc/nftables.conf",
            with: "sed -i \"s|\(NftablesConfig.publicInterfacePlaceholder)|$PUB_IF|g\" /etc/nftables.conf\nnft -c -f /etc/nftables.conf"
        )

        let tunnelSection = #"""
        log "\#(L10nScripts.startingTunnel(language))"
        systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true
        systemctl restart wg-quick@wg0
        """#

        let report = #"""
        log "\#(L10nScripts.reportTitle(language))"
        echo "\#(L10nScripts.vpsReportWireGuard(language, port: wgPort))"
        echo "\#(L10nScripts.vpsReportFirewall(language, ports: ports, target: homeWG))"
        echo "\#(L10nScripts.vpsReportForwarding(language))"
        echo
        echo "\#(L10nScripts.serviceStatusHeader(language))"
        for s in nftables wg-quick@wg0; do
          printf '  %-14s %s\n' "$s" "$(systemctl is-active "$s" || true)"
        done
        echo
        echo "\#(L10nScripts.vpsHandshakeNote(language))"
        wg show wg0 || true
        echo
        echo "\#(L10nScripts.nextStepsHeader(language))"
        echo "  \#(L10nScripts.vpsNextStepHome(language))"
        echo "  \#(L10nScripts.vpsNextStepPTR(language, hostname: context.ptrHostname))"
        """#

        let header = BashSections.header(
            scriptName: "setup-vps.sh",
            purpose: L10nScripts.purposeVPS(language),
            profile: profile,
            language: language
        )
        var steps = [
            BashSections.installPackages(["wireguard", "wireguard-tools", "nftables"],
                                         profile: profile, language: language),
            wireGuardSection,
            sysctlSection,
            firewallWithInterface,
            CrowdSecSections.install(enabled: context.input.serviceSettings.crowdsecEnabled,
                                     language: language),
            tunnelSection,
            MetricsHistorySections.install(language: language)
        ]
        var finalSteps: [String] = []
        if let access = context.input.dashboardAccess {
            steps.append(DashboardAccessSections.vpsSection(access, language: language))
            finalSteps.append(Self.gatedByServicesFlag(DashboardAccessSections.revokeInstallKey(access, language: language)))
        }
        let script = assemble(header: header, steps: steps, report: [report], finalSteps: finalSteps,
                              reportReader: context.input.dashboardAccess?.sshUser)

        return Artifact(
            fileName: "setup-vps.sh",
            kind: .shellScript,
            contents: script,
            summary: L10nScripts.summaryVPS(language),
            server: .vpsRelay
        )
    }

    // MARK: - Scenario B: home server

    static func homeServer(
        _ context: MailContext,
        homeKeys: WireGuardKeyPair,
        vpsPublicKey: String
    ) throws -> Artifact {
        let language = context.language
        guard let vps = context.server(.vpsRelay),
              let vpsPublicIP = vps.publicAddress?.value,
              let wgConf = WireGuardConfig.homeConf(context: context, homeKeys: homeKeys, vpsPublicKey: vpsPublicKey) else {
            throw ValidationError.inconsistentTopology(L10nGeneration.errSplitAddressesMissing(language))
        }
        let profile = context.distributionProfile(for: .homeBackend)
        let wgPort = WireGuardDefaults.listenPort

        let wireGuardSection = #"""
        log "\#(L10nScripts.wgFullTunnelLog(language))"
        install -d -m 700 /etc/wireguard
        \#(BashSections.writeFile(path: "/etc/wireguard/wg0.conf", contents: wgConf, delimiter: "EOF_WG"))
        chmod 600 /etc/wireguard/wg0.conf

        # **The relay's own address is pinned OUTSIDE the tunnel, before the
        # tunnel comes up.** wg-quick answers a full tunnel by moving every
        # route into its own table and exempting the encrypted packets with
        # `fwmark 51820`; any other mangle rule on this host that rewrites
        # marks clears that exemption — mailcow's netfilter container sets one
        # on every outgoing packet, and mailcow is a service from this same
        # catalogue. The encrypted UDP then matches the default route wg-quick
        # has just installed, is encrypted again, and the machine sends
        # hundreds of megabytes a second to itself with no internet at all.
        #
        # A /32 in the MAIN table is immune to that: wg-quick's own rules
        # consult main first (`lookup main suppress_prefixlength 0`), and no
        # mark can affect a route. It is a unit rather than a `PreUp` for two
        # reasons — a failing hook takes the whole interface down with it, and
        # Ubuntu 26.04 confines wg-quick with an AppArmor profile allowing only
        # `ip`, `nft` and `sysctl`, so a hook that needs a shell pipeline is
        # denied and `|| true` hides it.
        \#(BashSections.writeFile(path: "/etc/systemd/system/gryonixnexus-tunnel-endpoint.service",
                                  contents: tunnelEndpointUnit(endpoint: vpsPublicIP),
                                  delimiter: "EOF_TUNNEL_ENDPOINT"))
        systemctl daemon-reload
        systemctl enable --now gryonixnexus-tunnel-endpoint.service >/dev/null 2>&1 || true

        log "\#(L10nScripts.startingTunnelToVPS(language, endpoint: "\(vpsPublicIP):\(wgPort)"))"
        systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true
        systemctl restart wg-quick@wg0

        log "\#(L10nScripts.waitingForHandshake(language))"
        handshake=0
        for _ in $(seq 1 20); do
          hs="$(wg show wg0 latest-handshakes | awk 'NR==1{print $2}')"
          if [ -n "${hs:-}" ] && [ "$hs" -gt 0 ] 2>/dev/null; then handshake=1; break; fi
          sleep 1
        done
        [ "$handshake" -eq 1 ] || fail "\#(L10nScripts.noHandshake(language, endpoint: "\(vpsPublicIP):\(wgPort)", port: wgPort))"
        echo "\#(L10nScripts.tunnelUp(language))"

        \#(RelayRouteSyncSections.install())
        \#(TunnelWatchdogSections.install())
        """#

        let sysctlSection = #"""
        log "Loosening rp_filter: /etc/sysctl.d/99-gryonixnexus-rpfilter.conf"
        \#(BashSections.writeFile(path: "/etc/sysctl.d/99-gryonixnexus-rpfilter.conf", contents: NftablesConfig.homeSysctl, delimiter: "EOF_SYSCTL"))
        sysctl --system >/dev/null
        """#

        let header = BashSections.header(
            scriptName: "setup-home-server.sh",
            purpose: context.hasMail
                ? L10nScripts.purposeHomeMail(language)
                : L10nScripts.purposeHomeServices(language),
            profile: profile,
            language: language
        )
        var steps: [String] = []
        if context.hasMail {
            steps.append(BashSections.dnsCheck(hostname: context.hostname, expectedIP: vpsPublicIP,
                                               language: language))
        }
        if let preflight = PortPreflightSections.section(context) { steps.append(preflight) }
        steps.append(BashSections.installPackages(
            hostPackages + ["wireguard", "wireguard-tools"],
            profile: profile, language: language
        ))
        steps.append(sysctlSection)
        steps.append(BashSections.applyFirewall(ruleset: NftablesConfig.homeRuleset(context)))
        steps.append(CrowdSecSections.install(enabled: context.input.serviceSettings.crowdsecEnabled,
                                              language: language))
        steps.append(MetricsHistorySections.install(language: language))
        steps.append(wireGuardSection)
        steps.append(contentsOf: ServiceInfraSections.allSections(context).map(Self.gatedByServicesFlag))
        var finalSteps: [String] = []
        if let access = context.input.dashboardAccess {
            steps.append(DashboardAccessSections.homeSection(access, context: context))
            finalSteps.append(Self.gatedByServicesFlag(DashboardAccessSections.revokeInstallKey(access, language: language)))
        }
        let tunnelLine = L10nScripts.tunnelReportLine(language, endpoint: "\(vpsPublicIP):\(wgPort)")
        let script = assemble(
            header: header,
            steps: steps,
            report: reportSections(context, ptrIP: vpsPublicIP, extraLines: [tunnelLine]),
            finalSteps: finalSteps,
            reportReader: context.input.dashboardAccess?.sshUser
        )

        return Artifact(
            fileName: "setup-home-server.sh",
            kind: .shellScript,
            contents: script,
            summary: L10nScripts.summaryHome(language),
            server: .homeBackend
        )
    }
}

func tunnelEndpointUnit(endpoint: String) -> String {
    """
    [Unit]
    Description=gryonixNexus: keep the WireGuard relay reachable outside the tunnel
    Wants=network-online.target
    After=network-online.target
    Before=wg-quick@wg0.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/bin/sh -c 'ip -4 route replace \(endpoint)/32 $(ip -4 route show default table main | head -n1 | cut -d" " -f2-)'
    ExecStop=/bin/sh -c 'ip -4 route del \(endpoint)/32 || true'

    [Install]
    WantedBy=multi-user.target
    """
}

// MARK: - One script per service

extension SetupScripts {
    static let servicePrefix = "service-"
    static let finishName = Artifact.finishSetupName

    /// A script per selected service, then one to finish
    static func serviceScripts(_ context: MailContext, ptrIP: String, extraLines: [String] = []) -> [Artifact] {
        guard context.needsDocker else { return [] }
        return context.allSelectedServices.map { serviceScript($0, context: context) }
            + [finishScript(context, ptrIP: ptrIP, extraLines: extraLines)]
    }

    static func serviceScript(_ service: any ManagedService, context: MailContext) -> Artifact {
        let role = context.mailHostRole
        let fileName = servicePrefix + service.id.rawValue + ".sh"
        var steps: [String] = []
        if let preflight = PortPreflightSections.section(context) { steps.append(preflight) }
        steps.append(ServiceInfraSections.installDocker(language: context.language))
        steps.append(ServiceInfraSections.composeSetup(service, context: context))
        if service.id == .vpnPanel, let panel = ServiceInfraSections.vpnPanelServicesJSON(context) {
            steps.append(panel)
        }
        if context.needsCaddy {
            steps.append(ServiceInfraSections.installCaddy(profile: context.distributionProfile(for: role),
                                                           language: context.language))
            steps.append(ServiceInfraSections.writeCaddyfile(context))
        }
        let header = BashSections.header(scriptName: fileName, purpose: service.displayName,
                                         profile: context.distributionProfile(for: role),
                                         language: context.language)
        return Artifact(fileName: fileName, kind: .shellScript,
                        contents: assemble(header: header, steps: steps, report: []),
                        summary: service.displayName, server: role)
    }

    /// The report and the install key taken back
    static func finishScript(_ context: MailContext, ptrIP: String, extraLines: [String]) -> Artifact {
        let role = context.mailHostRole
        var finalSteps: [String] = []
        if let access = context.input.dashboardAccess {
            finalSteps.append(DashboardAccessSections.revokeInstallKey(access, language: context.language))
        }
        let header = BashSections.header(scriptName: finishName, purpose: L10nScripts.reportTitle(context.language),
                                         profile: context.distributionProfile(for: role),
                                         language: context.language)
        let script = assemble(header: header, steps: [],
                              report: reportSections(context, ptrIP: ptrIP, extraLines: extraLines),
                              finalSteps: finalSteps, reportReader: context.input.dashboardAccess?.sshUser)
        return Artifact(fileName: finishName, kind: .shellScript, contents: script,
                        summary: L10nScripts.reportTitle(context.language), server: role)
    }
}
