package com.skaymer.gryonixnexus.catalog.services

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

/** Mailu — the alternative mail engine, offered instead of mailcow */
class MailuService : MailEngineService {
    override val id = ServiceID.MAILU
    override val displayName = "Mailu"
    override val systemImage = "envelope.badge.shield.half.filled"

    /** One mail stack at a time */
    override val category = ServiceCategory.MAIL
    override val usesSharedAdminLogin = true
    override val runtime = ServiceRuntime.Docker(COMPOSE_PROJECT)

    override val resources = ServiceResources(memoryMB = 1536, diskGB = 6)

    override fun requiredHostname(domain: String): String = "mail.$domain"

    override fun composeFile(context: ServiceContext): ComposeFile {
        val path = context.settings.mailuPath
        val subnet = context.settings.mailuSubnet
        val resolver = resolverAddress(subnet)
        return ComposeFile(
            directory = path,
            composeContents = """
            services:
              redis:
                image: $CACHE_IMAGE
                restart: unless-stopped
                volumes:
                  - $path/redis:/data
              front:
                image: ${image(Component.NGINX)}
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
                  - "127.0.0.1:$WEB_UI_PORT:80"
                  - "25:25"
                  - "465:465"
                  - "993:993"
                  - "4190:4190"
                volumes:
                  - $path/certs:/certs
                  - $path/overrides/nginx:/overrides:ro
              resolver:
                image: ${image(Component.UNBOUND)}
                env_file: .env
                restart: unless-stopped
                networks:
                  default:
                    ipv4_address: $resolver
              admin:
                image: ${image(Component.ADMIN)}
                restart: unless-stopped
                env_file: .env
                volumes:
                  - $path/data:/data
                  - $path/dkim:/dkim
                depends_on:
                  - redis
                  - resolver
                dns:
                  - $resolver
              imap:
                image: ${image(Component.DOVECOT)}
                restart: unless-stopped
                env_file: .env
                volumes:
                  - $path/mail:/mail
                  - $path/overrides:/overrides:ro
                depends_on:
                  - front
                  - resolver
                dns:
                  - $resolver
              smtp:
                image: ${image(Component.POSTFIX)}
                restart: unless-stopped
                env_file: .env
                volumes:
                  - $path/mailqueue:/queue
                  - $path/overrides:/overrides:ro
                depends_on:
                  - front
                  - resolver
                dns:
                  - $resolver
              antispam:
                image: ${image(Component.RSPAMD)}
                restart: unless-stopped
                env_file: .env
                volumes:
                  - $path/filter:/var/lib/rspamd
                  - $path/overrides/rspamd:/etc/rspamd/override.d:ro
                depends_on:
                  - front
                  - redis
                  - resolver
                dns:
                  - $resolver
              webmail:
                image: ${image(Component.WEBMAIL)}
                restart: unless-stopped
                env_file: .env
                volumes:
                  - $path/webmail:/data
                  - $path/overrides/roundcube:/overrides:ro
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
                    - subnet: $subnet
            """.trimIndent(),
            envTemplate = envTemplate(context)
        )
    }

