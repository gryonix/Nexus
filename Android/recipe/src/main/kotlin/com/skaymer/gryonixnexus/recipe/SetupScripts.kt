package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.embedding
import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.core.ArtifactKind
import com.skaymer.gryonixnexus.core.NetworkAddress
import com.skaymer.gryonixnexus.core.ServerRole
import com.skaymer.gryonixnexus.core.ValidationError
import com.skaymer.gryonixnexus.core.WireGuardDefaults

/** Ready-to-run setup scripts — the main result of generation */
internal object SetupScripts {
    // jq: required by mailcow's generate_config.sh; harmless elsewhere.
    private val HOST_PACKAGES = listOf("nftables", "git", "ca-certificates", "curl", "jq")

    private fun assemble(header: String, steps: List<String>, report: List<String>,
                         finalSteps: List<String> = emptyList(),
                         reportReader: String? = null): String {
        val total = steps.size + (if (report.isEmpty()) 0 else 1) + finalSteps.size
        var index = 0
        fun marker(): String {
            index += 1
            return "echo \"${SetupMarkers.STEP} $index/$total\""
        }
        val parts = mutableListOf(header)
        for (step in steps) parts.add(marker() + "\n" + step)
        if (report.isNotEmpty()) {
            parts.add(marker() + "\necho \"${SetupMarkers.REPORT_BEGIN}\"\nset +e")
            parts.add("GD_REPORT_TMP=\"${SH}(mktemp)\"\n{")
            parts.addAll(report)
            parts.add("} > \"${SH}GD_REPORT_TMP\" 2>&1")
            parts.add("""
            cat "${SH}GD_REPORT_TMP"
            set -e
            echo "${SetupMarkers.REPORT_END}"

            @PERSIST@
            """.trimIndent().embedding("PERSIST" to persistReport(reportReader)))
        }
        for (step in finalSteps) parts.add(marker() + "\n" + step)
        parts.add("echo \"${SetupMarkers.DONE}\"")
        return parts.joinToString("\n\n")
    }

    private fun gatedByServicesFlag(step: String): String {
        if (step.isBlank()) return step
        return "if [ -z \"${SH}{GRYONIXNEXUS_SKIP_SERVICES:-}\" ]; then\n$step\nfi"
    }

    private fun persistReport(reader: String?): String {
        val path = SetupMarkers.REPORT_FILE_PATH
        val directory = path.substring(0, path.lastIndexOf('/'))
        val chown = reader?.let { "\n  chown '$it' $path 2>/dev/null || true" } ?: ""
        return """
        # Best effort throughout: the report has already been printed, and
        # nothing about keeping a copy of it is worth failing an install over.
        install -d -m 755 $directory 2>/dev/null || true
        if cp "${SH}GD_REPORT_TMP" $path 2>/dev/null; then
          chmod 600 $path 2>/dev/null || true@CHOWN@
        fi
        rm -f "${SH}GD_REPORT_TMP"
        """.trimIndent().embedding("CHOWN" to chown)
    }

    // MARK: - One script per service

    const val SERVICE_PREFIX = "service-"
    const val FINISH_NAME = Artifact.FINISH_SETUP_NAME

    /** A script per selected service, then one to finish */
    fun serviceScripts(context: MailContext, ptrIP: String, extraLines: List<String> = emptyList()): List<Artifact> {
        if (!context.needsDocker) return emptyList()
        return context.allSelectedServices.map { serviceScript(it, context) } +
            finishScript(context, ptrIP, extraLines)
    }

    fun serviceScript(service: ManagedService, context: MailContext): Artifact {
        val role = context.mailHostRole
        val fileName = SERVICE_PREFIX + service.id.rawValue + ".sh"
        val steps = mutableListOf<String>()
        PortPreflightSections.section(context)?.let { steps.add(it) }
        steps.add(ServiceInfraSections.installDocker(context.language))
        steps.add(ServiceInfraSections.composeSetup(service, context))
        if (service.id == ServiceID.VPN_PANEL) {
            ServiceInfraSections.vpnPanelServicesJSON(context)?.let { steps.add(it) }
        }
        if (context.needsCaddy) {
            steps.add(ServiceInfraSections.installCaddy(context.distributionProfile(role), context.language))
            steps.add(ServiceInfraSections.writeCaddyfile(context))
        }
        val header = BashSections.header(
            scriptName = fileName,
            purpose = service.displayName,
            profile = context.distributionProfile(role),
            language = context.language
        )
        return Artifact(fileName = fileName, kind = ArtifactKind.SHELL_SCRIPT,
            contents = assemble(header, steps, emptyList()), summary = service.displayName, server = role)
    }

