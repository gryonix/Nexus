package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.embedding
import com.skaymer.gryonixnexus.catalog.services.VPNPanelService
import com.skaymer.gryonixnexus.core.WireGuardDefaults

/** Generates the root-owned uninstall wrapper */
internal object UninstallSections {
    const val SCRIPT_PATH = "/opt/gryonixnexus-uninstall.sh"
    const val DONE_MARKER = "GRYONIXNEXUS_UNINSTALL_DONE"

    const val VPN_TARGET = "vpn"
    const val ALL_TARGET = "--all"

    const val PURGE_DATA_FLAG = "--purge-data"
    const val PURGE_BACKUPS_FLAG = "--purge-backups"

    fun quotedPath(path: String): String =
        path.split("*").joinToString("*") { if (it.isEmpty()) "" else "'$it'" }

    fun purgeBlock(spec: UninstallSpec, indent: String): List<String> {
        val lines = mutableListOf<String>()
        val dataTargets = listOfNotNull(spec.configDirectory) + spec.dataPaths
        if (dataTargets.isNotEmpty()) {
            lines.add("${indent}if [ \"${SH}PURGE_DATA\" -eq 1 ]; then")
            for (target in dataTargets) lines.add("$indent  purge_path ${quotedPath(target)}")
            lines.add("${indent}fi")
        }
        if (spec.backupDirs.isNotEmpty()) {
            lines.add("${indent}if [ \"${SH}PURGE_BACKUPS\" -eq 1 ]; then")
            for (target in spec.backupDirs) lines.add("$indent  rm -rf ${quotedPath(target)}")
            lines.add("${indent}fi")
        }
        return lines
    }

    private fun sudoersOwners(services: List<ManagedService>, context: ServiceContext):
        Map<String, Set<ServiceID>> {
        val owners = mutableMapOf<String, MutableSet<ServiceID>>()
        for (service in services) {
            for (line in service.sudoersLines(context)) {
                owners.getOrPut(line) { mutableSetOf() }.add(service.id)
            }
        }
        return owners
    }

    private fun removableSudoersLines(
        unit: List<ManagedService>,
        owners: Map<String, Set<ServiceID>>,
        context: ServiceContext,
    ): List<String> {
        val unitIDs = unit.map { it.id }.toSet()
        val seen = mutableSetOf<String>()
        val result = mutableListOf<String>()
        for (service in unit) {
            for (line in service.sudoersLines(context)) {
                if (!seen.add(line)) continue
                val owningIDs = owners[line] ?: continue
                if (!unitIDs.containsAll(owningIDs)) continue
                result.add(line)
            }
        }
        return result
    }

    private fun sudoersRemovalCall(lines: List<String>): List<String> {
        if (lines.isEmpty()) return emptyList()
        val quoted = lines.map { "'$it'" }
        return listOf("  remove_sudoers_lines \\", "    " + quoted.joinToString(" \\\n    "))
    }

    /** The bash function body removing one service, from its UninstallSpec */
    private fun uninstallFunction(name: String, spec: UninstallSpec,
                                  siteHeaders: List<String>,
                                  sudoersLines: List<String> = emptyList()): String {
        val lines = mutableListOf("uninstall_$name() {")
        for (step in spec.preSteps) lines.add("  $step")
        spec.composeProject?.let { lines.add("  compose_down '$it'") }
        for (header in siteHeaders) lines.add("  remove_caddy_site '$header'")
        for (step in spec.postSteps) lines.add("  $step")
        lines += purgeBlock(spec, "  ")
        lines += sudoersRemovalCall(sudoersLines)
        lines.add("}")
        return lines.joinToString("\n")
    }

    private fun functionName(id: ServiceID): String = id.rawValue.replace("-", "_")

    private fun siteHeaders(service: ManagedService, context: MailContext): List<String> {
        val ingress = service.webIngress(context.serviceContext) ?: return emptyList()
        return listOf(
            (listOf(ingress.hostname) + context.mirroredHostnames(ingress.hostname))
                .joinToString(", ")
        )
    }