    override fun setupSteps(context: ServiceContext): List<String> {
        val path = context.settings.mailuPath
        val lang = context.language
        val hostname = "mail.${context.domain}"
        val domains = listOf(context.domain) + context.additionalDomains
        val domainYAML = domains.joinToString("\n") { "  - name: $it\n    dkim_key: -generate-" }
        return listOf(
            """
            log "Mailu: ${L10nServices.serviceStarting(lang)}"
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
            install -d -m 755 $path
            install -d -m 700 $path/certs $path/dkim $path/data
            install -d -m 755 $path/mail $path/mailqueue $path/filter $path/webmail $path/redis
            install -d -m 755 $path/overrides $path/overrides/nginx $path/overrides/rspamd $path/overrides/roundcube
            cd $path
            docker compose -p $COMPOSE_PROJECT pull -q
            docker compose -p $COMPOSE_PROJECT up -d
            """.trimIndent(),
            certSyncStep(context),
            """
            # Domains and DKIM keys. Nothing here is fatal and no output is
            # discarded — the same rule the mailcow API and Nextcloud occ
            # blocks follow: errexit in the middle of this step would take the
            # remaining services and the revocation of the install key with it,
            # and a mail domain is fixable from the admin UI afterwards.
            # Its own cd: sections share one shell and the working directory
            # persists across them, so relying on an earlier step's cd is a
            # dependency nobody can see when the steps are reordered.
            cd $path
            MU_OUT=""
            # `-u`: never as root — see `adminRunAsUser`. A root exec here
            # creates /data/main.db before the engine does, and the engine
            # then cannot write its own schema into it.
            mu_exec() { MU_OUT="${SH}(timeout 120 docker compose -p $COMPOSE_PROJECT exec -T -u $ADMIN_RUN_AS_USER $ADMIN_SERVICE "${SH}@" 2>&1)"; }
            mu_why() { printf '%s' "${SH}MU_OUT" | tr -d '\r\n' | cut -c1-300; }
            # A deadline, not a number of attempts: each attempt can burn its
            # own timeout, so counting attempts leaves the real wait unbounded.
            # `flask mailu config-export` has to reach the database, which is
            # what is actually not ready yet while the containers report up.
            MU_READY=0
            MU_TRY=0
            MU_DEADLINE=${SH}((${SH}(date +%s) + 300))
            while [ "${SH}(date +%s)" -lt "${SH}MU_DEADLINE" ]; do
              if mu_exec flask mailu config-export -j; then MU_READY=1; break; fi
              MU_TRY=${SH}((MU_TRY + 1))
              # Heartbeat every ~30 s: silence here is indistinguishable from a
              # hung install in the app's progress view.
              if [ "${SH}((MU_TRY % 6))" -eq 0 ]; then
                log "${L10nServices.mailuWaiting(lang)} (${SH}(mu_why))"
              fi
              sleep 5
            done
            if [ "${SH}MU_READY" -eq 1 ]; then
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
              if ! printf '%s\n' 'domain:' '@DOMAINYAML@' \
                   | timeout 120 docker compose -p $COMPOSE_PROJECT exec -T -u $ADMIN_RUN_AS_USER $ADMIN_SERVICE \
                     flask mailu config-import -q -u >/dev/null 2>&1; then
                log "${L10nServices.mailuDomainImportFailed(lang)}"
              fi
            else
              log "${L10nServices.mailuUnavailable(lang)} (${SH}(mu_why))"
            fi
            """.trimIndent().embedding("DOMAINYAML" to domainYAML),
            dkimDumpStep(context, hostname)
        )
    }

    private fun certSyncStep(context: ServiceContext): String {
        val path = context.settings.mailuPath
        val hostname = "mail.${context.domain}"
        return """
        cat > $CERT_SYNC_SCRIPT_PATH <<'EOF_MU_CERTSYNC'
        #!/bin/bash
        set -eu
        DOMAIN="$hostname"
        MAILU="$path"
        DEST="${SH}MAILU/certs"
        CADDY_DATA="/var/lib/caddy/.local/share/caddy/certificates"
        SRC_CRT="${SH}(find "${SH}CADDY_DATA" -type f -name "${SH}{DOMAIN}.crt" 2>/dev/null | head -n1)"
        SRC_KEY="${SH}(find "${SH}CADDY_DATA" -type f -name "${SH}{DOMAIN}.key" 2>/dev/null | head -n1)"
        # No certificate yet (ACME still pending) is not an error: the timer
        # comes back every hour and the mail ports keep serving the old one.
        if [ -z "${SH}SRC_CRT" ] || [ -z "${SH}SRC_KEY" ]; then exit 0; fi
        if cmp -s "${SH}SRC_CRT" "${SH}DEST/cert.pem" && cmp -s "${SH}SRC_KEY" "${SH}DEST/key.pem"; then exit 0; fi
        cp "${SH}SRC_CRT" "${SH}DEST/cert.pem"
        cp "${SH}SRC_KEY" "${SH}DEST/key.pem"
        chmod 600 "${SH}DEST/cert.pem" "${SH}DEST/key.pem"
        cd "${SH}MAILU"
        # Only the services that terminate TLS themselves; restarting the whole
        # project would drop deliveries in flight for nothing.
        docker compose -p $COMPOSE_PROJECT restart $FRONT_SERVICE >/dev/null 2>&1 || true
        EOF_MU_CERTSYNC
        chmod 700 $CERT_SYNC_SCRIPT_PATH
        cat > /etc/systemd/system/$CERT_SYNC_UNIT.service <<'EOF_MU_CERTSVC'
        [Unit]
        Description=Sync Caddy TLS certificate into Mailu (SMTP/IMAPS)
        After=docker.service
        [Service]
        Type=oneshot
        ExecStart=$CERT_SYNC_SCRIPT_PATH
        EOF_MU_CERTSVC
        cat > /etc/systemd/system/$CERT_SYNC_UNIT.timer <<'EOF_MU_CERTTIMER'
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
        systemctl enable --now $CERT_SYNC_UNIT.timer >/dev/null 2>&1 || true
        $CERT_SYNC_SCRIPT_PATH || true
        """.trimIndent()
    }

