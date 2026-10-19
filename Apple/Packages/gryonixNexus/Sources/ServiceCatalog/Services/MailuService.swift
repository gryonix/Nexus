public struct MailuService: MailEngineService {
    public static let composeProject = "mailu"
    /// Loopback port Caddy proxies to
    public static let webUIPort = 8085
    public static let frontService = "front"
    public static let adminService = "admin"
    public static let adminRunAsUser = "mailu"
    public static let wrapperTarget = ServiceID.mailu.rawValue
    /// One CalVer line, patches included
    public static let imageTag = "2024.06"
    public enum Component: String, CaseIterable, Sendable {
        case nginx, unbound, admin, dovecot, postfix, rspamd, webmail
    }
    public static func image(_ component: Component) -> String {
        "ghcr.io/mailu/\(component.rawValue):\(imageTag)"
    }
    /// Session store and rspamd's backend
    public static let cacheImage = "redis:8-alpine"

    /// Sync script + timer that copy Caddy's certificate into Mailu
    public static let certSyncScriptPath = "/opt/gryonixnexus-mailu-cert-sync.sh"
    public static let certSyncUnit = "gryonixnexus-mailu-cert-sync"
    /// Root-owned DKIM dump for the app's configuration export, mirroring mailcow's
    public static let dkimDumpScriptPath = "/opt/gryonixnexus-mailu-dkim.sh"
    public static let dkimMarker = "GRYONIXNEXUS_DKIM"
    public static let dkimDumpDoneMarker = "GRYONIXNEXUS_DKIM_DONE"

    public let id = ServiceID.mailu
    public let displayName = "Mailu"
    public let systemImage = "envelope.badge.shield.half.filled"
    /// One mail stack at a time
    public let category = ServiceCategory.mail
    public let usesSharedAdminLogin = true
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 1536, diskGB: 6)

    public init() {}

    public func requiredHostname(forDomain domain: String) -> String? {
        "mail.\(domain)"
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.mailuPath
        let subnet = context.settings.mailuSubnet
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              redis:
                image: \(Self.cacheImage)
                restart: unless-stopped
                volumes:
                  - \(path)/redis:/data
              front:
                image: \(Self.image(.nginx))
                restart: unless-stopped
                env_file: .env
                logging:
                  driver: json-file
                ports:
                  # The web UI stays on loopback behind Caddy; the mail ports
                  # are the only public binds, and they are not proxyable —
                  # SMTP and IMAP are not HTTP.
                  #
                  # 143 and 587 are deliberately absent, not forgotten: the
                  # front's dovecot proxy gates those two listeners behind
                  # PORT_143/PORT_587 and binds them to port 0 when unset,
                  # which is the case here — unlike 465/993/4190, which it
                  # always enables. Publishing a dead port would still open
                  # the public interface, because docker publishes through
                  # its own DNAT, past the firewall.
                  - "127.0.0.1:\(Self.webUIPort):80"
                  - "25:25"
                  - "465:465"
                  - "993:993"
                  - "4190:4190"
                volumes:
                  - \(path)/certs:/certs
                  - \(path)/overrides/nginx:/overrides:ro
              resolver:
                image: \(Self.image(.unbound))
                env_file: .env
                restart: unless-stopped
                networks:
                  default:
                    ipv4_address: \(Self.resolverAddress(subnet: subnet))
              admin:
                image: \(Self.image(.admin))
                restart: unless-stopped
                env_file: .env
                volumes:
                  - \(path)/data:/data
                  - \(path)/dkim:/dkim
                depends_on:
                  - redis
                  - resolver
                dns:
                  - \(Self.resolverAddress(subnet: subnet))
              imap:
                image: \(Self.image(.dovecot))
                restart: unless-stopped
                env_file: .env
                volumes:
                  - \(path)/mail:/mail
                  - \(path)/overrides:/overrides:ro
                depends_on:
                  - front
                  - resolver
                dns:
                  - \(Self.resolverAddress(subnet: subnet))
              smtp:
                image: \(Self.image(.postfix))
                restart: unless-stopped
                env_file: .env
                volumes:
                  - \(path)/mailqueue:/queue
                  - \(path)/overrides:/overrides:ro
                depends_on:
                  - front
                  - resolver
                dns:
                  - \(Self.resolverAddress(subnet: subnet))
              antispam:
                image: \(Self.image(.rspamd))
                restart: unless-stopped
                env_file: .env
                volumes:
                  - \(path)/filter:/var/lib/rspamd
                  - \(path)/overrides/rspamd:/etc/rspamd/override.d:ro
                depends_on:
                  - front
                  - redis
                  - resolver
                dns:
                  - \(Self.resolverAddress(subnet: subnet))
              webmail:
                image: \(Self.image(.webmail))
                restart: unless-stopped
                env_file: .env
                volumes:
                  - \(path)/webmail:/data
                  - \(path)/overrides/roundcube:/overrides:ro
                depends_on:
                  - front

            networks:
              default:
                driver: bridge
                ipam:
                  config:
                    # Fixed on purpose: SUBNET below has to name the range
                    # docker really used, and letting docker choose it would
                    # make the two disagree the first time the pool shifts.
                    - subnet: \(subnet)
            """,
            envTemplate: Self.envTemplate(context)
        )
    }

    static func resolverAddress(subnet: String) -> String {
        host(in: subnet, last: "254")
    }

    static func gatewayAddress(subnet: String) -> String {
        host(in: subnet, last: "1")
    }

    private static func host(in subnet: String, last: String) -> String {
        let base = subnet.split(separator: "/").first.map(String.init) ?? subnet
        var octets = base.split(separator: ".").map(String.init)
        guard octets.count == 4 else { return base }
        octets[3] = last
        return octets.joined(separator: ".")
    }

    private static func envTemplate(_ context: ServiceContext) -> String {
        let hostname = "mail.\(context.domain)"
        let admin = context.settings.adminUsername
        let hostnames = ([context.domain] + context.additionalDomains)
            .map { "mail.\($0)" }
            .joined(separator: ",")
        return """
        # Managed by gryonixNexus. Generated on the server; secrets are the
        # __RANDOM__ markers, replaced once and then left alone on re-runs.
        SECRET_KEY=__RANDOM__
        DOMAIN=\(context.domain)
        HOSTNAMES=\(hostnames)
        POSTMASTER=postmaster
        # See the type comment: Caddy owns 80/443 and the ACME account, so Mailu
        # serves plain HTTP for the proxy and uses the synced certificate for
        # SMTP/IMAP only.
        TLS_FLAVOR=mail
        SUBNET=\(context.settings.mailuSubnet)
        # The first administrator is created by the stack itself. `ifmissing`
        # rather than `update`: a re-run of setup must not reset a password the
        # owner has since changed.
        INITIAL_ADMIN_ACCOUNT=\(admin)
        INITIAL_ADMIN_DOMAIN=\(context.domain)
        INITIAL_ADMIN_PW=__RANDOM__
        INITIAL_ADMIN_MODE=ifmissing
        # Behind a proxy Mailu would otherwise log and rate-limit Caddy's
        # address instead of the client's.
        #
        # The trusted address is the BRIDGE GATEWAY, not 127.0.0.1: Caddy
        # connects to a published port on the host, and the container sees that
        # connection arriving from the docker network's gateway. This is the
        # same trap as mailcow's API_ALLOW_FROM — a loopback
        # value here does not fail loudly, it silently makes every client look
        # like the proxy, which means the per-IP rate limit bans everyone at
        # once the first time one client gets a password wrong.
        REAL_IP_HEADER=X-Forwarded-For
        REAL_IP_FROM=\(Self.gatewayAddress(subnet: context.settings.mailuSubnet))
        WEBROOT_REDIRECT=/webmail
        # ADMIN gates the admin interface ITSELF, WEB_ADMIN only says where it
        # would live. Without this the nginx template renders no location for
        # it at all: /admin falls through to WEBROOT_REDIRECT and lands on the
        # webmail, which reads as "the admin UI is broken". The setup report points at /admin.
        ADMIN=true
        WEB_ADMIN=/admin
        WEB_WEBMAIL=/webmail
        WEBMAIL=roundcube
        WEBDAV=none
        # Off deliberately: ClamAV alone wants about a gigabyte of RAM, which is
        # most of a small server's headroom. Rspamd still filters spam.
        ANTIVIRUS=none
        MESSAGE_SIZE_LIMIT=50000000
        RECIPIENT_DELIMITER=+
        DMARC_RUA=postmaster
        DMARC_RUF=postmaster
        COMPOSE_PROJECT_NAME=\(composeProject)
        MAILU_HOSTNAME=\(hostname)
        """
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.mailuPath
        let lang = context.language
        let hostname = "mail.\(context.domain)"
        let domains = [context.domain] + context.additionalDomains
        let domainYAML = domains.map { "  - name: \($0)\n    dkim_key: -generate-" }
            .joined(separator: "\n")
        return [
            #"""
            log "Mailu: \#(L10nServices.serviceStarting(lang))"
            # 0700 on the trees that hold mail and keys: the containers run as
            # their own uids and do not need host accounts reading them.
            #
            # Root-owned is CORRECT here and must stay that way — this is NOT
            # Passbolt's bind-mount trap. Every Mailu image starts as root and
            # chowns its own mounts before dropping privileges (`admin` runs
            # `find /data | xargs -n1 chown mailu:mailu` and `chown -R
            # mailu:mailu /dkim`, `webmail` runs `chown -R mailu:mailu /data`),
            # so a host-side chown here would only guess at uids the image
            # already assigns itself. Read out of the pinned images.
            install -d -m 755 \#(path)
            install -d -m 700 \#(path)/certs \#(path)/dkim \#(path)/data
            install -d -m 755 \#(path)/mail \#(path)/mailqueue \#(path)/filter \#(path)/webmail \#(path)/redis
            install -d -m 755 \#(path)/overrides \#(path)/overrides/nginx \#(path)/overrides/rspamd \#(path)/overrides/roundcube
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#,
            certSyncStep(context),
            #"""
            # Domains and DKIM keys. Nothing here is fatal and no output is
            # discarded — the same rule the mailcow API and Nextcloud occ
            # blocks follow: errexit in the middle of this step would take the
            # remaining services and the revocation of the install key with it,
            # and a mail domain is fixable from the admin UI afterwards.
            # Its own cd: sections share one shell and the working directory
            # persists across them, so relying on an earlier step's cd is a
            # dependency nobody can see when the steps are reordered.
            cd \#(path)
            MU_OUT=""
            # `-u`: never as root — see `adminRunAsUser`. A root exec here
            # creates /data/main.db before the engine does, and the engine
            # then cannot write its own schema into it.
            mu_exec() { MU_OUT="$(timeout 120 docker compose -p \#(Self.composeProject) exec -T -u \#(Self.adminRunAsUser) \#(Self.adminService) "$@" 2>&1)"; }
            mu_why() { printf '%s' "$MU_OUT" | tr -d '\r\n' | cut -c1-300; }
            # A deadline, not a number of attempts: each attempt can burn its
            # own timeout, so counting attempts leaves the real wait unbounded.
            # `flask mailu config-export` has to reach the database, which is
            # what is actually not ready yet while the containers report up.
            MU_READY=0
            MU_TRY=0
            MU_DEADLINE=$(($(date +%s) + 300))
            while [ "$(date +%s)" -lt "$MU_DEADLINE" ]; do
              if mu_exec flask mailu config-export -j; then MU_READY=1; break; fi
              MU_TRY=$((MU_TRY + 1))
              # Heartbeat every ~30 s: silence here is indistinguishable from a
              # hung install in the app's progress view.
              if [ "$((MU_TRY % 6))" -eq 0 ]; then
                log "\#(L10nServices.mailuWaiting(lang)) ($(mu_why))"
              fi
              sleep 5
            done
            if [ "$MU_READY" -eq 1 ]; then
              # `-u` is merge mode, and it is not optional: without it the
              # input is treated as the configuration rather than an addition
              # to it. `-q` because the app streams this log.
              #
              # The key is `domain`, singular — the same name the export uses.
              # A plural one is not an error the tool reports, it is simply a
              # section nothing reads, so the keys would never be minted.
              #
              # Idempotent for this shape: `-generate-` mints a key only where
              # there is none, so a re-run leaves existing keys alone.
              if ! printf '%s\n' 'domain:' '\#(domainYAML)' \
                   | timeout 120 docker compose -p \#(Self.composeProject) exec -T -u \#(Self.adminRunAsUser) \#(Self.adminService) \
                     flask mailu config-import -q -u >/dev/null 2>&1; then
                log "\#(L10nServices.mailuDomainImportFailed(lang))"
              fi
            else
              log "\#(L10nServices.mailuUnavailable(lang)) ($(mu_why))"
            fi
            """#,
            dkimDumpStep(context, hostname: hostname)
        ]
    }

    private func certSyncStep(_ context: ServiceContext) -> String {
        let path = context.settings.mailuPath
        let hostname = "mail.\(context.domain)"
        return #"""
        cat > \#(Self.certSyncScriptPath) <<'EOF_MU_CERTSYNC'
        #!/bin/bash
        set -eu
        DOMAIN="\#(hostname)"
        MAILU="\#(path)"
        DEST="$MAILU/certs"
        CADDY_DATA="/var/lib/caddy/.local/share/caddy/certificates"
        SRC_CRT="$(find "$CADDY_DATA" -type f -name "${DOMAIN}.crt" 2>/dev/null | head -n1)"
        SRC_KEY="$(find "$CADDY_DATA" -type f -name "${DOMAIN}.key" 2>/dev/null | head -n1)"
        # No certificate yet (ACME still pending) is not an error: the timer
        # comes back every hour and the mail ports keep serving the old one.
        if [ -z "$SRC_CRT" ] || [ -z "$SRC_KEY" ]; then exit 0; fi
        if cmp -s "$SRC_CRT" "$DEST/cert.pem" && cmp -s "$SRC_KEY" "$DEST/key.pem"; then exit 0; fi
        cp "$SRC_CRT" "$DEST/cert.pem"
        cp "$SRC_KEY" "$DEST/key.pem"
        chmod 600 "$DEST/cert.pem" "$DEST/key.pem"
        cd "$MAILU"
        # Only the services that terminate TLS themselves; restarting the whole
        # project would drop deliveries in flight for nothing.
        docker compose -p \#(Self.composeProject) restart \#(Self.frontService) >/dev/null 2>&1 || true
        EOF_MU_CERTSYNC
        chmod 700 \#(Self.certSyncScriptPath)
        cat > /etc/systemd/system/\#(Self.certSyncUnit).service <<'EOF_MU_CERTSVC'
        [Unit]
        Description=Sync Caddy TLS certificate into Mailu (SMTP/IMAPS)
        After=docker.service
        [Service]
        Type=oneshot
        ExecStart=\#(Self.certSyncScriptPath)
        EOF_MU_CERTSVC
        cat > /etc/systemd/system/\#(Self.certSyncUnit).timer <<'EOF_MU_CERTTIMER'
        [Unit]
        Description=Periodic Caddy to Mailu TLS certificate sync
        [Timer]
        OnActiveSec=5min
        OnUnitActiveSec=1h
        Persistent=true
        [Install]
        WantedBy=timers.target
        EOF_MU_CERTTIMER
        systemctl daemon-reload
        systemctl enable --now \#(Self.certSyncUnit).timer >/dev/null 2>&1 || true
        \#(Self.certSyncScriptPath) || true
        """#
    }

    private func dkimDumpStep(_ context: ServiceContext, hostname: String) -> String {
        let path = context.settings.mailuPath
        return #"""
        cat > \#(Self.dkimDumpScriptPath) <<'EOF_GD_MU_DKIM'
        #!/bin/bash
        set -euo pipefail
        cd \#(path) 2>/dev/null || { echo "\#(Self.dkimDumpDoneMarker)"; exit 0; }
        # --dns asks Mailu for the records it would publish; the private key is
        # NOT in that projection, which is why this dump can be whitelisted.
        OUT="$(timeout 60 docker compose -p \#(Self.composeProject) exec -T -u \#(Self.adminRunAsUser) \#(Self.adminService) \
               flask mailu config-export -d -j domain 2>/dev/null || true)"
        printf '%s' "$OUT" | python3 -c '
        import json, sys
        try:
            data = json.load(sys.stdin)
        except Exception:
            raise SystemExit(0)
        for domain in data.get("domain", []):
            record = domain.get("dns_dkim")
            if not record:
                continue
            # dns_dkim is a full zone line: "<name> 600 IN TXT \"v=DKIM1…\"".
            # The app wants the name and the value, so keep those two.
            name, _, rest = record.partition(" ")
            value = rest[rest.find("\"") :].strip() if "\"" in rest else rest.strip()
            print("\#(Self.dkimMarker) " + name.rstrip(".") + " " + value)
        ' 2>/dev/null || true
        echo "\#(Self.dkimDumpDoneMarker)"
        EOF_GD_MU_DKIM
        chmod 700 \#(Self.dkimDumpScriptPath)
        """#
    }

    public func extraSudoers(_ context: ServiceContext) -> [PrivilegedCommand] {
        [PrivilegedCommand(binaryPath: Self.dkimDumpScriptPath, arguments: "")]
    }

    /// Only what the engine actually listens on
    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] {
        [
            FirewallPort(25, comment: "SMTP"),
            FirewallPort(465, comment: "SMTPS (implicit TLS)"),
            FirewallPort(993, comment: "IMAPS (implicit TLS)"),
            FirewallPort(4190, comment: "Sieve")
        ]
    }

    public func webIngress(_ context: ServiceContext) -> WebIngress? {
        WebIngress(hostname: "mail.\(context.domain)", upstreamPort: Self.webUIPort)
    }

    public func dnsHostnames(_ context: ServiceContext) -> [String] { [] }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.mailuPath
        let lang = context.language
        let hostname = "mail.\(context.domain)"
        let admin = context.settings.adminUsername
        return [
            #"""
            echo "Mailu:        https://\#(hostname)/admin"
            echo "  \#(L10nServices.webmailLabel(lang)):     https://\#(hostname)/webmail"
            echo "  \#(L10nServices.administratorLabel(lang)): \#(admin)@\#(context.domain)"
            echo "  \#(L10nServices.passwordGeneratedOnServerLabel(lang)): $(grep '^INITIAL_ADMIN_PW=' \#(path)/.env | cut -d= -f2-)"
            # The DKIM records, straight from the engine that minted them. Not
            # fatal and not silenced: a missing key is a DNS record the user
            # adds later, not a reason to lose the rest of the report.
            echo "  \#(L10nServices.mailuClientPortsNote(lang))"
            echo "  \#(L10nServices.dkimRecordsLabel(lang)):"
            \#(Self.dkimDumpScriptPath) 2>/dev/null | grep '^\#(Self.dkimMarker) ' | while read -r _ NAME VALUE; do
              echo "    $NAME TXT $VALUE"
            done || echo "    \#(L10nServices.mailuDKIMPendingNote(lang))"
            """#
        ]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.mailuPath
        return ServiceActions(
            statusProbe: .composeProject(
                project: Self.composeProject,
                list: PrivilegedCommand(binaryPath: "/usr/bin/docker",
                                        arguments: "compose -p \(Self.composeProject) ps")
            ),
            restart: ServicePower.compose(project: Self.composeProject, "restart", timeoutClass: .long),
            start: ServicePower.compose(project: Self.composeProject, "start", timeoutClass: .long),
            stop: ServicePower.compose(project: Self.composeProject, "stop", timeoutClass: .long),
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
                    quiesceServices: ["front", "admin", "imap", "smtp",
                                      "antispam", "webmail", "redis", "resolver"],
                    encryptsByDefault: true,
                    sizePaths: ["\(path)/mail", "\(path)/data", "\(path)/webmail"],
                    excludes: ["\(Self.archiveSlot(path: path))/filter",
                               "\(Self.archiveSlot(path: path))/mailqueue"]
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
        UpdateSpec(images: [Self.cacheImage] + Component.allCases.map(Self.image))
    }

    static func archiveSlot(path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            dataPaths: [context.settings.mailuPath],
            postSteps: [
                "systemctl disable --now \(Self.certSyncUnit).timer >/dev/null 2>&1 || true",
                "rm -f /etc/systemd/system/\(Self.certSyncUnit).service "
                    + "/etc/systemd/system/\(Self.certSyncUnit).timer "
                    + "'\(Self.certSyncScriptPath)' '\(Self.dkimDumpScriptPath)'",
                "rm -f '\(Self.certSyncScriptPath)'.bak.* '\(Self.dkimDumpScriptPath)'.bak.*",
                "systemctl daemon-reload || true"
            ]
        )
    }
}