    /** The report and the install key taken back */
    fun finishScript(context: MailContext, ptrIP: String, extraLines: List<String>): Artifact {
        val role = context.mailHostRole
        val finalSteps = listOfNotNull(
            context.input.dashboardAccess?.let { DashboardAccessSections.revokeInstallKey(it, context.language) }
        )
        val header = BashSections.header(
            scriptName = FINISH_NAME,
            purpose = L10nScripts.reportTitle(context.language),
            profile = context.distributionProfile(role),
            language = context.language
        )
        val script = assemble(
            header = header,
            steps = emptyList(),
            report = reportSections(context, ptrIP, extraLines),
            finalSteps = finalSteps,
            reportReader = context.input.dashboardAccess?.sshUser
        )
        return Artifact(fileName = FINISH_NAME, kind = ArtifactKind.SHELL_SCRIPT, contents = script,
            summary = L10nScripts.reportTitle(context.language), server = role)
    }

    // MARK: - Scenario A: single server with a public IP

    fun mailServer(context: MailContext): Artifact {
        val host = context.mailHost
        val publicIP = host?.publicAddress?.value
            ?: throw ValidationError.MissingPublicIP(context.mailHostRole)
        val profile = context.distributionProfile(host.role)
        val language = context.language

        val header = BashSections.header(
            scriptName = "setup-mail-server.sh",
            purpose = if (context.hasMail) {
                L10nScripts.purposeMailServer(language, context.hostname)
            } else {
                L10nScripts.purposeServicesServer(language, context.domainName)
            },
            profile = profile,
            language = language
        )
        val steps = mutableListOf<String>()
        if (context.hasMail) {
            steps.add(BashSections.dnsCheck(context.hostname, publicIP, language))
        }
        PortPreflightSections.section(context)?.let { steps.add(it) }
        steps.add(BashSections.installPackages(HOST_PACKAGES, profile, language))
        steps.add(BashSections.applyFirewall(NftablesConfig.singleHostRuleset(context)))
        steps.add(CrowdSecSections.install(context.input.serviceSettings.crowdsecEnabled, language))
        steps.add(MetricsHistorySections.install(language))
        steps.addAll(ServiceInfraSections.allSections(context).map(::gatedByServicesFlag))
        val finalSteps = mutableListOf<String>()
        context.input.dashboardAccess?.let { access ->
            steps.add(DashboardAccessSections.singleHostSection(access, context))
            finalSteps.add(gatedByServicesFlag(DashboardAccessSections.revokeInstallKey(access, language)))
        }
        val script = assemble(
            header = header,
            steps = steps,
            report = reportSections(context, publicIP),
            finalSteps = finalSteps,
            reportReader = context.input.dashboardAccess?.sshUser
        )

        return Artifact(
            fileName = "setup-mail-server.sh",
            kind = ArtifactKind.SHELL_SCRIPT,
            contents = script,
            summary = L10nScripts.summarySingleHost(language),
            server = ServerRole.SINGLE_HOST
        )
    }

    private fun reportSections(context: MailContext, ptrIP: String,
                               extraLines: List<String> = emptyList()): List<String> {
        val language = context.language
        val lines = extraLines.toMutableList()
        if (context.hasMail) {
            lines.add(L10nScripts.mailHostLabel(language) + context.hostname)
        }
        if (context.publishesAddressRecords) {
            lines.add(L10nScripts.ptrReminder(language, ptrIP, context.ptrHostname))
        }
        if (ServiceInfraSections.hostNeedsBackupPassphrase(context)) {
            lines.add(L10nScripts.backupPassphraseLabel(language) +
                          "${SH}(cat ${BackupControlSections.PASSPHRASE_PATH} 2>/dev/null)")
        }
        return listOf(ServiceInfraSections.standaloneReport(context, lines))
    }

    // MARK: - Scenario B: VPS entry point

