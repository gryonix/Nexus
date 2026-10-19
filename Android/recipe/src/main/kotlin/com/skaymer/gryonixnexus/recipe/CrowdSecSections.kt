package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.Apt
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.embedding

object CrowdSecSections {
    /** Loopback-only, and never mailcow's 8080 — see the type header */
    const val LAPI_LISTEN_ADDR = "127.0.0.1:8237"

    private const val BOUNCER_NAME = "gryonixnexus-firewall-bouncer"

    /** Covers both acquisition sources below */
    private const val COLLECTIONS = "crowdsecurity/sshd crowdsecurity/caddy crowdsecurity/linux"

    private val ACQUISITION_YAML = """
        # Managed by gryonixNexus. Journald, not files: this fleet runs Debian with
        # rsyslog inactive, so /var/log/auth.log does not exist and a file-based
        # acquisition would parse nothing while reporting itself healthy.
        source: journalctl
        journalctl_filter:
         - "_SYSTEMD_UNIT=ssh.service"
         - "_SYSTEMD_UNIT=sshd.service"
        labels:
         type: syslog
        ---
        source: journalctl
        journalctl_filter:
         - "_SYSTEMD_UNIT=caddy.service"
        labels:
         type: caddy
    """.trimIndent()

    fun install(enabled: Boolean, language: AppLanguage): String {
        if (!enabled) return "log \"${L10nScripts.crowdsecDisabledLog(language)}\""
        return """
            log "${L10nScripts.crowdsecInstallingLog(language)}"
            (
            set -e
            curl -fsSL https://install.crowdsec.net | sh
            dpkg --configure -a --force-confdef --force-confold || true
            # Engine first, in its own call: apt given both packages on one line
            # has configured the bouncer first on this fleet, and its
            # post-installation script could not mint itself an API key because
            # the engine did not exist yet — the unit starts and talks to nothing.
            apt-get ${Apt.OPTIONS} install -y crowdsec
            apt-get ${Apt.OPTIONS} install -y crowdsec-firewall-bouncer-nftables

            # acquis.d, not the package's own acquis.yaml: CrowdSec's supported
            # directory for additional sources, so an upgrade never fights us for
            # the file.
            install -d -m 755 /etc/crowdsec/acquis.d
            cat > /etc/crowdsec/acquis.d/gryonixnexus.yaml <<'EOF_CS_ACQUIS'
            @ACQUISITION@
            EOF_CS_ACQUIS

            # Move the local API off 8080 BEFORE the engine starts — see the type
            # header. All three files have to agree: listen_uri moves the door,
            # the other two are how cscli and the bouncer find it. Missing files
            # (a postinst that has not run yet) are left alone rather than
            # failing the block — the engine start below still gets the newly
            # written acquisition either way.
            [ -f /etc/crowdsec/config.yaml ] && \
              sed -i "s|^\( *\)listen_uri:.*|\1listen_uri: $LAPI_LISTEN_ADDR|" /etc/crowdsec/config.yaml
            [ -f /etc/crowdsec/local_api_credentials.yaml ] && \
              sed -i "s|^url:.*|url: http://$LAPI_LISTEN_ADDR|" /etc/crowdsec/local_api_credentials.yaml
            [ -f /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml ] && \
              sed -i "s|^api_url:.*|api_url: http://$LAPI_LISTEN_ADDR/|" /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml

            # --error lowers cscli's log level so an already-installed collection
            # is silent; the command still succeeds, which is what makes this
            # idempotent on a re-run.
            cscli collections install $COLLECTIONS --error || true
            cscli hub update --error || true

            systemctl enable --now crowdsec >/dev/null 2>&1 || true
            systemctl restart crowdsec

            # A key the bouncer cannot use is the same outcome as no bouncer at
            # all — registered only when the config carries no real key yet, so a
            # re-run does not mint a new one and restart a bouncer that already
            # works.
            BOUNCER_CFG=/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
            if [ -f "${SH}BOUNCER_CFG" ]; then
              CURRENT_KEY="${SH}(sed -n 's/^api_key: *//p' "${SH}BOUNCER_CFG" | head -n1 | tr -d '"'\''')"
              if [ -z "${SH}{CURRENT_KEY:-}" ] || [ "${SH}{CURRENT_KEY:-}" = "<API_KEY>" ]; then
                cscli bouncers delete $BOUNCER_NAME >/dev/null 2>&1 || true
                KEY="${SH}(cscli bouncers add $BOUNCER_NAME -o raw)"
                if [ -n "${SH}{KEY:-}" ]; then
                  sed -i "s|^api_key:.*|api_key: ${SH}KEY|" "${SH}BOUNCER_CFG"
                fi
              fi
              # Refused rather than repaired when the bouncer is not aimed at its
              # own table: a bouncer aimed at the table this script's own
              # `flush ruleset` firewall step rewrites would have its bans erased
              # by the next provision, with nothing on either side to say so —
              # the same refusal `bouncer_targets_its_own_table` makes.
              if grep -Eq '^[[:space:]]*table:[[:space:]]*"?crowdsec6?"?[[:space:]]*${SH}' "${SH}BOUNCER_CFG"; then
                systemctl enable --now crowdsec-firewall-bouncer >/dev/null 2>&1 || true
                systemctl try-restart crowdsec-firewall-bouncer || true
              fi
            fi
            ) || echo "${L10nScripts.crowdsecFailedLog(language)}" >&2
        """.trimIndent().embedding("ACQUISITION" to ACQUISITION_YAML)
    }
}
