package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.VPNPortShare
import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.CaddySetupGuard
import com.skaymer.gryonixnexus.catalog.Apt
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.embedding
import com.skaymer.gryonixnexus.catalog.services.AutheliaService
import com.skaymer.gryonixnexus.catalog.services.VPNPanelService
import com.skaymer.gryonixnexus.core.DistributionProfile

internal object ServiceInfraSections {
    fun installDocker(language: AppLanguage): String = """
        log "${L10nScripts.installingDocker(language)}"
        if ! command -v docker >/dev/null 2>&1; then
          curl -fsSL https://get.docker.com | sh
        fi
        systemctl enable --now docker >/dev/null 2>&1 || true
        """.trimIndent()

    /** Installs the release .deb, verified against its sha512 list */
    @Suppress("UNUSED_PARAMETER")
    fun installCaddy(profile: DistributionProfile, language: AppLanguage): String = """
        log "${L10nScripts.installingCaddy(language)}"
        @STALE@
        if ! command -v caddy >/dev/null 2>&1 || ! id caddy >/dev/null 2>&1; then
          caddy_arch="${SH}(dpkg --print-architecture)"
          case "${SH}caddy_arch" in armhf) caddy_arch=armv6 ;; armel) caddy_arch=armv5 ;; esac
          caddy_tag="${SH}(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/caddyserver/caddy/releases/latest)"
          caddy_tag="${SH}{caddy_tag##*/}"
          caddy_deb="caddy_${SH}{caddy_tag#v}_linux_${SH}{caddy_arch}.deb"
          caddy_url="https://github.com/caddyserver/caddy/releases/download/${SH}caddy_tag"
          caddy_tmp="${SH}(mktemp -d)"
          curl -fsSL -o "${SH}caddy_tmp/${SH}caddy_deb" "${SH}caddy_url/${SH}caddy_deb"
          curl -fsSL -o "${SH}caddy_tmp/sums" "${SH}caddy_url/caddy_${SH}{caddy_tag#v}_checksums.txt"
          (cd "${SH}caddy_tmp" && grep "  ${SH}caddy_deb\${SH}" sums | sha512sum -c -)
          @APT@ install -yq --no-install-recommends --reinstall "${SH}caddy_tmp/${SH}caddy_deb"
          id caddy >/dev/null
          rm -rf "${SH}caddy_tmp"
        fi
        """.trimIndent().embedding(
        "STALE" to Apt.DROP_RETIRED_SOURCES,
        "APT" to Apt.QUIET
    )