    private fun dkimDumpStep(context: ServiceContext, hostname: String): String {
        val path = context.settings.mailuPath
        return """
        cat > $DKIM_DUMP_SCRIPT_PATH <<'EOF_GD_MU_DKIM'
        #!/bin/bash
        set -euo pipefail
        cd $path 2>/dev/null || { echo "$DKIM_DUMP_DONE_MARKER"; exit 0; }
        # --dns asks Mailu for the records it would publish; the private key is
        # NOT in that projection, which is why this dump can be whitelisted.
        OUT="${SH}(timeout 60 docker compose -p $COMPOSE_PROJECT exec -T -u $ADMIN_RUN_AS_USER $ADMIN_SERVICE \
               flask mailu config-export -d -j domain 2>/dev/null || true)"
        printf '%s' "${SH}OUT" | python3 -c '
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
            print("$DKIM_MARKER " + name.rstrip(".") + " " + value)
        ' 2>/dev/null || true
        echo "$DKIM_DUMP_DONE_MARKER"
        EOF_GD_MU_DKIM
        chmod 700 $DKIM_DUMP_SCRIPT_PATH
        """.trimIndent()
    }

    override fun extraSudoers(context: ServiceContext) =
        listOf(PrivilegedCommand(DKIM_DUMP_SCRIPT_PATH, ""))

    /** Only what the engine actually listens on */
    override fun firewallPorts(context: ServiceContext) = listOf(
        FirewallPort(25, comment = "SMTP"),
        FirewallPort(465, comment = "SMTPS (implicit TLS)"),
        FirewallPort(993, comment = "IMAPS (implicit TLS)"),
        FirewallPort(4190, comment = "Sieve")
    )

    override fun webIngress(context: ServiceContext) =
        WebIngress(hostname = "mail.${context.domain}", upstreamPort = WEB_UI_PORT)

    override fun dnsHostnames(context: ServiceContext): List<String> = emptyList()

    override fun reportSteps(context: ServiceContext): List<String> {
        val path = context.settings.mailuPath
        val lang = context.language
        val hostname = "mail.${context.domain}"
        val admin = context.settings.adminUsername
        return listOf("""
            echo "Mailu:        https://$hostname/admin"
            echo "  ${L10nServices.webmailLabel(lang)}:     https://$hostname/webmail"
            echo "  ${L10nServices.administratorLabel(lang)}: $admin@${context.domain}"
            echo "  ${L10nServices.passwordGeneratedOnServerLabel(lang)}: ${SH}(grep '^INITIAL_ADMIN_PW=' $path/.env | cut -d= -f2-)"
            # The DKIM records, straight from the engine that minted them. Not
            # fatal and not silenced: a missing key is a DNS record the user
            # adds later, not a reason to lose the rest of the report.
            echo "  ${L10nServices.mailuClientPortsNote(lang)}"
            echo "  ${L10nServices.dkimRecordsLabel(lang)}:"
            $DKIM_DUMP_SCRIPT_PATH 2>/dev/null | grep '^$DKIM_MARKER ' | while read -r _ NAME VALUE; do
              echo "    ${SH}NAME TXT ${SH}VALUE"
            done || echo "    ${L10nServices.mailuDKIMPendingNote(lang)}"
        """.trimIndent())
    }