    fun servicesHostWrapper(access: DashboardAccessInput, context: MailContext,
                            includeWireGuard: Boolean): String {
        val serviceContext = context.serviceContext
        val sudoersContext = serviceContext.copy(sshUser = access.sshUser)
        val services = context.allSelectedServices
        val vpnServices = services.filter {
            it.id in ServiceID.VPN_PROTOCOLS || it.id == ServiceID.VPN_PANEL
        }
        val meshServices = services.filter {
            it.id == ServiceID.HEADSCALE || it.id == ServiceID.TAILSCALE_NODE
        }
        val appServices = services.filter {
            it.id !in ServiceID.VPN_PROTOCOLS && it.id != ServiceID.VPN_PANEL &&
                it.id != ServiceID.HEADSCALE && it.id != ServiceID.TAILSCALE_NODE
        }

        val functions = mutableListOf<String>()
        val caseArms = mutableListOf<String>()
        val allCalls = mutableListOf<String>()

        val sudoersOwnersByLine = sudoersOwners(services, sudoersContext)

        for (service in appServices) {
            val name = functionName(service.id)
            functions.add(uninstallFunction(name, service.uninstallSpec(serviceContext),
                                            siteHeaders(service, context),
                                            removableSudoersLines(listOf(service), sudoersOwnersByLine,
                                                                  sudoersContext)))
            caseArms.add("  ${service.id.rawValue}) uninstall_$name ;;")
            allCalls.add("  uninstall_$name")
        }

        if (meshServices.isNotEmpty()) {
            val meshLines = mutableListOf("uninstall_headscale() {")
            val seenProjects = mutableSetOf<String>()
            for (service in meshServices) {
                val spec = service.uninstallSpec(serviceContext)
                for (step in spec.preSteps) meshLines.add("  $step")
                val project = spec.composeProject
                if (project != null && seenProjects.add(project)) {
                    meshLines.add("  compose_down '$project'")
                }
                for (header in siteHeaders(service, context)) {
                    meshLines.add("  remove_caddy_site '$header'")
                }
                for (step in spec.postSteps) meshLines.add("  $step")
            }
            for (service in meshServices) {
                meshLines += purgeBlock(service.uninstallSpec(serviceContext), "  ")
            }
            meshLines += sudoersRemovalCall(
                removableSudoersLines(meshServices, sudoersOwnersByLine, sudoersContext)
            )
            meshLines.add("}")
            functions.add(meshLines.joinToString("\n"))
            caseArms.add("  ${ServiceID.HEADSCALE.rawValue}) uninstall_headscale ;;")
            allCalls.add("  uninstall_headscale")
        }

        if (vpnServices.isNotEmpty()) {
            val vpnLines = mutableListOf("uninstall_vpn() {")
            val seenProjects = mutableSetOf<String>()
            for (service in vpnServices) {
                val spec = service.uninstallSpec(serviceContext)
                for (step in spec.preSteps) vpnLines.add("  $step")
                val project = spec.composeProject
                if (project != null && seenProjects.add(project)) {
                    vpnLines.add("  compose_down '$project'")
                }
                for (header in siteHeaders(service, context)) {
                    vpnLines.add("  remove_caddy_site '$header'")
                }
                for (step in spec.postSteps) vpnLines.add("  $step")
            }
            for (service in vpnServices) {
                vpnLines += purgeBlock(service.uninstallSpec(serviceContext), "  ")
            }
            vpnLines += sudoersRemovalCall(
                removableSudoersLines(vpnServices, sudoersOwnersByLine, sudoersContext)
            )
            vpnLines.add("}")
            functions.add(vpnLines.joinToString("\n"))
            caseArms.add("  $VPN_TARGET) uninstall_vpn ;;")
            allCalls.add("  uninstall_vpn")
        }

        val tunnelCleanup = if (includeWireGuard) {
            (TunnelWatchdogSections.uninstallLines("  ") + listOf(
                "  systemctl disable --now wg-quick@${WireGuardDefaults.INTERFACE_NAME}" +
                    " >/dev/null 2>&1 || true",
                "  rm -f '/etc/wireguard/${WireGuardDefaults.INTERFACE_NAME}.conf'",
                "  # The oneshot that pinned the relay outside the tunnel. Stopping it",
                "  # takes the route with it (ExecStop), and the unit goes the way every",
                "  # other root-owned file this product wrote goes — the DDNS lesson.",
                "  systemctl disable --now gryonixnexus-tunnel-endpoint.service >/dev/null 2>&1 || true",
                "  rm -f /etc/systemd/system/gryonixnexus-tunnel-endpoint.service",
                "  systemctl daemon-reload || true",
                "  rm -f /etc/ssh/sshd_config.d/60-gryonixnexus-tunnel.conf",
                "  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true"
            ) + RelayRouteSyncSections.uninstallLines("  ") + listOf(
                "  rm -f /etc/sysctl.d/99-gryonixnexus-rpfilter.conf"
            )).joinToString("\n")
        } else {
            ""
        }

        val script = """
        #!/bin/bash
        # Managed by gryonixNexus — remove services or the whole gryonixNexus install.
        # Usage: gryonixnexus-uninstall.sh <service|$VPN_TARGET|$ALL_TARGET> [$PURGE_DATA_FLAG] [$PURGE_BACKUPS_FLAG]
        # Default keeps data and backups on disk; the flags delete them (independently).
        set -euo pipefail

        TARGET="${SH}{1:-}"
        PURGE_DATA=0
        PURGE_BACKUPS=0
        shift || true
        for arg in "${SH}@"; do
          case "${SH}arg" in
            $PURGE_DATA_FLAG) PURGE_DATA=1 ;;
            $PURGE_BACKUPS_FLAG) PURGE_BACKUPS=1 ;;
          esac
        done

        compose_down() {
          if [ "${SH}PURGE_DATA" -eq 1 ]; then
            # --rmi all also reclaims the images, but only the ones THIS
            # project's services use — the scoped replacement for the
            # `docker system prune -af` that used to run once at the end and
            # took every unused image and stopped container on the host with
            # it, ours or not. Images still referenced elsewhere are skipped
            # by docker itself.
            docker compose -p "${SH}1" down --remove-orphans --volumes --rmi all >/dev/null 2>&1 || true
          else
            docker compose -p "${SH}1" down --remove-orphans >/dev/null 2>&1 || true
          fi
        }

        # Unmounts fast storage bound inside each path, then deletes it.
        purge_path() {
          local target mount source
          for target in "${SH}@"; do
            [ -e "${SH}target" ] || continue
            while read -r mount; do
              source="${SH}(awk -v m="${SH}mount" '${SH}2 == m && ${SH}3 == "none" {print ${SH}1}' /etc/fstab)"
              umount "${SH}mount" 2>/dev/null || true
              sed -i "\|[[:space:]]${SH}{mount}[[:space:]]none[[:space:]]|d" /etc/fstab
              if [ -n "${SH}source" ]; then rm -rf "${SH}source"; fi
            done < <(awk -v t="${SH}target/" 'index(${SH}2, t) == 1 {print ${SH}2}' /proc/mounts | sort -r)
            rm -rf "${SH}target"
          done
        }

        # Removes one site block from the Caddyfile. The header is the exact
        # first line of the block as writeCaddyfile emits it (top-level `}` on
        # its own line closes it) — wrapper and Caddyfile are regenerated
        # together on every setup run, so the format cannot drift between them.
        remove_caddy_site() {
          local f=/etc/caddy/Caddyfile
          [ -f "${SH}f" ] || return 0
          awk -v start="${SH}1 {" '
            ${SH}0 == start {skip=1; next}
            skip && ${SH}0 == "}" {skip=0; next}
            !skip {print}
          ' "${SH}f" > "${SH}f.gryonixnexus" && mv "${SH}f.gryonixnexus" "${SH}f"
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
          [ -f "${SH}f" ] || return 0
          local tmp="${SH}f.gryonixnexus"
          printf '%s\n' "${SH}@" | grep -vFxf - "${SH}f" > "${SH}tmp" || true
          if [ -s "${SH}tmp" ] && visudo -cf "${SH}tmp" >/dev/null 2>&1; then
            mv "${SH}tmp" "${SH}f"
          else
            rm -f "${SH}tmp"
          fi
        }

        @FUNCTIONS@

        uninstall_all() {
        @ALL_CALLS@
        @UPDATE_UNINSTALL@
        @BACKUP_UNINSTALL@
        @DDNS_UNINSTALL@
        @AGENT_REMOVAL@
          # Host metrics collector + its history
          systemctl disable --now gryonixnexus-metrics >/dev/null 2>&1 || true
          rm -f /etc/systemd/system/gryonixnexus-metrics.service /opt/gryonixnexus-metrics-collector.sh
          systemctl daemon-reload || true
          rm -rf /var/lib/gryonixnexus
          # Caddy: only the sites this app wrote are removed
          rest="${SH}(mktemp)"
          { [ -f /etc/caddy/Caddyfile ] && awk '
            BEGIN{d=0;b="";own=0}
            d==0&&b==""&&index(${SH}0,"{")==0{print;next}
            {b=b ${SH}0 "\n"; if(index(${SH}0,"# gryonixnexus:"))own=1; t=${SH}0; o=gsub(/[{]/,"",t); t=${SH}0; c=gsub(/[}]/,"",t); d+=o-c;
             if(d<=0){ if(!own) printf "%s",b; b=""; own=0; d=0}}
            END{printf "%s",b}' /etc/caddy/Caddyfile > "${SH}rest"; } || : > "${SH}rest"
          if grep -Eq '^[^#[:space:]{}].*[{][[:space:]]*${SH}' "${SH}rest"; then
            cat "${SH}rest" > /etc/caddy/Caddyfile
            { caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1 && systemctl reload caddy >/dev/null 2>&1; } || true
          else
            systemctl disable --now caddy >/dev/null 2>&1 || true
            rm -f /etc/caddy/Caddyfile
          fi
          rm -f "${SH}rest" '${VPNPanelService.ADMIN_GUARD_PATH}'
        @TUNNEL_CLEANUP@
          # No host-wide `docker system prune` here: image reclamation is done
          # per compose project by compose_down --rmi all, which cannot
          # reach Docker state this deployment did not create.
          # Dashboard wrappers, then our own whitelist last — after this line
          # the app's sudo access is gone, which is the point.
          rm -f '${DashboardAccessSections.CONTAINER_CONTROL_SCRIPT_PATH}' '${DashboardAccessSections.RESTORE_SCRIPT_PATH}'
          # The agent bootstrap wrapper and whatever sources it unpacked. A
          # root-owned script the erase leaves behind is the DDNS lesson: the
          # erased machine still carrying something only root can remove.
          rm -f '${AgentBootstrapSections.SCRIPT_PATH}'
          rm -rf '${AgentBootstrapSections.UNPACK_ROOT}'
        @BACKUP_COPIES@
        @PASSWORD_AUTH_CLOSE@
        @APP_KEY_REMOVAL@
          rm -f /etc/sudoers.d/gryonixnexus-control
          rm -f '$SCRIPT_PATH'
        }

        case "${SH}TARGET" in
        @CASE_ARMS@
          $ALL_TARGET) uninstall_all ;;
          *) echo "unsupported target: ${SH}{TARGET}" >&2; exit 2 ;;
        esac
        echo '$DONE_MARKER'
        """.trimIndent().embedding(
            "FUNCTIONS" to functions.joinToString("\n\n"),
            "ALL_CALLS" to allCalls.joinToString("\n"),
            "UPDATE_UNINSTALL" to UpdateControlSections.uninstallLines("  ").joinToString("\n"),
            "BACKUP_UNINSTALL" to BackupControlSections.uninstallLines("  ").joinToString("\n"),
            "DDNS_UNINSTALL" to dynamicDNSUninstallLines("  ").joinToString("\n"),
            "AGENT_REMOVAL" to agentRemoval("  ").joinToString("\n"),
            "TUNNEL_CLEANUP" to tunnelCleanup,
            "BACKUP_COPIES" to backupCopyRemoval("  ", HOME_BACKUP_COPY_GLOBS),
            "PASSWORD_AUTH_CLOSE" to
                DashboardAccessSections.passwordAuthCloseUninstallLines("  ").joinToString("\n"),
            "APP_KEY_REMOVAL" to appKeyRemoval(access),
            "CASE_ARMS" to caseArms.joinToString("\n")
        )
        return installSection(script, context.language)
    }