    fun caddySite(owner: String, hostname: String, upstreamPort: Int,
                  adminGuard: Boolean = false,
                  upstreamHTTPS: Boolean = false, tlsInternal: Boolean = false,
                  sso: Boolean = false, publicPaths: List<String> = emptyList(),
                  overwriteForwardedFor: Boolean = false): String {
        val proxy = if (upstreamHTTPS) {
            """
            reverse_proxy https://127.0.0.1:$upstreamPort {
                    header_up Host {host}
                    transport http {
                        tls_insecure_skip_verify
                    }
                }
            """.trimIndent()
        } else if (overwriteForwardedFor) {
            """
            reverse_proxy 127.0.0.1:$upstreamPort {
                    header_up X-Forwarded-For {remote_host}
                }
            """.trimIndent()
        } else {
            "reverse_proxy 127.0.0.1:$upstreamPort"
        }
        val tlsLine = if (tlsInternal) "tls internal\n    " else ""
        val ssoLine = if (sso) AutheliaService.forwardAuthBlock(hostname) + "\n    " else ""
        val ownerLine = "# $CADDY_OWNER_TAG $owner\n    "
        val guardLine = if (adminGuard) "import ${VPNPanelService.ADMIN_GUARD_PATH}\n        " else ""
        val portal = if (sso) portalPaths(owner) else emptyList()
        if (portal.isNotEmpty() && publicPaths.isEmpty()) {
            return portalSplitSite(hostname, ownerLine + tlsLine, portal, guardLine, ssoLine, proxy)
        }
        if (publicPaths.isNotEmpty() && portal.isNotEmpty()) {
            return """
            @HOSTNAME@ {
                @OWNER@@TLS@@OPEN@ path @PATHS@
                @PORTAL@ path @PORTAL_PATHS@
                handle @OPEN@ {
                    @PROXY@
                }
                handle @PORTAL@ {
                    @GUARD@@SSO@@PROXY@
                }
                handle {
                    @GUARD@@PROXY@
                }
            }
            """.trimIndent().embedding("HOSTNAME" to hostname, "OWNER" to ownerLine,
                                       "TLS" to tlsLine,
                                       "OPEN" to "@$CADDY_PUBLIC_PATHS_MATCHER",
                                       "PATHS" to publicPaths.joinToString(" "),
                                       "PORTAL" to "@$PORTAL_PATHS_MATCHER",
                                       "PORTAL_PATHS" to portal.joinToString(" "),
                                       "GUARD" to guardLine,
                                       "SSO" to nested(ssoLine), "PROXY" to nested(proxy))
        }
        if (publicPaths.isNotEmpty() && (adminGuard || sso)) {
            return """
            @HOSTNAME@ {
                @OWNER@@TLS@@MATCHER@ path @PATHS@
                handle @MATCHER@ {
                    @PROXY@
                }
                handle {
                    @GUARD@@SSO@@PROXY@
                }
            }
            """.trimIndent().embedding("HOSTNAME" to hostname, "OWNER" to ownerLine,
                                       "TLS" to tlsLine,
                                       "MATCHER" to "@$CADDY_PUBLIC_PATHS_MATCHER",
                                       "PATHS" to publicPaths.joinToString(" "),
                                       "GUARD" to guardLine,
                                       "SSO" to nested(ssoLine), "PROXY" to nested(proxy))
        }
        if (!adminGuard) {
            return """
            @HOSTNAME@ {
                @OWNER@@TLS@@SSO@@PROXY@
            }
            """.trimIndent().embedding("HOSTNAME" to hostname, "OWNER" to ownerLine,
                                       "TLS" to tlsLine,
                                       "SSO" to ssoLine, "PROXY" to proxy)
        }
        return """
        @HOSTNAME@ {
            @OWNER@@TLS@import ${VPNPanelService.ADMIN_GUARD_PATH}
            @SSO@@PROXY@
        }
        """.trimIndent().embedding("HOSTNAME" to hostname, "OWNER" to ownerLine,
                                   "TLS" to tlsLine,
                                   "SSO" to ssoLine, "PROXY" to proxy)
    }

    const val CADDY_OWNER_TAG = "gryonixnexus:"

    /** Name of the matcher the public-path branch is selected by */
    const val CADDY_PUBLIC_PATHS_MATCHER = "gryonixnexus_open"

    /** Matcher for the paths the portal still covers */
    const val PORTAL_PATHS_MATCHER = "gryonixnexus_portal"

    /** Admin paths behind the portal; the rest signs in itself */
    fun portalPaths(owner: String): List<String> =
        if (owner != "mailcow") emptyList()
        else listOf("/admin", "/admin/*", "/domainadmin", "/domainadmin/*", "/rspamd", "/rspamd/*")

    /** A site whose portal covers only its admin paths */
    private fun portalSplitSite(
        hostname: String, head: String, paths: List<String>, guardLine: String, sso: String, proxy: String,
    ): String = """
        @HOSTNAME@ {
            @HEAD@@MATCHER@ path @PATHS@
            handle @MATCHER@ {
                @GUARD@@SSO@@PROXY@
            }
            handle {
                @GUARD@@PROXY@
            }
        }
        """.trimIndent().embedding("HOSTNAME" to hostname, "HEAD" to head,
                                   "MATCHER" to "@$PORTAL_PATHS_MATCHER",
                                   "PATHS" to paths.joinToString(" "), "GUARD" to guardLine,
                                   "SSO" to nested(sso), "PROXY" to nested(proxy))

