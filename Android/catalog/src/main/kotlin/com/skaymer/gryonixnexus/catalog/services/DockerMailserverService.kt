package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.ArchiveBackupPlan
import com.skaymer.gryonixnexus.catalog.BackupPlan
import com.skaymer.gryonixnexus.catalog.BackupSpec
import com.skaymer.gryonixnexus.catalog.BackupWrapperSpec
import com.skaymer.gryonixnexus.catalog.ComposeFile
import com.skaymer.gryonixnexus.catalog.FirewallPort
import com.skaymer.gryonixnexus.catalog.L10nServices
import com.skaymer.gryonixnexus.catalog.MailEngineService
import com.skaymer.gryonixnexus.catalog.PrivilegedCommand
import com.skaymer.gryonixnexus.catalog.RestoreSpec
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.ServiceActions
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceCommand
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServicePower
import com.skaymer.gryonixnexus.catalog.ServiceResources
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.StatusProbe
import com.skaymer.gryonixnexus.catalog.UninstallSpec
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.WebIngress
import com.skaymer.gryonixnexus.catalog.embedding

/** docker-mailserver — the light mail engine */
class DockerMailserverService : MailEngineService {
    override val id = ServiceID.DOCKER_MAILSERVER
    override val displayName = "Docker Mailserver"
    override val systemImage = "envelope.arrow.triangle.branch"

    override val category = ServiceCategory.MAIL
    override val usesSharedAdminLogin = true
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    override val resources = ServiceResources(memoryMB = 768, diskGB = 5)