    fun vpsWrapper(access: DashboardAccessInput, language: AppLanguage): String {
        val script = """
        #!/bin/bash
        # Managed by gryonixNexus — remove the gryonixNexus install from this relay.
        # Usage: gryonixnexus-uninstall.sh $ALL_TARGET
        set -euo pipefail

        TARGET="${SH}{1:-}"
        if [ "${SH}TARGET" != "$ALL_TARGET" ]; then
          echo "unsupported target: ${SH}{TARGET}" >&2; exit 2
        fi

        systemctl disable --now wg-quick@${WireGuardDefaults.INTERFACE_NAME} >/dev/null 2>&1 || true
        rm -f '/etc/wireguard/${WireGuardDefaults.INTERFACE_NAME}.conf'
        rm -f /etc/sysctl.d/99-gryonixnexus-forwarding.conf
        @AGENT_REMOVAL@
        systemctl disable --now gryonixnexus-metrics >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/gryonixnexus-metrics.service /opt/gryonixnexus-metrics-collector.sh
        systemctl daemon-reload || true
        rm -rf /var/lib/gryonixnexus
        @UPDATE_UNINSTALL@
        @BACKUP_UNINSTALL@
        @DDNS_UNINSTALL@
        @BACKUP_COPIES@
        @PASSWORD_AUTH_CLOSE@
        @APP_KEY_REMOVAL@
        rm -f /etc/sudoers.d/gryonixnexus-control
        rm -f '$SCRIPT_PATH'
        echo '$DONE_MARKER'
        """.trimIndent().embedding(
            "AGENT_REMOVAL" to agentRemoval("").joinToString("\n"),
            "UPDATE_UNINSTALL" to UpdateControlSections.uninstallLines("").joinToString("\n"),
            "BACKUP_UNINSTALL" to BackupControlSections.uninstallLines("").joinToString("\n"),
            "DDNS_UNINSTALL" to dynamicDNSUninstallLines("").joinToString("\n"),
            "BACKUP_COPIES" to backupCopyRemoval("", VPS_BACKUP_COPY_GLOBS),
            "PASSWORD_AUTH_CLOSE" to
                DashboardAccessSections.passwordAuthCloseUninstallLines("").joinToString("\n"),
            "APP_KEY_REMOVAL" to appKeyRemoval(access)
        )
        return installSection(script, language)
    }