    override fun actions(context: ServiceContext): ServiceActions {
        val path = context.settings.mailuPath
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
                    quiesceServices = listOf("front", "admin", "imap", "smtp",
                                             "antispam", "webmail", "redis", "resolver"),
                    encryptsByDefault = true,
                    sizePaths = listOf("$path/mail", "$path/data", "$path/webmail"),
                    excludes = listOf("${archiveSlot(path)}/filter",
                                      "${archiveSlot(path)}/mailqueue")
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
        UpdateSpec(images = listOf(CACHE_IMAGE) + Component.entries.map { image(it) })

    override fun uninstallSpec(context: ServiceContext) = UninstallSpec(
        composeProject = COMPOSE_PROJECT,
        dataPaths = listOf(context.settings.mailuPath),
        postSteps = listOf(
            "systemctl disable --now $CERT_SYNC_UNIT.timer >/dev/null 2>&1 || true",
            "rm -f /etc/systemd/system/$CERT_SYNC_UNIT.service " +
                "/etc/systemd/system/$CERT_SYNC_UNIT.timer " +
                "'$CERT_SYNC_SCRIPT_PATH' '$DKIM_DUMP_SCRIPT_PATH'",
            "rm -f '$CERT_SYNC_SCRIPT_PATH'.bak.* '$DKIM_DUMP_SCRIPT_PATH'.bak.*",
            "systemctl daemon-reload || true"
        )
    )

    enum class Component(val wireValue: String) {
        NGINX("nginx"), UNBOUND("unbound"), ADMIN("admin"), DOVECOT("dovecot"),
        POSTFIX("postfix"), RSPAMD("rspamd"), WEBMAIL("webmail")
    }

    companion object {
        const val COMPOSE_PROJECT = "mailu"

        /** Loopback port Caddy proxies to */
        const val WEB_UI_PORT = 8085

        const val FRONT_SERVICE = "front"

        const val ADMIN_SERVICE = "admin"

        const val ADMIN_RUN_AS_USER = "mailu"
        val WRAPPER_TARGET = ServiceID.MAILU.rawValue

        /** One CalVer line, patches included */
        const val IMAGE_TAG = "2024.06"

        fun image(component: Component): String =
            "ghcr.io/mailu/${component.wireValue}:$IMAGE_TAG"

        /** Session store and rspamd's backend */
        const val CACHE_IMAGE = "redis:8-alpine"

        /** Sync script + timer that copy Caddy's certificate into Mailu */
        const val CERT_SYNC_SCRIPT_PATH = "/opt/gryonixnexus-mailu-cert-sync.sh"
        const val CERT_SYNC_UNIT = "gryonixnexus-mailu-cert-sync"

        /** Root-owned DKIM dump for the app's configuration export, mirroring mailcow's */
        const val DKIM_DUMP_SCRIPT_PATH = "/opt/gryonixnexus-mailu-dkim.sh"

        const val DKIM_MARKER = "GRYONIXNEXUS_DKIM"
        const val DKIM_DUMP_DONE_MARKER = "GRYONIXNEXUS_DKIM_DONE"

        fun resolverAddress(subnet: String): String = host(subnet, "254")

        fun gatewayAddress(subnet: String): String = host(subnet, "1")

        private fun host(subnet: String, last: String): String {
            val base = subnet.split("/").firstOrNull()?.takeIf { it.isNotEmpty() } ?: subnet
            val octets = base.split(".").toMutableList()
            if (octets.size != 4) return base
            octets[3] = last
            return octets.joinToString(".")
        }

        fun archiveSlot(path: String): String =
            path.split("/").lastOrNull()?.takeIf { it.isNotEmpty() } ?: path

        private fun envTemplate(context: ServiceContext): String {
            val hostname = "mail.${context.domain}"
            val admin = context.settings.adminUsername
            val hostnames = (listOf(context.domain) + context.additionalDomains)
                .joinToString(",") { "mail.$it" }
            return """
            # Managed by gryonixNexus. Generated on the server; secrets are the
            # __RANDOM__ markers, replaced once and then left alone on re-runs.
            SECRET_KEY=__RANDOM__
            DOMAIN=${context.domain}
            HOSTNAMES=$hostnames
            POSTMASTER=postmaster
            # See the type comment: Caddy owns 80/443 and the ACME account, so Mailu
            # serves plain HTTP for the proxy and uses the synced certificate for
            # SMTP/IMAP only.
            TLS_FLAVOR=mail
            SUBNET=${context.settings.mailuSubnet}
            # The first administrator is created by the stack itself. `ifmissing`
            # rather than `update`: a re-run of setup must not reset a password the
            # owner has since changed.
            INITIAL_ADMIN_ACCOUNT=$admin
            INITIAL_ADMIN_DOMAIN=${context.domain}
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
            REAL_IP_FROM=${gatewayAddress(context.settings.mailuSubnet)}
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
            COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT
            MAILU_HOSTNAME=$hostname
            """.trimIndent()
        }
    }
}