    /** One more level of indent after every line break */
    private fun nested(block: String) = block.replace("\n", "\n    ")

    /** The Caddyfile's global block */
    val caddyGlobalOptions = "{\n\torder respond before forward_auth\n\tservers {\n\t\tprotocols h1 h2\n\t}\n}"

    fun caddyMergeProgram(indent: String): String =
        caddyMergeAWK.split("\n").joinToString("\n") { if (it.isEmpty()) "" else indent + it }

    /** The program [caddyMergeProgram] indents */
    val caddyMergeAWK = """
        function flush(   i, names, count, parts, id, line, keep) {
          if (n == 0) return
          names = block[1]
          sub(/[ \t]*\{[ \t]*${SH}/, "", names)
          if (pass == 1) {
            if (names != "") {
              header[block[1]] = 1
              count = split(names, parts, ",")
              for (i = 1; i <= count; i++) {
                gsub(/^[ \t]+|[ \t]+${SH}/, "", parts[i])
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
              gsub(/^[ \t]+|[ \t]+${SH}/, "", line)
              if (index(line, "# $CADDY_OWNER_TAG ") == 1) {
                id = substr(line, length("# $CADDY_OWNER_TAG ") + 1)
                gsub(/^[ \t]+|[ \t]+${SH}/, "", id)
                if (index("," ourids ",", "," id ",") > 0) keep = 0
              }
            }
          }
          if (keep) {
            count = split(names, parts, ",")
            for (i = 1; i <= count; i++) {
              gsub(/^[ \t]+|[ \t]+${SH}/, "", parts[i])
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
        /^[ \t]*${SH}/ { flush(); next }
        { block[++n] = ${SH}0 }
        END { flush(); if (clashes != "") print clashes }
        """.trimIndent()

    /** Writes /etc/caddy/Caddyfile from the web services and restarts Caddy */
    fun writeCaddyfile(context: MailContext): String {
        val rendered = context.webServices.mapNotNull { service ->
            val ingress = service.webIngress(context.serviceContext) ?: return@mapNotNull null
            val names = (listOf(ingress.hostname) + context.mirroredHostnames(ingress.hostname))
                .joinToString(", ")
            val sso = ServiceID.AUTHELIA in context.serviceContext.installedServices &&
                AutheliaService.guards(service.id, context.serviceContext.settings)
            val site = caddySite(
                owner = service.id.rawValue, hostname = names, upstreamPort = ingress.upstreamPort,
                adminGuard = ingress.adminGuard, upstreamHTTPS = ingress.upstreamHTTPS,
                tlsInternal = context.usesInternalTLS, sso = sso,
                publicPaths = ingress.publicPaths,
                overwriteForwardedFor = ingress.overwriteForwardedFor
            )
            val installed = context.serviceContext.installedServices
            service.id.rawValue to CaddySetupGuard.guarding(site, service.id.rawValue, installed)
        }
        val sites = rendered.map { it.second }
        val ownedIDs = rendered.joinToString(",") { it.first }
        val armed = CaddySetupGuard.armSection(
            rendered.filter { it.second.contains(CaddySetupGuard.importLine(it.first)) }.map { it.first }
        )
        return """
        log "${L10nScripts.caddyReverseProxyLog(context.language)}"
        # Every site imports the admin guard, so the file must exist even when
        # no VPN panel installs the lockdown wrapper (empty = public; re-runs
        # keep the current state — a missing import is a fatal Caddy error).
        # Mode spelled out rather than left to the umask: caddy runs as its own
        # user and cannot read a root-only /etc/caddy at all.
        install -d -m 755 /etc/caddy
        [ -f ${VPNPanelService.ADMIN_GUARD_PATH} ] || : > ${VPNPanelService.ADMIN_GUARD_PATH}@ARMED@
        cat > /etc/caddy/Caddyfile.gryonixnexus <<'EOF_CADDYFILE'
        @SITES@
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
          caddy_clash=${SH}(awk -v ourids='$ownedIDs' \
                            -v out=/etc/caddy/Caddyfile.gryonixnexus-kept '
        @CADDY_MERGE_PROGRAM@
          ' /etc/caddy/Caddyfile.gryonixnexus /etc/caddy/Caddyfile)
          if [ -n "${SH}caddy_clash" ]; then
            rm -f /etc/caddy/Caddyfile.gryonixnexus /etc/caddy/Caddyfile.gryonixnexus-kept
            fail "${L10nScripts.caddyNameAlreadyServed(context.language)}: ${SH}caddy_clash"
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
          fail "${L10nScripts.caddyDidNotStart(context.language)}"
        fi
        """.trimIndent().embedding(
            "SITES" to (caddyGlobalOptions + "\n\n" + sites.joinToString("\n\n")),
            "ARMED" to armed,
            "CADDY_MERGE_PROGRAM" to caddyMergeProgram(indent = "    ")
        )
    }