    /** Paths the control-plane agent's bootstrap puts on a host */
    private const val AGENT_UNIT = "gryonixnexusd.service"
    private const val AGENT_BINARY_PATH = "/usr/local/bin/gryonixnexusd"
    private const val AGENT_SOCKET_PATH = "/run/gryonixnexusd.sock"

    private const val AGENT_STATE_DIRECTORY = "/var/lib/gryonixnexus/agent"

    private const val AGENT_MDNS_UNIT = "gryonixnexus-mdns.service"
    private const val AGENT_MDNS_SCRIPT = "/usr/local/lib/gryonixnexus/mdns-aliases.sh"
    private const val AGENT_HOME_NETWORK_SNIPPET = "/etc/caddy/gryonixnexus-home-network.caddy"
    private const val PREDECESSOR_UNIT = "gryonixnexus.service"
    private const val PREDECESSOR_BINARY_PATH = "/usr/local/bin/gryonixd"
    private const val PREDECESSOR_SOCKET_PATH = "/run/gryonixd.sock"

    /** Dynamic DNS: the updater, its units and its configuration */
    fun dynamicDNSUninstallLines(indent: String): List<String> = listOf(
        "$indent# Dynamic DNS: the timer is armed by the panel long after setup,",
        "$indent# so it outlives the services unless it is stopped here.",
        "${indent}systemctl disable --now 'gryonixnexus-ddns.timer' >/dev/null 2>&1 || true",
        "${indent}rm -f /etc/systemd/system/gryonixnexus-ddns.timer " +
            "/etc/systemd/system/gryonixnexus-ddns.service",
        "${indent}rm -f '/etc/gryonixnexus/ddns.conf' '/var/lib/gryonixnexus/ddns-status.txt'",
        "${indent}rm -f '/opt/gryonixnexus-ddns.sh'"
    )

