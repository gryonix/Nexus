/// Mailcow: the dockerized full mail stack — the app's only mail engine.
/// Web UI goes through the shared Caddy ingress (mailcow's own HTTP bound to
/// 127.0.0.1); mail ports are exposed directly.
public struct MailcowService: MailEngineService {
    public static let composeProject = "mailcowdockerized"
    public static let dkimMarker = "GRYONIXNEXUS_DKIM"
    /// Root-owned read-only wrapper installed by setup
    public static let dkimDumpScriptPath = "/opt/gryonixnexus-dkim.sh"
    public static let dkimDumpDoneMarker = "GRYONIXNEXUS_DKIM_DONE"
    public static let adminPasswordFile = ".gryonixnexus-admin-password"
    /// Local bind for mailcow's web UI
    public static let webUIPort = 8080
    public static let webUIHTTPSPort = 18443

    public let id = ServiceID.mailcow
    public let displayName = "Mailcow"
    public let systemImage = "envelope.badge"
    public let category = ServiceCategory.mail
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 2560, diskGB: 8)

    public init() {}

    /// MAILCOW_HOSTNAME and the web UI are pinned to mail.<domain>
    public func requiredHostname(forDomain domain: String) -> String? {
        "mail.\(domain)"
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? { nil }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.mailcowPath
        let hostname = "mail.\(context.domain)"
        let lang = context.language
        // One domain per line for the here-document below.
        let mailDomainList = ([context.domain] + context.additionalDomains)
            .joined(separator: "\n")
        let teardown = context.settings.eraseMailOnDomainChange ? #"""
        if [ -f "\#(path)/mailcow.conf" ] && ! grep -qx 'MAILCOW_HOSTNAME=\#(hostname)' "\#(path)/mailcow.conf"; then
          log "\#(L10nServices.mailcowRecreatingForNewHostname(lang, hostname: hostname))"
          (cd "\#(path)" && docker compose down -v --remove-orphans) || true
          rm -rf "\#(path)"
        fi

        """# : ""
        return [teardown + #"""
        log "\#(L10nServices.mailcowInstalling(lang, path: path))"
        if [ ! -d "\#(path)/.git" ] && [ -n "$(ls -A "\#(path)" 2>/dev/null)" ]; then
          # Kept data, no repository: bring the repository in beside it.
          rm -rf "\#(path).clone"
          git clone --no-checkout https://github.com/mailcow/mailcow-dockerized "\#(path).clone"
          mv "\#(path).clone/.git" "\#(path)/.git"
          rm -rf "\#(path).clone"
          git -C "\#(path)" checkout HEAD -- .
        elif [ ! -d "\#(path)/.git" ]; then
          git clone https://github.com/mailcow/mailcow-dockerized \#(path)
        fi
        cd \#(path)
        if [ ! -f mailcow.conf ]; then
          # Non-interactive config: hostname/timezone/branch via env. The env
          # vars do NOT cover everything: on low-memory hosts (≤ 2.5 GiB) the
          # script still prompts "disable ClamAV? [Y/n]" (and similar) from
          # stdin, hanging a headless run. Feed a bounded set of yes-answers:
          # unexpected prompts read them (or hit EOF → their default), and a
          # bounded printf can't die of SIGPIPE under pipefail.
          # COMPOSE_VERSION: generate_config.sh does not detect the compose
          # flavour, it only substitutes this variable into mailcow.conf. We
          # install the compose plugin, so it is always "native".
          printf 'y\ny\ny\n' | COMPOSE_VERSION=native MAILCOW_HOSTNAME=\#(hostname) MAILCOW_TZ=UTC MAILCOW_BRANCH=master ./generate_config.sh
          # Behind the shared Caddy ingress: web UI on loopback only.
          sed -i 's/^HTTP_BIND=.*/HTTP_BIND=127.0.0.1/' mailcow.conf
          sed -i 's/^HTTP_PORT=.*/HTTP_PORT=\#(Self.webUIPort)/' mailcow.conf
          sed -i 's/^HTTPS_BIND=.*/HTTPS_BIND=127.0.0.1/' mailcow.conf
          sed -i 's/^HTTPS_PORT=.*/HTTPS_PORT=\#(Self.webUIHTTPSPort)/' mailcow.conf
          # TLS terminates at Caddy; mailcow must not fight for ACME.
          sed -i 's/^SKIP_LETS_ENCRYPT=.*/SKIP_LETS_ENCRYPT=y/' mailcow.conf
        fi
        # Left empty, DOCKER_COMPOSE_VERSION takes every mailcow helper that
        # reads it down with it: `backup_and_restore.sh restore` aborts with
        # "Can not read DOCKER_COMPOSE_VERSION variable from mailcow.conf"
        # BEFORE unpacking anything, so the restore wrapper reports failure
        # having restored nothing (update.sh is safe — it unsets and re-detects
        # the value itself). Repaired here, outside the `if` above, because the
        # conf is generated exactly once: servers installed before this fix are
        # only reachable through a setup re-run, which is how sudoers and
        # wrapper changes already reach them.
        if grep -q '^DOCKER_COMPOSE_VERSION=' mailcow.conf; then
          sed -i 's/^DOCKER_COMPOSE_VERSION=.*/DOCKER_COMPOSE_VERSION=native/' mailcow.conf
        else
          echo 'DOCKER_COMPOSE_VERSION=native' >> mailcow.conf
        fi
        # A clone made under a tight umask stays broken forever without this:
        # git has no mode flag, and a re-run skips the clone (.git is already
        # there). mailcow's containers drop to their own users — nginx's config
        # says `user nginx` — and mount this tree, so root-only modes make the
        # worker fail to even traverse /web and every PHP path answers a bare
        # nginx 404, the whole API included. mailcow.conf keeps 600: it holds
        # the database passwords.
        chmod -R a+rX .
        chmod 600 mailcow.conf
        # Pull/up wrapped in retry: on a fresh public server the first pull of
        # mailcow's ~15 images often trips a transient registry timeout, which
        # under `set -e` aborted the install and forced a manual Retry.
        retry 4 docker compose pull -q
        retry 2 docker compose up -d
        """#, #"""
        cd \#(path)
        # Enable the REST API once (key generated on this server, kept by
        # re-runs). docker-compose passes API_KEY/API_ALLOW_FROM into the php
        # container; the last assignment in the .env-style file wins, so
        # appending works even next to the commented template lines.
        if ! grep -q '^API_KEY=' mailcow.conf; then
          # The caller is the host reaching the published port, so mailcow's
          # nginx sees the connection arrive from its own bridge gateway — .1
          # of whatever IPV4_NETWORK generate_config.sh settled on. That is
          # 172.22.1 by default but NOT always: the generator moves the subnet
          # when it collides with a docker network that already exists, and a
          # hardcoded gateway then fails the API's IP ACL with an "api access
          # denied for ip" that reads exactly like a wrong key.
          MC_NET="$(grep '^IPV4_NETWORK=' mailcow.conf | tail -n1 | cut -d= -f2- | tr -d '[:space:]')"
          printf 'API_KEY=%s\nAPI_ALLOW_FROM=%s.1,127.0.0.1\n' \
            "$(openssl rand -hex 20)" "${MC_NET:-172.22.1}" >> mailcow.conf
          docker compose up -d
        fi
        MC_API_KEY="$(grep '^API_KEY=' mailcow.conf | tail -n1 | cut -d= -f2-)"
        MC_API="https://127.0.0.1:\#(Self.webUIHTTPSPort)/api/v1"
        MC_BODY="$(mktemp)"
        MC_CODE=000
        # The API lives on the HTTPS vhost. mailcow's HTTP port 301-redirects
        # to it unconditionally, and curl without -L returns the redirect's
        # HTML body instead of JSON — so every call over HTTP silently failed
        # (jq found no fields), add/domain and add/dkim never ran, and DKIM was
        # reported "not ready" forever. Hit HTTPS directly, -k for self-signed.
        #
        # Status into a variable, body into a file, and never a non-zero exit.
        # With `curl -f` the only thing that reached the install log was
        # "curl: (22) The requested URL returned error: 404": the body — which
        # is mailcow's own reason for refusing ("route not found",
        # "authentication failed", "Cannot find attributes in post data") — was
        # discarded, so the failure was undiagnosable, and the bare exit status
        # killed the entire 22-step install under `set -e` at step 7, before
        # the other services and before the install key was revoked.
        mc_api() {
          MC_CODE="$(curl -sSk --max-time 20 -o "$MC_BODY" -w '%{http_code}' -K - \
            -H "Content-Type: application/json" "$@" <<< "header = \"X-API-Key: $MC_API_KEY\"")" || :
          case "$MC_CODE" in ''|*[!0-9]*) MC_CODE=000 ;; esac
          [ "$MC_CODE" -ge 200 ] && [ "$MC_CODE" -lt 300 ]
        }
        # Why the last call failed, in one bounded line: an HTML error page
        # instead of JSON must not flood the log the app streams.
        mc_why() { printf 'HTTP %s %s' "$MC_CODE" "$(tr -d '\r\n' < "$MC_BODY" | cut -c1-300)"; }
        log "\#(L10nServices.mailcowProvisioningDomain(lang, domain: context.domain))"
        # A deadline rather than a fixed number of tries: each attempt can
        # itself burn the 20 s curl timeout, so counting attempts bounded this
        # wait at 25 minutes of total silence, not the 5 it was meant to be.
        MC_READY=0
        MC_TRY=0
        MC_DEADLINE=$(($(date +%s) + 300))
        while [ "$(date +%s)" -lt "$MC_DEADLINE" ]; do
          if mc_api "$MC_API/get/domain/all"; then MC_READY=1; break; fi
          # Heartbeat every ~30 s. The API needs a while after the containers
          # report healthy, and a wait that prints nothing at all is
          # indistinguishable from a hung install in the app's progress view.
          MC_TRY=$((MC_TRY + 1))
          if [ "$((MC_TRY % 6))" -eq 0 ]; then
            log "\#(L10nServices.mailcowWaitingForAPI(lang)) ($(mc_why))"
          fi
          sleep 5
        done
        if [ "$MC_READY" -eq 1 ]; then
          # Every mail domain (the primary one plus any additional
          # domains) with its own DKIM key. Both steps are idempotent — created
          # only when missing, so re-runs never touch an existing configuration,
          # and a domain removed from the app is left alone on the server rather
          # than deleted with its mailboxes.
          # The list is fed through a here-document rather than a quoted word
          # list: it reads the names literally, so no shell quoting question
          # arises at all, and it stays the same shape for one domain or ten.
          while IFS= read -r MC_DOMAIN; do
            [ -n "$MC_DOMAIN" ] || continue
            if ! mc_api "$MC_API/get/domain/$MC_DOMAIN" || ! jq -e '.domain_name' < "$MC_BODY" >/dev/null 2>&1; then
              mc_api -X POST -d "{\"domain\":\"$MC_DOMAIN\",\"description\":\"Managed by gryonixNexus\",\"aliases\":\"400\",\"defquota\":\"3072\",\"maxquota\":\"10240\",\"quota\":\"10240\",\"mailboxes\":\"50\",\"active\":\"1\",\"restart_sogo\":\"10\"}" \
                "$MC_API/add/domain" \
                || log "\#(L10nServices.mailcowDomainAddFailed(lang, domain: "$MC_DOMAIN")) ($(mc_why))"
            fi
            if ! mc_api "$MC_API/get/dkim/$MC_DOMAIN" || ! jq -e '.pubkey' < "$MC_BODY" >/dev/null 2>&1; then
              mc_api -X POST -d "{\"domains\":\"$MC_DOMAIN\",\"dkim_selector\":\"dkim\",\"key_size\":2048}" \
                "$MC_API/add/dkim" \
                || log "\#(L10nServices.mailcowDKIMAddFailed(lang, domain: "$MC_DOMAIN")) ($(mc_why))"
            fi
          done <<'EOF_MC_DOMAINS'
        \#(mailDomainList)
        EOF_MC_DOMAINS
          # The panel's `admin` ships with a published password. Replace it once
          # the API answers (the admin row exists by then) and keep the new one
          # in a root-only file the report reads; a failed call keeps the default
          # and the report says so. Re-runs reuse the stored password.
          MC_ADMIN_FILE="\#(path)/\#(Self.adminPasswordFile)"
          MC_ADMIN_PASS="$(cat "$MC_ADMIN_FILE" 2>/dev/null || true)"
          [ -n "$MC_ADMIN_PASS" ] || MC_ADMIN_PASS="$(openssl rand -hex 12)"
          MC_REQ="$(mktemp)"
          printf '{"items":["admin"],"attr":{"password":"%s","password2":"%s"}}' "$MC_ADMIN_PASS" "$MC_ADMIN_PASS" > "$MC_REQ"
          if mc_api -X POST -d @"$MC_REQ" \
               "$MC_API/edit/admin" \
             && jq -e 'if type == "array" then all(.[]; .type == "success") else .type == "success" end' < "$MC_BODY" >/dev/null 2>&1; then
            (umask 077; printf '%s\n' "$MC_ADMIN_PASS" > "$MC_ADMIN_FILE")
          else
            log "Mailcow admin password: the default one stays ($(mc_why))"
          fi
          rm -f "$MC_REQ"
        else
          log "\#(L10nServices.mailcowAPIUnreachable(lang)) ($(mc_why))"
        fi
        rm -f "$MC_BODY"
        """#, #"""
        # Automatic trusted TLS for SMTP/IMAPS. Caddy fronts only the web UI;
        # mailcow's mail daemons (Postfix/Dovecot) serve their OWN certificate,
        # so without this they present a self-signed one and mail clients warn.
        # Sync Caddy's issued certificate for \#(hostname) into mailcow's ssl
        # assets and reload the mail daemons — once now (a no-op until Caddy has
        # issued it) and then on a timer so renewals are picked up automatically.
        cat > /opt/gryonixnexus-mailcow-cert-sync.sh <<'EOF_MC_CERTSYNC'
        #!/bin/bash
        set -eu
        DOMAIN="\#(hostname)"
        MAILCOW="\#(path)"
        DEST="$MAILCOW/data/assets/ssl"
        CADDY_DATA="/var/lib/caddy/.local/share/caddy/certificates"
        SRC_CRT="$(find "$CADDY_DATA" -type f -name "${DOMAIN}.crt" 2>/dev/null | head -n1)"
        SRC_KEY="$(find "$CADDY_DATA" -type f -name "${DOMAIN}.key" 2>/dev/null | head -n1)"
        if [ -z "$SRC_CRT" ] || [ -z "$SRC_KEY" ]; then exit 0; fi
        if cmp -s "$SRC_CRT" "$DEST/cert.pem" && cmp -s "$SRC_KEY" "$DEST/key.pem"; then exit 0; fi
        cp "$SRC_CRT" "$DEST/cert.pem"
        cp "$SRC_KEY" "$DEST/key.pem"
        cd "$MAILCOW"
        docker compose restart postfix-mailcow dovecot-mailcow nginx-mailcow >/dev/null 2>&1 || true
        EOF_MC_CERTSYNC
        chmod 700 /opt/gryonixnexus-mailcow-cert-sync.sh
        cat > /etc/systemd/system/gryonixnexus-mailcow-cert-sync.service <<'EOF_MC_CERTSVC'
        [Unit]
        Description=Sync Caddy TLS certificate into Mailcow (SMTP/IMAPS)
        After=docker.service
        [Service]
        Type=oneshot
        ExecStart=/opt/gryonixnexus-mailcow-cert-sync.sh
        EOF_MC_CERTSVC
        cat > /etc/systemd/system/gryonixnexus-mailcow-cert-sync.timer <<'EOF_MC_CERTTIMER'
        [Unit]
        Description=Periodic Caddy to Mailcow TLS certificate sync
        [Timer]
        OnActiveSec=5min
        OnUnitActiveSec=1h
        Persistent=true
        [Install]
        WantedBy=timers.target
        EOF_MC_CERTTIMER
        systemctl daemon-reload
        systemctl enable --now gryonixnexus-mailcow-cert-sync.timer >/dev/null 2>&1 || true
        /opt/gryonixnexus-mailcow-cert-sync.sh || true
        """#, #"""
        # Root-owned DKIM dump: every domain and alias domain, missing keys created.
        cat > \#(Self.dkimDumpScriptPath) <<'EOF_GD_DKIM'
        #!/bin/bash
        set -euo pipefail
        CONF="\#(path)/mailcow.conf"
        [ -r "$CONF" ] || { echo "\#(Self.dkimDumpDoneMarker)"; exit 0; }
        MC_KEY="$(grep '^API_KEY=' "$CONF" | tail -n1 | cut -d= -f2-)"
        API="https://127.0.0.1:\#(Self.webUIHTTPSPort)/api/v1"
        mc() { curl -fsSk --max-time 20 -K - "$@" <<< "header = \"X-API-Key: $MC_KEY\""; }
        DOMAINS="$({ mc "$API/get/domain/all" 2>/dev/null | jq -r '.[].domain_name // empty' 2>/dev/null || true; mc "$API/get/alias-domain/all" 2>/dev/null | jq -r '.[].alias_domain // empty' 2>/dev/null || true; } | sort -u)"
        dkim_of() { mc "$API/get/dkim/$1" 2>/dev/null | jq -r "select(type == \"object\") | .$2 // empty" 2>/dev/null || true; }
        for D in $DOMAINS; do
          if [ -z "$(dkim_of "$D" dkim_txt)" ]; then
            mc -X POST -H "Content-Type: application/json" -d "{\"domains\":\"$D\",\"dkim_selector\":\"dkim\",\"key_size\":2048}" "$API/add/dkim" >/dev/null 2>&1 || true
          fi
          TXT="$(dkim_of "$D" dkim_txt)"
          SEL="$(dkim_of "$D" dkim_selector)"
          if [ -n "$TXT" ]; then echo "\#(Self.dkimMarker) ${SEL:-dkim}._domainkey.$D $TXT"; fi
        done
        echo "\#(Self.dkimDumpDoneMarker)"
        EOF_GD_DKIM
        chmod 750 \#(Self.dkimDumpScriptPath)
        """#]
    }

    public func extraSudoers(_ context: ServiceContext) -> [PrivilegedCommand] {
        [PrivilegedCommand(binaryPath: Self.dkimDumpScriptPath, arguments: "")]
    }

    public func firewallPorts(_ context: ServiceContext) -> [FirewallPort] {
        [
            FirewallPort(25, comment: "SMTP"),
            FirewallPort(465, comment: "SMTPS"),
            FirewallPort(587, comment: "Submission"),
            FirewallPort(143, comment: "IMAP"),
            FirewallPort(993, comment: "IMAPS"),
            FirewallPort(4190, comment: "Sieve")
        ]
    }

    public func webIngress(_ context: ServiceContext) -> WebIngress? {
        WebIngress(hostname: "mail.\(context.domain)", upstreamPort: Self.webUIHTTPSPort,
                   upstreamHTTPS: true, publicPaths: Self.syncPaths)
    }

    /// Calendar, contacts and ActiveSync paths, open outside the VPN
    public static let syncPaths = [
        "/SOGo/dav", "/SOGo/dav/*", "/.well-known/caldav", "/.well-known/carddav",
        "/principals", "/principals/*", "/Microsoft-Server-ActiveSync", "/Microsoft-Server-ActiveSync/*",
    ]

    // mail.<domain> A-record is already produced by the mail DNS generator.
    public func dnsHostnames(_ context: ServiceContext) -> [String] { [] }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.mailcowPath
        let lang = context.language
        let dkimBlocks = ([context.domain] + context.additionalDomains).map { domain -> String in
            let record = "dkim._domainkey.\(domain)"
            return #"""
            MC_DKIM_TXT="$(curl -fsSk --max-time 20 -K - <<< "header = \"X-API-Key: $MC_KEY\"" \
              "https://127.0.0.1:\#(Self.webUIHTTPSPort)/api/v1/get/dkim/\#(domain)" 2>/dev/null \
              | jq -r '.dkim_txt // empty' 2>/dev/null)"
            if [ -n "$MC_DKIM_TXT" ]; then
              echo "  \#(L10nServices.mailcowDKIMHeader(lang, record: record))"
              echo "  $MC_DKIM_TXT"
              # Machine-readable twin of the two lines above: the app shows DKIM
              # on its own screen after the install, and the human lines are
              # localized (unparsable). Deliberately ASCII and fixed-shape —
              # `<marker> <record name> <value>`. Mirrored by ServerControl's
              # DKIMRecordParser; pinned by tests on both sides.
              echo "\#(Self.dkimMarker) \#(record) $MC_DKIM_TXT"
            else
              echo "  \#(L10nServices.mailcowDKIMNotReady(lang))"
            fi
            """#
        }.joined(separator: "\n")
        return [#"""
        echo "Mailcow:      https://mail.\#(context.domain)  (\#(L10nServices.directoryLabel(lang)): \#(path))"
        echo "  \#(L10nServices.administratorLabel(lang)): admin"
        MC_ADMIN_PASS="$(cat \#(path)/\#(Self.adminPasswordFile) 2>/dev/null || true)"
        if [ -n "$MC_ADMIN_PASS" ]; then
          echo "  \#(L10nServices.passwordLabel(lang)): $MC_ADMIN_PASS"
        else
          echo "  \#(L10nServices.passwordLabel(lang)): moohoo"
          echo "  \#(L10nServices.mailcowDefaultPasswordNote(lang))"
        fi
        echo "  \#(L10nServices.mailcowAutoCertNote(lang))"
        MC_KEY="$(grep '^API_KEY=' \#(path)/mailcow.conf | tail -n1 | cut -d= -f2-)"
        \#(dkimBlocks)
        """#]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.mailcowPath
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
                wrapperTarget: "mailcow",
                backupDir: context.settings.mailcowBackupDir,
                run: ServiceCommand(
                    PrivilegedCommand(binaryPath: BackupWrapperSpec.wrapperPath,
                                      arguments: ""),
                    timeoutClass: .long,
                    streamsOutput: true
                ),
                plan: .externalScript(path: "\(path)/bot-backup.sh",
                                      sizePaths: [path,
                                                  "/var/lib/docker/volumes/\(Self.composeProject)_*"])
            )),
            restore: RestoreSpec(
                wrapperTarget: "mailcow",
                backupDir: context.settings.mailcowBackupDir,
                // mailcow's own backups are plain directories/tarballs.
                needsPassphrase: false,
                privileged: PrivilegedCommand(binaryPath: RestoreSpec.wrapperPath, arguments: "")
            )
        )
    }

    public func updateSpec(_ context: ServiceContext) -> UpdateSpec { .ownUpdater }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            configDirectory: context.settings.mailcowPath,
            backupDirs: [context.settings.mailcowBackupDir],
            postSteps: [
                "systemctl disable --now gryonixnexus-mailcow-cert-sync.timer >/dev/null 2>&1 || true",
                "rm -f /etc/systemd/system/gryonixnexus-mailcow-cert-sync.service "
                    + "/etc/systemd/system/gryonixnexus-mailcow-cert-sync.timer "
                    + "/opt/gryonixnexus-mailcow-cert-sync.sh",
                "systemctl daemon-reload || true",
                "rm -f '\(context.settings.mailcowPath)/bot-backup.sh' "
                    + "'\(context.settings.mailcowPath)'/bot-backup.sh.bak.* || true",
                "rm -f \(Self.dkimDumpScriptPath)"
            ]
        )
    }
}