    fun composeSetup(service: ManagedService, context: MailContext): String {
        val compose = service.composeFile(context.serviceContext)
        // The service manages its own install (mailcow: git clone + generate_config.sh).
            ?: return service.setupSteps(context.serviceContext).joinToString("\n\n")
        val tag = service.id.rawValue.uppercase().replace("-", "_")
        val sections = mutableListOf(
            """
            log "${service.displayName}: docker-compose"
            # Mode spelled out, not left to the umask: containers that drop to
            # a non-root user mount from here, and .env carries its own 600.
            install -d -m 755 ${compose.directory}
            @COMPOSE@
            """.trimIndent().embedding(
                "COMPOSE" to BashSections.writeFile(
                    path = "${compose.directory}/docker-compose.yml",
                    contents = compose.composeContents,
                    delimiter = "EOF_COMPOSE_$tag"
                )
            )
        )
        compose.envTemplate?.let { envTemplate ->
            sections.add("""
            if [ ! -f "${compose.directory}/.env" ]; then
              @ENV@
              while IFS= read -r line; do
                case "${SH}line" in
                  *__RANDOM__*) printf '%s\n' "${SH}{line/__RANDOM__/${SH}(openssl rand -hex 24)}" ;;
                  *) printf '%s\n' "${SH}line" ;;
                esac
              done < "${compose.directory}/.env.template" > "${compose.directory}/.env"
              rm -f "${compose.directory}/.env.template"
            fi
            chmod 600 "${compose.directory}/.env"
            """.trimIndent().embedding(
                "ENV" to BashSections.writeFile(
                    path = "${compose.directory}/.env.template",
                    contents = envTemplate,
                    delimiter = "EOF_ENV_$tag"
                )
            ))
        }
        sections.addAll(withPortVerification(service, context))
        return sections.joinToString("\n\n")
    }

    fun withPortVerification(service: ManagedService, context: MailContext): List<String> {
        val steps = service.setupSteps(context.serviceContext)
        val argument = PortPreflightSections.verifyArgument(service, context)
        val project = (service.runtime as? ServiceRuntime.Docker)?.composeProject
        if (argument.isEmpty() || project == null) return steps
        val check = """
            gd_pp_verify $project "$argument" "${service.displayName}"
            gd_pp_settled $project "${service.displayName}"
        """.trimIndent()
        val index = steps.indexOfFirst { "up -d" in it }
        if (index < 0) return steps + check
        val withCheck = steps.toMutableList()
        withCheck.add(index + 1, check)
        return withCheck
    }

