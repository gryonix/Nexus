public struct DockerMailserverService: MailEngineService {
    public static let composeProject = "dockermailserver"
    /// Loopback port Caddy proxies the webmail to
    public static let webUIPort = 8086
    public static let containerName = "mailserver"
    public static let webmailContainerName = "mailserver-webmail"
    public static let wrapperTarget = ServiceID.dockerMailserver.rawValue

    public static let image = "ghcr.io/docker-mailserver/docker-mailserver:15.1.0"
    /// Roundcube supplies the webmail this engine has none of
    public static let webmailImage = "roundcube/roundcubemail:1.6.17-apache"

    /// Sync script + timer that copy Caddy's certificate in
    public static let certSyncScriptPath = "/opt/gryonixnexus-dms-cert-sync.sh"
    public static let certSyncUnit = "gryonixnexus-dms-cert-sync"
    public static let mailboxScriptPath = "/opt/gryonixnexus-dms-mailbox.sh"
    public static let dkimDumpScriptPath = "/opt/gryonixnexus-dms-dkim.sh"
    public static let dkimMarker = "GRYONIXNEXUS_DKIM"
    public static let dkimDumpDoneMarker = "GRYONIXNEXUS_DKIM_DONE"
    public static let dkimSelector = "dkim"
    public static let dkimKeySize = 2048

    public let id = ServiceID.dockerMailserver
    public let displayName = "Docker Mailserver"
    public let systemImage = "envelope.arrow.triangle.branch"
    public let category = ServiceCategory.mail
    public let usesSharedAdminLogin = true
    public let runtime = ServiceRuntime.docker(composeProject: Self.composeProject)
    public let resources = ServiceResources(memoryMB: 768, diskGB: 5)

    public init() {}

    /// `mail.<domain>`, like every engine here
    public func requiredHostname(forDomain domain: String) -> String? {
        "mail.\(domain)"
    }

    public func composeFile(_ context: ServiceContext) -> ComposeFile? {
        let path = context.settings.dockerMailserverPath
        let hostname = "mail.\(context.domain)"
        return ComposeFile(
            directory: path,
            composeContents: """
            services:
              mailserver:
                image: \(Self.image)
                container_name: \(Self.containerName)
                hostname: \(hostname)
                restart: unless-stopped
                env_file: .env
                # Every client port, including the STARTTLS pair. This engine
                # serves them all, so opening them is honest here.
                ports:
                  - "25:25"
                  - "143:143"
                  - "465:465"
                  - "587:587"
                  - "993:993"
                  - "4190:4190"
                volumes:
                  - \(path)/mail-data:/var/mail
                  - \(path)/mail-state:/var/mail-state
                  - \(path)/mail-logs:/var/log/mail
                  - \(path)/config:/tmp/docker-mailserver
                  - \(path)/certs:/etc/gryonixnexus-certs:ro
                  - /etc/localtime:/etc/localtime:ro
                # The container answers to its own certificate name INSIDE the
                # compose network. Roundcube verifies the peer name (PHP does
                # by default and Roundcube leaves imap_conn_options unset), so
                # connecting to `mailserver` failed against a certificate
                # issued for \(hostname). Aliasing here fixes
                # the name instead of switching verification off.
                networks:
                  default:
                    aliases:
                      - \(hostname)
                # Postfix and Dovecot change kernel-visible limits and need to
                # drop privileges themselves; this is the capability set
                # upstream documents for a non-privileged run.
                cap_add:
                  - NET_ADMIN
                stop_grace_period: 1m
              webmail:
                image: \(Self.webmailImage)
                container_name: \(Self.webmailContainerName)
                restart: unless-stopped
                depends_on:
                  - mailserver
                environment:
                  # The mail container's alias, not its service name: this
                  # name is what the certificate is issued for, and the
                  # connection is verified. It still resolves inside the
                  # compose network, so the traffic never leaves the host and
                  # never touches the published ports.
                  ROUNDCUBEMAIL_DEFAULT_HOST: ssl://\(hostname)
                  ROUNDCUBEMAIL_DEFAULT_PORT: "993"
                  ROUNDCUBEMAIL_SMTP_SERVER: tls://\(hostname)
                  ROUNDCUBEMAIL_SMTP_PORT: "587"
                  ROUNDCUBEMAIL_PLUGINS: archive,zipdownload,managesieve
                  ROUNDCUBEMAIL_UPLOAD_MAX_FILESIZE: 25M
                volumes:
                  - \(path)/webmail:/var/roundcube/config
                  # /var/roundcube/db is where the image puts its sqlite file
                  # (ROUNDCUBEMAIL_DB_DIR); mounted anywhere else the database
                  # stays in the container layer and every recreate throws
                  # away the users' settings, contacts and address book.
                  - \(path)/webmail-db:/var/roundcube/db
                ports:
                  # Loopback only: Caddy terminates TLS in front of it, which
                  # also puts it under the lockdown guard like every other UI.
                  - "127.0.0.1:\(Self.webUIPort):80"
            """,
            envTemplate: Self.envTemplate(context)
        )
    }

    private static func envTemplate(_ context: ServiceContext) -> String {
        let hostname = "mail.\(context.domain)"
        return """
        # Managed by gryonixNexus. Generated on the server; the __RANDOM__ marker
        # is replaced once and then left alone on re-runs.
        OVERRIDE_HOSTNAME=\(hostname)
        POSTMASTER_ADDRESS=postmaster@\(context.domain)
        # The certificate is handed in by the sync timer below — Caddy owns the
        # ACME account on this host, and only one process can.
        SSL_TYPE=manual
        SSL_CERT_PATH=/etc/gryonixnexus-certs/cert.pem
        SSL_KEY_PATH=/etc/gryonixnexus-certs/key.pem
        # Rspamd is the modern filter and it also signs DKIM; Amavis, ClamAV and
        # SpamAssassin are the legacy chain and together they are most of the
        # memory this engine was chosen to avoid. ClamAV alone wants about a
        # gigabyte, which is most of a small server's headroom.
        ENABLE_RSPAMD=1
        ENABLE_OPENDKIM=0
        ENABLE_AMAVIS=0
        ENABLE_CLAMAV=0
        ENABLE_SPAMASSASSIN=0
        # Sieve on 4190, the same port the other engines publish.
        ENABLE_MANAGESIEVE=1
        # No fail2ban: it needs NET_ADMIN plus host firewall access, and the
        # deployment already has nftables in front of this container.
        ENABLE_FAIL2BAN=0
        # Mailboxes live in a file the wrapper edits — no LDAP, no OIDC.
        ACCOUNT_PROVISIONER=FILE
        # Only the webmail container may relay without authenticating, and it
        # reaches Postfix over the compose network.
        PERMIT_DOCKER=connected-networks
        POSTFIX_MESSAGE_SIZE_LIMIT=50000000
        FIRST_MAILBOX_PASSWORD=__RANDOM__
        """
    }

    public func setupSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.dockerMailserverPath
        let lang = context.language
        let admin = context.settings.adminUsername
        let hostname = "mail.\(context.domain)"
        let domains = [context.domain] + context.additionalDomains
        return [
            #"""
            log "Docker Mailserver: \#(L10nServices.serviceStarting(lang))"
            install -d -m 755 \#(path) \#(path)/mail-data \#(path)/mail-state \#(path)/mail-logs \#(path)/config \#(path)/webmail \#(path)/webmail-db
            # The certificate directory is root-only: the container reads it
            # read-only, and nothing else on the host has business there.
            install -d -m 700 \#(path)/certs
            # SSL_TYPE=manual does NOT degrade when the files are missing: the
            # engine prints "File … does not exist!", shuts down, and
            # `restart: unless-stopped` turns that into a permanent crash
            # loop. Caddy only obtains the real certificate two steps later,
            # so on a fresh install there is nothing to point at yet — and a
            # container stuck in that loop never gets its first mailbox or its
            # DKIM keys either. A self-signed placeholder lets the engine boot;
            # the sync below replaces it the moment Caddy has the real one.
            # Live-found: without this the whole engine never starts.
            if [ ! -s \#(path)/certs/cert.pem ] || [ ! -s \#(path)/certs/key.pem ]; then
              if openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
                   -subj "/CN=\#(hostname)" -addext "subjectAltName=DNS:\#(hostname)" \
                   -keyout \#(path)/certs/key.pem -out \#(path)/certs/cert.pem >/dev/null 2>&1; then
                chmod 644 \#(path)/certs/cert.pem
                chmod 600 \#(path)/certs/key.pem
              else
                log "\#(L10nServices.dmsPlaceholderCertFailed(lang))"
              fi
            fi
            cd \#(path)
            docker compose -p \#(Self.composeProject) pull -q
            docker compose -p \#(Self.composeProject) up -d
            """#,
            certSyncStep(context),
            #"""
            # First mailbox and DKIM keys. Nothing here is fatal and no output
            # is discarded — the same rule the mailcow API, the Nextcloud occ
            # and the Mailu CLI blocks follow: errexit in the middle of this
            # step would take the remaining services and the revocation of the
            # install key with it, and a mailbox is addable afterwards.
            DMS_OUT=""
            dms_exec() { DMS_OUT="$(timeout 120 docker exec \#(Self.containerName) "$@" 2>&1)"; }
            # Passwords go in on stdin, never in argv: the arguments of
            # `docker exec` are readable out of /proc by every account on the
            # box. The helper asks for the password twice, so it is fed twice.
            # $1 add|update, $2 address, $3 password.
            dms_mailbox() {
              DMS_OUT="$(printf '%s\n%s\n' "$3" "$3" \
                | timeout 120 docker exec -i \#(Self.containerName) setup email "$1" "$2" 2>&1)"
            }
            dms_why() { printf '%s' "$DMS_OUT" | tr -d '\r\n' | cut -c1-300; }
            # A deadline, not a number of tries: each attempt can burn its own
            # timeout, so counting attempts leaves the real wait unbounded.
            # The probe is `setup help` and NOT `setup email list`: the list
            # subcommand exits 1 while no account exists — which is exactly the
            # state of every fresh install — so it answered "not ready" until
            # the deadline ran out and neither the first mailbox nor the DKIM
            # keys were ever created.
            DMS_READY=0
            DMS_TRY=0
            DMS_DEADLINE=$(($(date +%s) + 300))
            while [ "$(date +%s)" -lt "$DMS_DEADLINE" ]; do
              if dms_exec setup help; then DMS_READY=1; break; fi
              DMS_TRY=$((DMS_TRY + 1))
              # Heartbeat every ~30 s: silence here is indistinguishable from a
              # hung install in the app's progress view.
              if [ "$((DMS_TRY % 6))" -eq 0 ]; then
                log "\#(L10nServices.dmsWaiting(lang)) ($(dms_why))"
              fi
              sleep 5
            done
            if [ "$DMS_READY" -eq 1 ]; then
              DMS_PASSWORD="$(grep '^FIRST_MAILBOX_PASSWORD=' \#(path)/.env | cut -d= -f2- || true)"
              # Its failure IS the answer "there are no accounts yet" — the
              # account file does not exist until the first one is added — so
              # it must not take the step down with it under errexit.
              dms_exec setup email list || true
              # `email list` prints one line per mailbox; matching the address
              # at a word boundary keeps a lookalike account from passing for
              # this one and silently skipping creation — the Forgejo lesson.
              if ! printf '%s' "$DMS_OUT" | grep -qE "(^|[[:space:]*])\#(admin)@\#(context.domain)([[:space:]]|$)"; then
                if [ -n "$DMS_PASSWORD" ]; then
                  dms_mailbox add "\#(admin)@\#(context.domain)" "$DMS_PASSWORD" \
                    || log "\#(L10nServices.dmsMailboxFailed(lang)) ($(dms_why))"
                fi
              fi
              \#(dkimSteps(domains: domains, lang: lang, path: path))
            else
              log "\#(L10nServices.dmsUnavailable(lang)) ($(dms_why))"
            fi
            """#,
            managementScripts(context)
        ]
    }

    /// DKIM keys, one per mail domain
    private func dkimSteps(domains: [String], lang: AppLanguage, path: String) -> String {
        let keys = domains.map { domain in
            #"""
              # Idempotent: the helper skips a domain that already has a key.
              # The selector is spelled out — the default is `mail`, and the
              # DNS artifact tells the user to publish `dkim._domainkey`.
              dms_exec setup config dkim keysize \#(Self.dkimKeySize) selector \#(Self.dkimSelector) domain \#(domain) \
                || log "\#(L10nServices.dmsDKIMFailed(lang, domain: domain)) ($(dms_why))"
            """#
        }.joined(separator: "\n")
        return keys + "\n" + Self.dkimSigningDomainFix(path: path)
    }

    static func dkimSigningDomainFix(path: String) -> String {
        #"""
          # rspamd looks the signing key up under the eSLD unless told not to,
          # so a mail domain that is a SUBDOMAIN never matches its own key and
          # goes out unsigned. Our keys are filed under the exact domain.
          DMS_DKIM_CONF="\#(path)/config/rspamd/override.d/dkim_signing.conf"
          if [ -f "$DMS_DKIM_CONF" ] && grep -q '^use_esld = true;' "$DMS_DKIM_CONF"; then
            sed -i 's/^use_esld = true;/use_esld = false;/' "$DMS_DKIM_CONF"
            # rspamd reads this at start; without the restart the fix applies
            # only after the next unrelated container restart.
            dms_exec supervisorctl restart rspamd || true
          fi
        """#
    }

    private func certSyncStep(_ context: ServiceContext) -> String {
        let path = context.settings.dockerMailserverPath
        let hostname = "mail.\(context.domain)"
        return #"""
        cat > \#(Self.certSyncScriptPath) <<'EOF_DMS_CERTSYNC'
        #!/bin/bash
        set -eu
        DOMAIN="\#(hostname)"
        DMS="\#(path)"
        DEST="$DMS/certs"
        CADDY_DATA="/var/lib/caddy/.local/share/caddy/certificates"
        SRC_CRT="$(find "$CADDY_DATA" -type f -name "${DOMAIN}.crt" 2>/dev/null | head -n1)"
        SRC_KEY="$(find "$CADDY_DATA" -type f -name "${DOMAIN}.key" 2>/dev/null | head -n1)"
        # No certificate yet (ACME still pending) is not an error: the timer
        # comes back every hour and the mail ports keep serving what they have.
        if [ -z "$SRC_CRT" ] || [ -z "$SRC_KEY" ]; then exit 0; fi
        if cmp -s "$SRC_CRT" "$DEST/cert.pem" && cmp -s "$SRC_KEY" "$DEST/key.pem"; then exit 0; fi
        cp "$SRC_CRT" "$DEST/cert.pem"
        cp "$SRC_KEY" "$DEST/key.pem"
        chmod 644 "$DEST/cert.pem"
        chmod 600 "$DEST/key.pem"
        cd "$DMS"
        # Postfix and Dovecot read the certificate at start; the container has
        # no reload hook for a file that changed under it.
        docker compose -p \#(Self.composeProject) restart \#(Self.containerName) >/dev/null 2>&1 || true
        EOF_DMS_CERTSYNC
        chmod 700 \#(Self.certSyncScriptPath)
        cat > /etc/systemd/system/\#(Self.certSyncUnit).service <<'EOF_DMS_CERTSVC'
        [Unit]
        Description=Sync Caddy TLS certificate into Docker Mailserver (SMTP/IMAPS)
        After=docker.service
        [Service]
        Type=oneshot
        ExecStart=\#(Self.certSyncScriptPath)
        EOF_DMS_CERTSVC
        cat > /etc/systemd/system/\#(Self.certSyncUnit).timer <<'EOF_DMS_CERTTIMER'
        [Unit]
        Description=Periodic Caddy to Docker Mailserver TLS certificate sync
        [Timer]
        OnActiveSec=5min
        OnUnitActiveSec=1h
        Persistent=true
        [Install]
        WantedBy=timers.target
        EOF_DMS_CERTTIMER
        systemctl daemon-reload
        systemctl enable --now \#(Self.certSyncUnit).timer >/dev/null 2>&1 || true
        \#(Self.certSyncScriptPath) || true
        """#
    }

    private func managementScripts(_ context: ServiceContext) -> String {
        let path = context.settings.dockerMailserverPath
        return #"""
        cat > \#(Self.mailboxScriptPath) <<'EOF_DMS_MAILBOX'
        #!/bin/bash
        # Mailbox management for the gryonixNexus dashboard.
        # Usage: gryonixnexus-dms-mailbox.sh list
        #        gryonixnexus-dms-mailbox.sh add <address> (password on stdin)
        #        gryonixnexus-dms-mailbox.sh del <address>
        #        gryonixnexus-dms-mailbox.sh password <address> (password on stdin)
        set -euo pipefail
        cd \#(path) 2>/dev/null || { echo "docker mailserver is not installed" >&2; exit 2; }
        ACTION="${1:-}"
        ADDRESS="${2:-}"
        # The address is checked HERE, not by the container: this script runs as
        # root through sudo, so an argument that reaches `docker exec` unchecked
        # is an argument that reaches root. One local part, one domain, no
        # shell metacharacters, no leading dash that could read as a flag.
        check_address() {
          case "$ADDRESS" in
            -*|*[!a-zA-Z0-9.@_+-]*|*@*@*|@*|*@) echo "invalid address: ${ADDRESS}" >&2; exit 2 ;;
            *@*) ;;
            *) echo "invalid address: ${ADDRESS}" >&2; exit 2 ;;
          esac
        }
        # The password arrives on stdin, never in argv, where /proc would show
        # it to every account on the box.
        read_password() {
          if [ -t 0 ]; then echo "a password is required on stdin" >&2; exit 2; fi
          PASSWORD="$(cat)"
          [ -n "$PASSWORD" ] || { echo "the password is empty" >&2; exit 2; }
        }
        case "$ACTION" in
          list)
            # An install with no mailboxes yet is an EMPTY LIST, not a failure:
            # `setup email list` exits 1 for as long as the account file does
            # not exist, and the app would show an error where it should show
            # "no mailboxes". The file is checked on the host — it is the same
            # directory the container has mounted, so this adds no second
            # source of truth. A container that is down still makes the listing
            # fail, which the app does need to see.
            if [ -s \#(path)/config/postfix-accounts.cf ]; then
              docker exec \#(Self.containerName) setup email list
            fi
            ;;
          add)
            check_address; read_password
            # The password goes down stdin into the container as well, not as
            # an argument: `docker exec` argv is world-readable in /proc. The
            # helper prompts for it twice, hence the two lines.
            printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" \
              | docker exec -i \#(Self.containerName) setup email add "$ADDRESS" >/dev/null
            echo "GRYONIXNEXUS_MAILBOX_DONE add ${ADDRESS}"
            ;;
          del)
            check_address
            # Retried, because deleting a mailbox seconds after creating it
            # loses a race INSIDE the engine: `addmailuser` writes the account
            # line at once, but the mail directory is created asynchronously
            # about a second later, and `delmailuser` refuses while it is not
            # there ("Mailbox data directory … does not exist"). Absent at t=0, present at t=1s, and the very same
            # call then succeeds. Nothing is destroyed by the refusal — the
            # account line survives — so retrying is safe, and "add a mailbox,
            # notice the typo, delete it" is the most likely first thing
            # anyone does with this screen.
            # The LAST attempt runs with its output visible: whatever is
            # really wrong, the engine's own words are the only explanation
            # the app can show, and the marker is not printed on failure.
            DEL_TRY=1
            while true; do
              if [ "$DEL_TRY" -ge 5 ]; then
                docker exec \#(Self.containerName) setup email del -y "$ADDRESS" >/dev/null
                break
              fi
              if docker exec \#(Self.containerName) setup email del -y "$ADDRESS" >/dev/null 2>&1; then
                break
              fi
              DEL_TRY=$((DEL_TRY + 1))
              sleep 2
            done
            echo "GRYONIXNEXUS_MAILBOX_DONE del ${ADDRESS}"
            ;;
          password)
            check_address; read_password
            printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" \
              | docker exec -i \#(Self.containerName) setup email update "$ADDRESS" >/dev/null
            echo "GRYONIXNEXUS_MAILBOX_DONE password ${ADDRESS}"
            ;;
          *)
            echo "unsupported action: ${ACTION}" >&2; exit 2 ;;
        esac
        EOF_DMS_MAILBOX
        chmod 700 \#(Self.mailboxScriptPath)
        cat > \#(Self.dkimDumpScriptPath) <<'EOF_DMS_DKIM'
        #!/bin/bash
        set -euo pipefail
        # `setup config dkim` is what actually MINTS the key (see the install
        # step that calls it), and it always writes BIND-format keys under
        # opendkim/keys/<domain>/dkim.txt — REGARDLESS of ENABLE_RSPAMD vs
        # ENABLE_OPENDKIM. Rspamd's dkim_signing module reads its signing key
        # from that same path by the image's own default config; "opendkim"
        # here names where the key lives, not which engine signs with it.
        #
        # An earlier version of this wrapper globbed
        # `rspamd/dkim/*-dkim-*.public.dns.txt`, a path rspamd never writes on
        # this image: the real
        # key sat at opendkim/keys/<domain>/dkim.txt the whole time, and the
        # glob matched nothing, so every report said "not ready yet" forever.
        #
        # dkim.txt is a BIND zone-file record, not a bare value:
        #   dkim._domainkey IN TXT ( "v=DKIM1; h=sha256; k=rsa; "
        #     "p=MIIB..." "dYRV...AB" )  ; ----- DKIM key dkim for <domain>
        # The quoted segments concatenate directly (no separator) into the
        # single value to publish — the first segment's own trailing space
        # is what keeps "k=rsa;" and "p=..." apart, so no extra space is added
        # here.
        for F in \#(path)/config/opendkim/keys/*/dkim.txt; do
          [ -f "$F" ] || continue
          D="$(basename "$(dirname "$F")")"
          V="$(grep -o '"[^"]*"' "$F" | tr -d '"\n' | head -c 2000)"
          [ -n "$V" ] || continue
          # Bare, no quotes around $V — mailcow and Mailu both print the value
          # unquoted (see their own dkimMarker lines), and DKIMRecordParser /
          # DKIMExport downstream both expect the bare "v=DKIM1;...;p=..."
          # string, adding their own quoting where a format needs it (the BIND
          # zone export, the DNS provider's own form). A quoted value here
          # would ship the literal `"` characters into every artifact and
          # clipboard copy built from it.
          echo "\#(Self.dkimMarker) \#(Self.dkimSelector)._domainkey.$D $V"
        done
        echo "\#(Self.dkimDumpDoneMarker)"
        EOF_DMS_DKIM
        chmod 700 \#(Self.dkimDumpScriptPath)
        """#
    }

    public func extraSudoers(_ context: ServiceContext) -> [PrivilegedCommand] {
        [
            PrivilegedCommand(binaryPath: Self.mailboxScriptPath, arguments: ""),
            PrivilegedCommand(binaryPath: Self.dkimDumpScriptPath, arguments: "")
        ]
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
        WebIngress(hostname: "mail.\(context.domain)", upstreamPort: Self.webUIPort)
    }

    public func dnsHostnames(_ context: ServiceContext) -> [String] { [] }

    public func reportSteps(_ context: ServiceContext) -> [String] {
        let path = context.settings.dockerMailserverPath
        let lang = context.language
        let hostname = "mail.\(context.domain)"
        let admin = context.settings.adminUsername
        return [
            #"""
            echo "Docker Mailserver:"
            echo "  \#(L10nServices.webmailLabel(lang)):     https://\#(hostname)"
            echo "  \#(L10nServices.firstMailboxLabel(lang)): \#(admin)@\#(context.domain)"
            echo "  \#(L10nServices.passwordGeneratedOnServerLabel(lang)): $(grep '^FIRST_MAILBOX_PASSWORD=' \#(path)/.env | cut -d= -f2-)"
            echo "  \#(L10nServices.dmsMailboxesNote(lang))"
            echo "  \#(L10nServices.dkimRecordsLabel(lang)):"
            \#(Self.dkimDumpScriptPath) 2>/dev/null | grep '^\#(Self.dkimMarker) ' | while read -r _ NAME VALUE; do
              echo "    $NAME TXT $VALUE"
            done || echo "    \#(L10nServices.dmsDKIMPendingNote(lang))"
            """#
        ]
    }

    public func actions(_ context: ServiceContext) -> ServiceActions {
        let path = context.settings.dockerMailserverPath
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
                    quiesceServices: ["mailserver", "webmail"],
                    encryptsByDefault: true,
                    sizePaths: ["\(path)/mail-data", "\(path)/config"],
                    // Logs restore nothing and grow without bound.
                    excludes: ["\(Self.archiveSlot(path: path))/mail-logs"]
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

    static func archiveSlot(path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    public func updateSpec(_ context: ServiceContext) -> UpdateSpec {
        UpdateSpec(images: [Self.image, Self.webmailImage])
    }

    public func uninstallSpec(_ context: ServiceContext) -> UninstallSpec {
        UninstallSpec(
            composeProject: Self.composeProject,
            dataPaths: [context.settings.dockerMailserverPath],
            postSteps: [
                "systemctl disable --now \(Self.certSyncUnit).timer >/dev/null 2>&1 || true",
                "rm -f /etc/systemd/system/\(Self.certSyncUnit).service "
                    + "/etc/systemd/system/\(Self.certSyncUnit).timer "
                    + "'\(Self.certSyncScriptPath)' '\(Self.mailboxScriptPath)' "
                    + "'\(Self.dkimDumpScriptPath)'",
                "rm -f '\(Self.certSyncScriptPath)'.bak.* '\(Self.mailboxScriptPath)'.bak.* "
                    + "'\(Self.dkimDumpScriptPath)'.bak.*",
                "systemctl daemon-reload || true"
            ]
        )
    }
}