    fun vps(context: MailContext, vpsKeys: WireGuardKeyPair, homePublicKey: String): Artifact {
        val language = context.language
        val home = context.server(ServerRole.HOME_BACKEND)
        val homeWG = (home?.vpnAddress as? NetworkAddress.IPv4)?.value
        val wgConf = WireGuardConfig.vpsConf(context, vpsKeys, homePublicKey)
        val ruleset = NftablesConfig.vpsRuleset(context)
        if (context.server(ServerRole.VPS_RELAY) == null || homeWG == null ||
            wgConf == null || ruleset == null) {
            throw ValidationError.InconsistentTopology(
                L10nGeneration.errSplitAddressesMissing(language)
            )
        }
        val profile = context.distributionProfile(ServerRole.VPS_RELAY)
        val ports = context.forwardedPorts.joinToString(", ")
        val wgPort = WireGuardDefaults.LISTEN_PORT

        val wireGuardSection = """
        log "WireGuard: /etc/wireguard/wg0.conf"
        install -d -m 700 /etc/wireguard
        @WG_CONF@
        chmod 600 /etc/wireguard/wg0.conf
        """.trimIndent().embedding(
            "WG_CONF" to BashSections.writeFile("/etc/wireguard/wg0.conf", wgConf, "EOF_WG")
        )

        val sysctlSection = """
        log "${L10nScripts.enableForwardingLog(language)}"
        @SYSCTL@
        sysctl --system >/dev/null
        """.trimIndent().embedding(
            "SYSCTL" to BashSections.writeFile("/etc/sysctl.d/99-gryonixnexus-forwarding.conf",
                                               NftablesConfig.vpsSysctl, "EOF_SYSCTL")
        )

        val firewallSection = """
        log "${L10nScripts.detectPublicInterfaceLog(language)}"
        PUB_IF="${SH}(ip -4 route get 1.1.1.1 | awk '{for (i=1;i<NF;i++) if (${SH}i=="dev") {print ${SH}(i+1); exit}}')"
        [ -n "${SH}{PUB_IF:-}" ] || fail "${L10nScripts.publicInterfaceFail(language)}"
        echo "${L10nScripts.publicInterfaceIs(language, "${SH}PUB_IF")}"

        @FIREWALL@
        """.trimIndent().embedding("FIREWALL" to BashSections.applyFirewall(ruleset))
        val firewallWithInterface = firewallSection.replace(
            "nft -c -f /etc/nftables.conf",
            "sed -i \"s|${NftablesConfig.PUBLIC_INTERFACE_PLACEHOLDER}|${SH}PUB_IF|g\" " +
                "/etc/nftables.conf\nnft -c -f /etc/nftables.conf"
        )

        val tunnelSection = """
        log "${L10nScripts.startingTunnel(language)}"
        systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true
        systemctl restart wg-quick@wg0
        """.trimIndent()

        val report = """
        log "${L10nScripts.reportTitle(language)}"
        echo "${L10nScripts.vpsReportWireGuard(language, wgPort)}"
        echo "${L10nScripts.vpsReportFirewall(language, ports, homeWG)}"
        echo "${L10nScripts.vpsReportForwarding(language)}"
        echo
        echo "${L10nScripts.serviceStatusHeader(language)}"
        for s in nftables wg-quick@wg0; do
          printf '  %-14s %s\n' "${SH}s" "${SH}(systemctl is-active "${SH}s" || true)"
        done
        echo
        echo "${L10nScripts.vpsHandshakeNote(language)}"
        wg show wg0 || true
        echo
        echo "${L10nScripts.nextStepsHeader(language)}"
        echo "  ${L10nScripts.vpsNextStepHome(language)}"
        echo "  ${L10nScripts.vpsNextStepPTR(language, context.ptrHostname)}"
        """.trimIndent()

        val header = BashSections.header(
            scriptName = "setup-vps.sh",
            purpose = L10nScripts.purposeVPS(language),
            profile = profile,
            language = language
        )
        val steps = mutableListOf(
            BashSections.installPackages(listOf("wireguard", "wireguard-tools", "nftables"),
                                         profile, language),
            wireGuardSection,
            sysctlSection,
            firewallWithInterface,
            CrowdSecSections.install(context.input.serviceSettings.crowdsecEnabled, language),
            tunnelSection,
            MetricsHistorySections.install(language)
        )
        val finalSteps = mutableListOf<String>()
        context.input.dashboardAccess?.let { access ->
            steps.add(DashboardAccessSections.vpsSection(access, language))
            finalSteps.add(gatedByServicesFlag(DashboardAccessSections.revokeInstallKey(access, language)))
        }
        val script = assemble(header, steps, listOf(report), finalSteps,
                              context.input.dashboardAccess?.sshUser)

        return Artifact(
            fileName = "setup-vps.sh",
            kind = ArtifactKind.SHELL_SCRIPT,
            contents = script,
            summary = L10nScripts.summaryVPS(language),
            server = ServerRole.VPS_RELAY
        )
    }

    // MARK: - Scenario B: home server