    fun allSections(context: MailContext): List<String> {
        if (!context.needsDocker) return emptyList()
        val sections = mutableListOf(installDocker(context.language))
        sections.addAll(context.allSelectedServices.map { composeSetup(it, context) })
        vpnPanelServicesJSON(context)?.let { sections.add(it) }
        if (context.needsCaddy) {
            sections.add(installCaddy(context.distributionProfile(context.mailHostRole),
                                      context.language))
            sections.add(writeCaddyfile(context))
        }
        return sections
    }

    internal fun vpnPanelServicesJSON(context: MailContext): String? {
        if (context.input.services.none { it in ServiceID.VPN_PROTOCOLS }) return null
        val s = context.serviceContext.settings
        val vhost = s.vpnHostname.ifEmpty { "vpn.${context.domainName}" }
        val entries = mutableListOf<String>()
        fun add(svc: ServiceID, jsonID: String, name: String, port: Int, proto: String) {
            if (svc !in context.input.services) return
            val endpoint = "$vhost:$port · $proto"
            entries.add("""{"id":"$jsonID","name":"$name","endpoint":"$endpoint","host":"$vhost","port":"$port"}""")
        }
        add(ServiceID.WIREGUARD_VPN, "wireguard", "WireGuard", s.wireguardVPNPort, "UDP")
        add(ServiceID.AMNEZIA_WG, "amneziawg", "AmneziaWG", VPNPortShare.clientPort(context.serviceContext), "UDP")
        add(ServiceID.SHADOWSOCKS, "shadowsocks", "Shadowsocks", s.shadowsocksPort, "TCP+UDP")
        add(ServiceID.XRAY_REALITY, "xray", "VLESS / Reality", s.xrayRealityPort, "TCP")
        add(ServiceID.OPEN_VPN, "openvpn", "OpenVPN", s.openVPNPort, "UDP")
        val json = """{"services":[${entries.joinToString(",")}]}"""
        return """
        log "VPN Panel: services.json"
        install -d ${VPNPanelService.PATH}/data
        @SERVICES@
        docker restart ${VPNPanelService.CONTAINER_NAME} >/dev/null 2>&1 || true
        @SHARE@
        """.trimIndent().embedding(
            "SERVICES" to BashSections.writeFile(
                path = "${VPNPanelService.PATH}/data/services.json",
                contents = json,
                delimiter = "EOF_VPNPANEL_SVC"
            ),
            "SHARE" to VPNPortShare.section(context.serviceContext),
        )
    }

    /** Report for a server without mail: statuses + service access credentials */
    fun standaloneReport(context: MailContext, extraLines: List<String> = emptyList()): String {
        val language = context.language
        val extra = if (extraLines.isEmpty()) "" else
            extraLines.joinToString("\n") { "echo \"$it\"" } + "\n"
        val dnsReminder = if (context.publishesAddressRecords)
            "echo \"${L10nScripts.caddyDNSReminder(language)}\"\n\n" else ""
        return """
        log "${L10nScripts.reportTitle(language)}"
        echo "${L10nScripts.domainLabel(language)}${context.domainName}"
        @EXTRA@echo
        echo "${L10nScripts.serviceStatusHeader(language)}"
        for s in nftables docker caddy; do
          printf '  %-14s %s\n' "${SH}s" "${SH}(systemctl is-active "${SH}s" || true)"
        done
        echo
        @DNS@@SERVICES@
        """.trimIndent().embedding(
            "EXTRA" to extra, "DNS" to dnsReminder, "SERVICES" to servicesReport(context)
        )
    }

    fun hostNeedsBackupPassphrase(context: MailContext): Boolean =
        context.input.dashboardAccess != null &&
            BackupControlSections.needsStoredPassphrase(context.allSelectedServices,
                                                        context.serviceContext)

    fun servicesReport(context: MailContext): String {
        val steps = context.allSelectedServices.flatMap { it.reportSteps(context.serviceContext) }
        if (steps.isEmpty()) return ""
        return (listOf("""
        echo
        echo "${L10nScripts.serviceCredentialsHeader(context.language)}"
        """.trimIndent()) + steps).joinToString("\n")
    }
}