    private fun agentRemoval(indent: String): List<String> {
        fun unitRemoval(unit: String, binary: String, socket: String): List<String> = listOf(
            "${indent}if [ -f /etc/systemd/system/$unit ]; then",
            "$indent  systemctl disable --now '$unit' >/dev/null 2>&1 || true",
            "$indent  rm -f '/etc/systemd/system/$unit'",
            "$indent  systemctl daemon-reload || true",
            "${indent}fi",
            "${indent}rm -f '$binary' '$socket'"
        )
        return listOf(
            "$indent# Control-plane agent: installed by its own bootstrap, outside this",
            "$indent# setup, and therefore invisible to everything else here. Stopped",
            "$indent# before the state directory below is removed — the unit's",
            "$indent# StateDirectory= re-creates it on every start."
        ) + unitRemoval(AGENT_UNIT, AGENT_BINARY_PATH, AGENT_SOCKET_PATH) + listOf(
            "${indent}rm -rf '$AGENT_STATE_DIRECTORY'",
            "$indent# The agent's mDNS names and home-network doors.",
            "${indent}systemctl disable --now '$AGENT_MDNS_UNIT' >/dev/null 2>&1 || true",
            "${indent}rm -f '/etc/systemd/system/$AGENT_MDNS_UNIT' '$AGENT_MDNS_SCRIPT' '$AGENT_HOME_NETWORK_SNIPPET'",
            "$indent# The agent's system updater and its start and shutdown units.",
            "${indent}systemctl disable --now 'gryonixnexus-update-at-start.service' >/dev/null 2>&1 || true",
            "${indent}rm -f '/etc/gryonixnexus/update-at-start.conf'",
            "${indent}systemctl disable --now 'gryonixnexus-update-at-stop.service' >/dev/null 2>&1 || true",
            "${indent}systemctl disable --now 'gryonixnexus-system-scheduled.timer' >/dev/null 2>&1 || true",
            "${indent}rm -f '/opt/gryonixnexus-system-ctl.sh' '/etc/systemd/system/gryonixnexus-update-at-start.service' '/etc/systemd/system/gryonixnexus-update-at-stop.service' '/var/log/gryonixnexus-system-update.log'",
            "${indent}rm -f '/etc/systemd/system/gryonixnexus-system-scheduled.timer' '/etc/systemd/system/gryonixnexus-system-scheduled.service' '/etc/gryonixnexus/system-schedule.conf'",
            "$indent# The daemon before the rename (gryonixd). install-agent.sh removes",
            "$indent# it, but a host that never re-ran the bootstrap still has it, and",
            "$indent# its unit is Restart=always too."
        ) + unitRemoval(PREDECESSOR_UNIT, PREDECESSOR_BINARY_PATH, PREDECESSOR_SOCKET_PATH)
    }