    fun homeServer(context: MailContext, homeKeys: WireGuardKeyPair,
                   vpsPublicKey: String): Artifact {
        val language = context.language
        val vpsPublicIP = context.server(ServerRole.VPS_RELAY)?.publicAddress?.value
        val wgConf = WireGuardConfig.homeConf(context, homeKeys, vpsPublicKey)
        if (vpsPublicIP == null || wgConf == null) {
            throw ValidationError.InconsistentTopology(
                L10nGeneration.errSplitAddressesMissing(language)
            )
        }
        val profile = context.distributionProfile(ServerRole.HOME_BACKEND)
        val wgPort = WireGuardDefaults.LISTEN_PORT

        val wireGuardSection = """
        log "${L10nScripts.wgFullTunnelLog(language)}"
        install -d -m 700 /etc/wireguard
        @WG_CONF@
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
        @TUNNEL_ENDPOINT@
        systemctl daemon-reload
        systemctl enable --now gryonixnexus-tunnel-endpoint.service >/dev/null 2>&1 || true

        log "${L10nScripts.startingTunnelToVPS(language, "$vpsPublicIP:$wgPort")}"
        systemctl enable wg-quick@wg0 >/dev/null 2>&1 || true
        systemctl restart wg-quick@wg0

        log "${L10nScripts.waitingForHandshake(language)}"
        handshake=0
        for _ in ${SH}(seq 1 20); do
          hs="${SH}(wg show wg0 latest-handshakes | awk 'NR==1{print ${SH}2}')"
          if [ -n "${SH}{hs:-}" ] && [ "${SH}hs" -gt 0 ] 2>/dev/null; then handshake=1; break; fi
          sleep 1
        done
        [ "${SH}handshake" -eq 1 ] || fail "@NO_HANDSHAKE@"
        echo "${L10nScripts.tunnelUp(language)}"

        @ROUTE_SYNC@
        @WATCHDOG@
        """.trimIndent().embedding(
            "WG_CONF" to BashSections.writeFile("/etc/wireguard/wg0.conf", wgConf, "EOF_WG"),
            "TUNNEL_ENDPOINT" to BashSections.writeFile(
                "/etc/systemd/system/gryonixnexus-tunnel-endpoint.service",
                tunnelEndpointUnit(vpsPublicIP), "EOF_TUNNEL_ENDPOINT"
            ),
            "NO_HANDSHAKE" to L10nScripts.noHandshake(language, "$vpsPublicIP:$wgPort", wgPort),
            "ROUTE_SYNC" to RelayRouteSyncSections.install(),
            "WATCHDOG" to TunnelWatchdogSections.install()
        )

        val sysctlSection = """
        log "Loosening rp_filter: /etc/sysctl.d/99-gryonixnexus-rpfilter.conf"
        @SYSCTL@
        sysctl --system >/dev/null
        """.trimIndent().embedding(
            "SYSCTL" to BashSections.writeFile("/etc/sysctl.d/99-gryonixnexus-rpfilter.conf",
                                               NftablesConfig.homeSysctl, "EOF_SYSCTL")
        )

        val header = BashSections.header(
            scriptName = "setup-home-server.sh",
            purpose = if (context.hasMail) {
                L10nScripts.purposeHomeMail(language)
            } else {
                L10nScripts.purposeHomeServices(language)
            },
            profile = profile,
            language = language
        )
        val steps = mutableListOf<String>()
        if (context.hasMail) {
            steps.add(BashSections.dnsCheck(context.hostname, vpsPublicIP, language))
        }
        PortPreflightSections.section(context)?.let { steps.add(it) }
        steps.add(BashSections.installPackages(
            HOST_PACKAGES + listOf("wireguard", "wireguard-tools"), profile, language
        ))
        steps.add(sysctlSection)
        steps.add(BashSections.applyFirewall(NftablesConfig.homeRuleset(context)))
        steps.add(CrowdSecSections.install(context.input.serviceSettings.crowdsecEnabled, language))
        steps.add(MetricsHistorySections.install(language))
        steps.add(wireGuardSection)
        steps.addAll(ServiceInfraSections.allSections(context).map(::gatedByServicesFlag))
        val finalSteps = mutableListOf<String>()
        context.input.dashboardAccess?.let { access ->
            steps.add(DashboardAccessSections.homeSection(access, context))
            finalSteps.add(gatedByServicesFlag(DashboardAccessSections.revokeInstallKey(access, language)))
        }
        val tunnelLine = L10nScripts.tunnelReportLine(language, "$vpsPublicIP:$wgPort")
        val script = assemble(
            header = header,
            steps = steps,
            report = reportSections(context, vpsPublicIP, listOf(tunnelLine)),
            finalSteps = finalSteps,
            reportReader = context.input.dashboardAccess?.sshUser
        )

        return Artifact(
            fileName = "setup-home-server.sh",
            kind = ArtifactKind.SHELL_SCRIPT,
            contents = script,
            summary = L10nScripts.summaryHome(language),
            server = ServerRole.HOME_BACKEND
        )
    }
}

fun tunnelEndpointUnit(endpoint: String): String = """
    [Unit]
    Description=gryonixNexus: keep the WireGuard relay reachable outside the tunnel
    Wants=network-online.target
    After=network-online.target
    Before=wg-quick@wg0.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/bin/sh -c 'ip -4 route replace $endpoint/32 ${'$'}(ip -4 route show default table main | head -n1 | cut -d" " -f2-)'
    ExecStop=/bin/sh -c 'ip -4 route del $endpoint/32 || true'

    [Install]
    WantedBy=multi-user.target
""".trimIndent()