    /** `mail.<domain>`, like every engine here */
    override fun requiredHostname(domain: String): String = "mail.$domain"

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.dockerMailserverPath
        val hostname = "mail.${context.domain}"
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              mailserver:
                image: $IMAGE
                container_name: $CONTAINER_NAME
                hostname: $hostname
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
                  - $path/mail-data:/var/mail
                  - $path/mail-state:/var/mail-state
                  - $path/mail-logs:/var/log/mail
                  - $path/config:/tmp/docker-mailserver
                  - $path/certs:/etc/gryonixnexus-certs:ro
                  - /etc/localtime:/etc/localtime:ro
                # The container answers to its own certificate name INSIDE the
                # compose network. Roundcube verifies the peer name (PHP does
                # by default and Roundcube leaves imap_conn_options unset), so
                # connecting to `mailserver` failed against a certificate
                # issued for $hostname. Aliasing here fixes
                # the name instead of switching verification off.
                networks:
                  default:
                    aliases:
                      - $hostname
                # Postfix and Dovecot change kernel-visible limits and need to
                # drop privileges themselves; this is the capability set
                # upstream documents for a non-privileged run.
                cap_add:
                  - NET_ADMIN
                stop_grace_period: 1m
              webmail:
                image: $WEBMAIL_IMAGE
                container_name: $WEBMAIL_CONTAINER_NAME
                restart: unless-stopped
                depends_on:
                  - mailserver
                environment:
                  # The mail container's alias, not its service name: this
                  # name is what the certificate is issued for, and the
                  # connection is verified. It still resolves inside the
                  # compose network, so the traffic never leaves the host and
                  # never touches the published ports.
                  ROUNDCUBEMAIL_DEFAULT_HOST: ssl://$hostname
                  ROUNDCUBEMAIL_DEFAULT_PORT: "993"
                  ROUNDCUBEMAIL_SMTP_SERVER: tls://$hostname
                  ROUNDCUBEMAIL_SMTP_PORT: "587"
                  ROUNDCUBEMAIL_PLUGINS: archive,zipdownload,managesieve
                  ROUNDCUBEMAIL_UPLOAD_MAX_FILESIZE: 25M
                volumes:
                  - $path/webmail:/var/roundcube/config
                  # /var/roundcube/db is where the image puts its sqlite file
                  # (ROUNDCUBEMAIL_DB_DIR); mounted anywhere else the database
                  # stays in the container layer and every recreate throws
                  # away the users' settings, contacts and address book.
                  - $path/webmail-db:/var/roundcube/db
                ports:
                  # Loopback only: Caddy terminates TLS in front of it, which
                  # also puts it under the lockdown guard like every other UI.
                  - "127.0.0.1:$WEB_UI_PORT:80"
            """.trimIndent(),
            envTemplate = envTemplate(context)
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.dockerMailserverPath
        val lang = context.language
        val admin = context.settings.adminUsername
        val hostname = "mail.${context.domain}"
        val domains = listOf(context.domain) + context.additionalDomains
        return listOf(
            """
            log "Docker Mailserver: ${L10nServices.serviceStarting(lang)}"
            install -d -m 755 $path $path/mail-data $path/mail-state $path/mail-logs $path/config $path/webmail $path/webmail-db
            # The certificate directory is root-only: the container reads it
            # read-only, and nothing else on the host has business there.
            install -d -m 700 $path/certs
            # SSL_TYPE=manual does NOT degrade when the files are missing: the
            # engine prints "File … does not exist!", shuts down, and
            # `restart: unless-stopped` turns that into a permanent crash
            # loop. Caddy only obtains the real certificate two steps later,
            # so on a fresh install there is nothing to point at yet — and a
            # container stuck in that loop never gets its first mailbox or its
            # DKIM keys either. A self-signed placeholder lets the engine boot;
            # the sync below replaces it the moment Caddy has the real one.
            # Live-found: without this the whole engine never starts.
            if [ ! -s $path/certs/cert.pem ] || [ ! -s $path/certs/key.pem ]; then
              if openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
                   -subj "/CN=$hostname" -addext "subjectAltName=DNS:$hostname" \
                   -keyout $path/certs/key.pem -out $path/certs/cert.pem >/dev/null 2>&1; then
                chmod 644 $path/certs/cert.pem
                chmod 600 $path/certs/key.pem
              else
                log "${L10nServices.dmsPlaceholderCertFailed(lang)}"
              fi
            fi
            cd $path
            docker compose -p $COMPOSE_PROJECT pull -q
            docker compose -p $COMPOSE_PROJECT up -d
            """.trimIndent(),
            certSyncStep(context),
            """
            # First mailbox and DKIM keys. Nothing here is fatal and no output
            # is discarded — the same rule the mailcow API, the Nextcloud occ
            # and the Mailu CLI blocks follow: errexit in the middle of this
            # step would take the remaining services and the revocation of the
            # install key with it, and a mailbox is addable afterwards.
            DMS_OUT=""
            dms_exec() { DMS_OUT="${SH}(timeout 120 docker exec $CONTAINER_NAME "${SH}@" 2>&1)"; }
            # Passwords go in on stdin, never in argv: the arguments of
            # `docker exec` are readable out of /proc by every account on the
            # box. The helper asks for the password twice, so it is fed twice.
            # ${SH}1 add|update, ${SH}2 address, ${SH}3 password.
            dms_mailbox() {
              DMS_OUT="${SH}(printf '%s\n%s\n' "${SH}3" "${SH}3" \
                | timeout 120 docker exec -i $CONTAINER_NAME setup email "${SH}1" "${SH}2" 2>&1)"
            }
            dms_why() { printf '%s' "${SH}DMS_OUT" | tr -d '\r\n' | cut -c1-300; }
            # A deadline, not a number of tries: each attempt can burn its own
            # timeout, so counting attempts leaves the real wait unbounded.
            # The probe is `setup help` and NOT `setup email list`: the list
            # subcommand exits 1 while no account exists — which is exactly the
            # state of every fresh install — so it answered "not ready" until
            # the deadline ran out and neither the first mailbox nor the DKIM
            # keys were ever created.
            DMS_READY=0
            DMS_TRY=0
            DMS_DEADLINE=${SH}((${SH}(date +%s) + 300))
            while [ "${SH}(date +%s)" -lt "${SH}DMS_DEADLINE" ]; do
              if dms_exec setup help; then DMS_READY=1; break; fi
              DMS_TRY=${SH}((DMS_TRY + 1))
              # Heartbeat every ~30 s: silence here is indistinguishable from a
              # hung install in the app's progress view.
              if [ "${SH}((DMS_TRY % 6))" -eq 0 ]; then
                log "${L10nServices.dmsWaiting(lang)} (${SH}(dms_why))"
              fi
              sleep 5
            done
            if [ "${SH}DMS_READY" -eq 1 ]; then
              DMS_PASSWORD="${SH}(grep '^FIRST_MAILBOX_PASSWORD=' $path/.env | cut -d= -f2- || true)"
              # Its failure IS the answer "there are no accounts yet" — the
              # account file does not exist until the first one is added — so
              # it must not take the step down with it under errexit.
              dms_exec setup email list || true
              # `email list` prints one line per mailbox; matching the address
              # at a word boundary keeps a lookalike account from passing for
              # this one and silently skipping creation — the Forgejo lesson.
              if ! printf '%s' "${SH}DMS_OUT" | grep -qE "(^|[[:space:]*])$admin@${context.domain}([[:space:]]|${SH})"; then
                if [ -n "${SH}DMS_PASSWORD" ]; then
                  dms_mailbox add "$admin@${context.domain}" "${SH}DMS_PASSWORD" \
                    || log "${L10nServices.dmsMailboxFailed(lang)} (${SH}(dms_why))"
                fi
              fi
              @DKIMSTEPS@
            else
              log "${L10nServices.dmsUnavailable(lang)} (${SH}(dms_why))"
            fi
            """.trimIndent().embedding("DKIMSTEPS" to dkimSteps(domains, lang, path)),
            managementScripts(context)
        )
    }

    /** DKIM keys, one per mail domain */
    private fun dkimSteps(domains: List<String>, lang: AppLanguage, path: String): String {
        val keys = domains.joinToString("\n") { domain ->
            """
              # Idempotent: the helper skips a domain that already has a key.
              # The selector is spelled out — the default is `mail`, and the
              # DNS artifact tells the user to publish `dkim._domainkey`.
              dms_exec setup config dkim keysize $DKIM_KEY_SIZE selector $DKIM_SELECTOR domain $domain \
                || log "${L10nServices.dmsDKIMFailed(lang, domain)} (${SH}(dms_why))"
            """.trimIndent().prependIndent("  ")
        }
        return keys + "\n" + dkimSigningDomainFix(path)
    }

    override fun extraSudoers(context: ServiceContext) = listOf(
        PrivilegedCommand(MAILBOX_SCRIPT_PATH, ""),
        PrivilegedCommand(DKIM_DUMP_SCRIPT_PATH, "")
    )

    override fun firewallPorts(context: ServiceContext) = listOf(
        FirewallPort(25, comment = "SMTP"),
        FirewallPort(465, comment = "SMTPS"),
        FirewallPort(587, comment = "Submission"),
        FirewallPort(143, comment = "IMAP"),
        FirewallPort(993, comment = "IMAPS"),
        FirewallPort(4190, comment = "Sieve")
    )

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = "mail.${context.domain}", upstreamPort = WEB_UI_PORT)

    override fun dnsHostnames(context: ServiceContext): List<String> = emptyList()

    override fun reportSteps(context: ServiceContext): List<String> {
        val path = context.settings.dockerMailserverPath
        val lang = context.language
        val hostname = "mail.${context.domain}"
        val admin = context.settings.adminUsername
        return listOf("""
            echo "Docker Mailserver:"
            echo "  ${L10nServices.webmailLabel(lang)}:     https://$hostname"
            echo "  ${L10nServices.firstMailboxLabel(lang)}: $admin@${context.domain}"
            echo "  ${L10nServices.passwordGeneratedOnServerLabel(lang)}: ${SH}(grep '^FIRST_MAILBOX_PASSWORD=' $path/.env | cut -d= -f2-)"
            echo "  ${L10nServices.dmsMailboxesNote(lang)}"
            echo "  ${L10nServices.dkimRecordsLabel(lang)}:"
            $DKIM_DUMP_SCRIPT_PATH 2>/dev/null | grep '^$DKIM_MARKER ' | while read -r _ NAME VALUE; do
              echo "    ${SH}NAME TXT ${SH}VALUE"
            done || echo "    ${L10nServices.dmsDKIMPendingNote(lang)}"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.dockerMailserverPath
        return ServiceActions(
            statusProbe = StatusProbe.ComposeProject(
                project = COMPOSE_PROJECT,
                list = PrivilegedCommand("/usr/bin/docker", "compose -p $COMPOSE_PROJECT ps")
            ),
            restart = ServicePower.compose(COMPOSE_PROJECT, "restart",
                                           ServiceCommand.TimeoutClass.LONG),
            start = ServicePower.compose(COMPOSE_PROJECT, "start",
                                         ServiceCommand.TimeoutClass.LONG),
            stop = ServicePower.compose(COMPOSE_PROJECT, "stop",
                                        ServiceCommand.TimeoutClass.LONG),
            backup = BackupSpec.WrapperScript(BackupWrapperSpec(
                wrapperTarget = WRAPPER_TARGET,
                backupDir = context.backupDirectory(id),
                run = ServiceCommand(
                    PrivilegedCommand(BackupWrapperSpec.WRAPPER_PATH, ""),
                    ServiceCommand.TimeoutClass.LONG,
                    streamsOutput = true
                ),
                plan = BackupPlan.Archive(ArchiveBackupPlan(
                    composeProject = COMPOSE_PROJECT,
                    dataPath = path,
                    databases = emptyList(),
                    quiesceServices = listOf("mailserver", "webmail"),
                    encryptsByDefault = true,
                    sizePaths = listOf("$path/mail-data", "$path/config"),
                    // Logs restore nothing and grow without bound.
                    excludes = listOf("${archiveSlot(path)}/mail-logs")
                ))
            )),
            restore = RestoreSpec(
                wrapperTarget = WRAPPER_TARGET,
                backupDir = context.backupDirectory(id),
                needsPassphrase = false,
                privileged = PrivilegedCommand(RestoreSpec.WRAPPER_PATH, "")
            )
        )
    }

    override fun updateSpec(context: ServiceContext) =
        UpdateSpec(images = listOf(IMAGE, WEBMAIL_IMAGE))

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        dataPaths = listOf(context.settings.dockerMailserverPath),
        postSteps = listOf(
            "systemctl disable --now $CERT_SYNC_UNIT.timer >/dev/null 2>&1 || true",
            "rm -f /etc/systemd/system/$CERT_SYNC_UNIT.service " +
                "/etc/systemd/system/$CERT_SYNC_UNIT.timer " +
                "'$CERT_SYNC_SCRIPT_PATH' '$MAILBOX_SCRIPT_PATH' " +
                "'$DKIM_DUMP_SCRIPT_PATH'",
            "rm -f '$CERT_SYNC_SCRIPT_PATH'.bak.* '$MAILBOX_SCRIPT_PATH'.bak.* " +
                "'$DKIM_DUMP_SCRIPT_PATH'.bak.*",
            "systemctl daemon-reload || true"
        )
    )

    private fun certSyncStep(context: ServiceContext): String {
        val path = context.settings.dockerMailserverPath
        val hostname = "mail.${context.domain}"
        return """
        cat > $CERT_SYNC_SCRIPT_PATH <<'EOF_DMS_CERTSYNC'
        #!/bin/bash
        set -eu
        DOMAIN="$hostname"
        DMS="$path"
        DEST="${SH}DMS/certs"
        CADDY_DATA="/var/lib/caddy/.local/share/caddy/certificates"
        SRC_CRT="${SH}(find "${SH}CADDY_DATA" -type f -name "${SH}{DOMAIN}.crt" 2>/dev/null | head -n1)"
        SRC_KEY="${SH}(find "${SH}CADDY_DATA" -type f -name "${SH}{DOMAIN}.key" 2>/dev/null | head -n1)"
        # No certificate yet (ACME still pending) is not an error: the timer
        # comes back every hour and the mail ports keep serving what they have.
        if [ -z "${SH}SRC_CRT" ] || [ -z "${SH}SRC_KEY" ]; then exit 0; fi
        if cmp -s "${SH}SRC_CRT" "${SH}DEST/cert.pem" && cmp -s "${SH}SRC_KEY" "${SH}DEST/key.pem"; then exit 0; fi
        cp "${SH}SRC_CRT" "${SH}DEST/cert.pem"
        cp "${SH}SRC_KEY" "${SH}DEST/key.pem"
        chmod 644 "${SH}DEST/cert.pem"
        chmod 600 "${SH}DEST/key.pem"
        cd "${SH}DMS"
        # Postfix and Dovecot read the certificate at start; the container has
        # no reload hook for a file that changed under it.
        docker compose -p $COMPOSE_PROJECT restart $CONTAINER_NAME >/dev/null 2>&1 || true
        EOF_DMS_CERTSYNC
        chmod 700 $CERT_SYNC_SCRIPT_PATH
        cat > /etc/systemd/system/$CERT_SYNC_UNIT.service <<'EOF_DMS_CERTSVC'
        [Unit]
        Description=Sync Caddy TLS certificate into Docker Mailserver (SMTP/IMAPS)
        After=docker.service
        [Service]
        Type=oneshot
        ExecStart=$CERT_SYNC_SCRIPT_PATH
        EOF_DMS_CERTSVC
        cat > /etc/systemd/system/$CERT_SYNC_UNIT.timer <<'EOF_DMS_CERTTIMER'
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
        systemctl enable --now $CERT_SYNC_UNIT.timer >/dev/null 2>&1 || true
        $CERT_SYNC_SCRIPT_PATH || true
        """.trimIndent()
    }

    private fun managementScripts(context: ServiceContext): String {
        val path = context.settings.dockerMailserverPath
        return """
        cat > $MAILBOX_SCRIPT_PATH <<'EOF_DMS_MAILBOX'
        #!/bin/bash
        # Mailbox management for the gryonixNexus dashboard.
        # Usage: gryonixnexus-dms-mailbox.sh list
        #        gryonixnexus-dms-mailbox.sh add <address> (password on stdin)
        #        gryonixnexus-dms-mailbox.sh del <address>
        #        gryonixnexus-dms-mailbox.sh password <address> (password on stdin)
        set -euo pipefail
        cd $path 2>/dev/null || { echo "docker mailserver is not installed" >&2; exit 2; }
        ACTION="${SH}{1:-}"
        ADDRESS="${SH}{2:-}"
        # The address is checked HERE, not by the container: this script runs as
        # root through sudo, so an argument that reaches `docker exec` unchecked
        # is an argument that reaches root. One local part, one domain, no
        # shell metacharacters, no leading dash that could read as a flag.
        check_address() {
          case "${SH}ADDRESS" in
            -*|*[!a-zA-Z0-9.@_+-]*|*@*@*|@*|*@) echo "invalid address: ${SH}{ADDRESS}" >&2; exit 2 ;;
            *@*) ;;
            *) echo "invalid address: ${SH}{ADDRESS}" >&2; exit 2 ;;
          esac
        }
        # The password arrives on stdin, never in argv, where /proc would show
        # it to every account on the box.
        read_password() {
          if [ -t 0 ]; then echo "a password is required on stdin" >&2; exit 2; fi
          PASSWORD="${SH}(cat)"
          [ -n "${SH}PASSWORD" ] || { echo "the password is empty" >&2; exit 2; }
        }
        case "${SH}ACTION" in
          list)
            # An install with no mailboxes yet is an EMPTY LIST, not a failure:
            # `setup email list` exits 1 for as long as the account file does
            # not exist, and the app would show an error where it should show
            # "no mailboxes". The file is checked on the host — it is the same
            # directory the container has mounted, so this adds no second
            # source of truth. A container that is down still makes the listing
            # fail, which the app does need to see.
            if [ -s $path/config/postfix-accounts.cf ]; then
              docker exec $CONTAINER_NAME setup email list
            fi
            ;;
          add)
            check_address; read_password
            # The password goes down stdin into the container as well, not as
            # an argument: `docker exec` argv is world-readable in /proc. The
            # helper prompts for it twice, hence the two lines.
            printf '%s\n%s\n' "${SH}PASSWORD" "${SH}PASSWORD" \
              | docker exec -i $CONTAINER_NAME setup email add "${SH}ADDRESS" >/dev/null
            echo "GRYONIXNEXUS_MAILBOX_DONE add ${SH}{ADDRESS}"
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
              if [ "${SH}DEL_TRY" -ge 5 ]; then
                docker exec $CONTAINER_NAME setup email del -y "${SH}ADDRESS" >/dev/null
                break
              fi
              if docker exec $CONTAINER_NAME setup email del -y "${SH}ADDRESS" >/dev/null 2>&1; then
                break
              fi
              DEL_TRY=${SH}((DEL_TRY + 1))
              sleep 2
            done
            echo "GRYONIXNEXUS_MAILBOX_DONE del ${SH}{ADDRESS}"
            ;;
          password)
            check_address; read_password
            printf '%s\n%s\n' "${SH}PASSWORD" "${SH}PASSWORD" \
              | docker exec -i $CONTAINER_NAME setup email update "${SH}ADDRESS" >/dev/null
            echo "GRYONIXNEXUS_MAILBOX_DONE password ${SH}{ADDRESS}"
            ;;
          *)
            echo "unsupported action: ${SH}{ACTION}" >&2; exit 2 ;;
        esac
        EOF_DMS_MAILBOX
        chmod 700 $MAILBOX_SCRIPT_PATH
        cat > $DKIM_DUMP_SCRIPT_PATH <<'EOF_DMS_DKIM'
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
        for F in $path/config/opendkim/keys/*/dkim.txt; do
          [ -f "${SH}F" ] || continue
          D="${SH}(basename "${SH}(dirname "${SH}F")")"
          V="${SH}(grep -o '"[^"]*"' "${SH}F" | tr -d '"\n' | head -c 2000)"
          [ -n "${SH}V" ] || continue
          # Bare, no quotes around ${SH}V — mailcow and Mailu both print the value
          # unquoted (see their own dkimMarker lines), and DKIMRecordParser /
          # DKIMExport downstream both expect the bare "v=DKIM1;...;p=..."
          # string, adding their own quoting where a format needs it (the BIND
          # zone export, the DNS provider's own form). A quoted value here
          # would ship the literal `"` characters into every artifact and
          # clipboard copy built from it.
          echo "$DKIM_MARKER $DKIM_SELECTOR._domainkey.${SH}D ${SH}V"
        done
        echo "$DKIM_DUMP_DONE_MARKER"
        EOF_DMS_DKIM
        chmod 700 $DKIM_DUMP_SCRIPT_PATH
        """.trimIndent()
    }

    companion object {
        const val COMPOSE_PROJECT = "dockermailserver"

        /** Loopback port Caddy proxies the webmail to */
        const val WEB_UI_PORT = 8086
        const val CONTAINER_NAME = "mailserver"
        const val WEBMAIL_CONTAINER_NAME = "mailserver-webmail"
        val WRAPPER_TARGET = ServiceID.DOCKER_MAILSERVER.rawValue

        const val IMAGE = "ghcr.io/docker-mailserver/docker-mailserver:15.1.0"

        /** Roundcube supplies the webmail this engine has none of */
        const val WEBMAIL_IMAGE = "roundcube/roundcubemail:1.6.17-apache"

        /** Sync script + timer that copy Caddy's certificate in */
        const val CERT_SYNC_SCRIPT_PATH = "/opt/gryonixnexus-dms-cert-sync.sh"
        const val CERT_SYNC_UNIT = "gryonixnexus-dms-cert-sync"

        const val MAILBOX_SCRIPT_PATH = "/opt/gryonixnexus-dms-mailbox.sh"

        const val DKIM_DUMP_SCRIPT_PATH = "/opt/gryonixnexus-dms-dkim.sh"
        const val DKIM_MARKER = "GRYONIXNEXUS_DKIM"
        const val DKIM_DUMP_DONE_MARKER = "GRYONIXNEXUS_DKIM_DONE"

        const val DKIM_SELECTOR = "dkim"
        const val DKIM_KEY_SIZE = 2048

        fun archiveSlot(path: String): String =
            path.split("/").lastOrNull()?.takeIf { it.isNotEmpty() } ?: path

        fun dkimSigningDomainFix(path: String): String = """
          # rspamd looks the signing key up under the eSLD unless told not to,
          # so a mail domain that is a SUBDOMAIN never matches its own key and
          # goes out unsigned. Our keys are filed under the exact domain.
          DMS_DKIM_CONF="$path/config/rspamd/override.d/dkim_signing.conf"
          if [ -f "${SH}DMS_DKIM_CONF" ] && grep -q '^use_esld = true;' "${SH}DMS_DKIM_CONF"; then
            sed -i 's/^use_esld = true;/use_esld = false;/' "${SH}DMS_DKIM_CONF"
            # rspamd reads this at start; without the restart the fix applies
            # only after the next unrelated container restart.
            dms_exec supervisorctl restart rspamd || true
          fi
        """.trimIndent().prependIndent("  ")

        private fun envTemplate(context: ServiceContext): String {
            val hostname = "mail.${context.domain}"
            return """
            # Managed by gryonixNexus. Generated on the server; the __RANDOM__ marker
            # is replaced once and then left alone on re-runs.
            OVERRIDE_HOSTNAME=$hostname
            POSTMASTER_ADDRESS=postmaster@${context.domain}
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
            """.trimIndent()
        }
    }
}