    /** Removes the `<path>.bak.<epoch>` copies the setup leaves behind */
    private fun backupCopyRemoval(indent: String, globs: List<String>): String = listOf(
        "$indent# Backup copies the setup makes before overwriting a managed file.",
        "${indent}rm -f ${globs.joinToString(" ")} || true"
    ).joinToString("\n")

    private val SHARED_BACKUP_COPY_GLOBS = listOf(
        "/etc/nftables.conf.bak.*",
        "/etc/wireguard/wg0.conf.bak.*",
        "/etc/systemd/system/gryonixnexus-*.service.bak.*"
    )

    /** Managed-file backup copies on the host that runs the services */
    private val HOME_BACKUP_COPY_GLOBS = SHARED_BACKUP_COPY_GLOBS + listOf(
        "/opt/gryonixnexus-*.bak.*",
        "/opt/vaultwarden-update.sh.bak.*",
        "/etc/caddy/Caddyfile.bak.*",
        "/etc/systemd/system/gryonixnexus-*.timer.bak.*",
        "/etc/sysctl.d/99-gryonixnexus-rpfilter.conf.bak.*"
    )

    private val VPS_BACKUP_COPY_GLOBS = SHARED_BACKUP_COPY_GLOBS + listOf(
        "/opt/gryonixnexus-*.bak.*",
        "/etc/sysctl.d/99-gryonixnexus-forwarding.conf.bak.*"
    )

    private fun appKeyRemoval(access: DashboardAccessInput): String {
        if (!access.createUser) return "  :"
        return """
        APP_KEY='${access.appPublicKey}'
        USER_HOME="${SH}(getent passwd '${access.sshUser}' | cut -d: -f6 || true)"
        if [ -n "${SH}USER_HOME" ] && [ -f "${SH}USER_HOME/.ssh/authorized_keys" ]; then
          grep -vxF "${SH}APP_KEY" "${SH}USER_HOME/.ssh/authorized_keys" > "${SH}USER_HOME/.ssh/authorized_keys.gryonixnexus" || true
          mv "${SH}USER_HOME/.ssh/authorized_keys.gryonixnexus" "${SH}USER_HOME/.ssh/authorized_keys"
          chmod 600 "${SH}USER_HOME/.ssh/authorized_keys"
          # Root wrote the replacement, and sshd reads authorized_keys as
          # the account: leaving it root-owned makes the file unreadable to
          # sshd and kills every OTHER key the account has. Same reason the
          # revoke step chowns; see revokeInstallKey.
          chown '${access.sshUser}' "${SH}USER_HOME/.ssh/authorized_keys"
        fi
        """.trimIndent().prependIndent("  ")
    }

    private fun installSection(script: String, language: AppLanguage): String = """
        log "${L10nScripts.uninstallWrapperLog(language)}"
        @SCRIPT_FILE@
        chmod 750 '$SCRIPT_PATH'
        """.trimIndent().embedding(
        "SCRIPT_FILE" to BashSections.writeFile(SCRIPT_PATH, script, "EOF_UNINSTALL")
    )
}
