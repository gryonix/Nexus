package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.embedding
import com.skaymer.gryonixnexus.core.DistributionProfile
import com.skaymer.gryonixnexus.core.DistributionProfileID
import com.skaymer.gryonixnexus.core.makeProfile

/** Shared bash sections for setup scripts */
internal object BashSections {
    val supportedDistributionIDs: String
        get() = DistributionProfileID.entries.joinToString("|") { it.makeProfile().osReleaseID }

    fun header(scriptName: String, purpose: String,
               profile: DistributionProfile, language: AppLanguage): String {
        val detected = "${SH}{PRETTY_NAME:-${SH}{ID:-${L10nScripts.unknownValue(language)}}}"
        return """
        #!/usr/bin/env bash
        # Managed by gryonixNexus — $purpose
        # ${SetupMarkers.DISTRIBUTION}: ${profile.osReleaseID}
        # ${L10nScripts.headerRunLine(language, scriptName)}
        # ${L10nScripts.headerSelfContained(language)}
        set -euo pipefail

        # Pinned, never inherited. Whatever launches this script may have
        # tightened its own umask — the app's runner did, to keep the run log
        # private — and a script that adopts it writes 0700 directories and
        # 0600 files that only root can read. Nothing here notices (it IS
        # root), but caddy, mailcow's nginx worker and every other service
        # running as somebody else cannot read what was written for them.
        # Secrets get an explicit chmod at the point they are created; the
        # default has to stay ordinary.
        umask 022

        log()    { printf '\n==> %s\n' "${SH}*"; }
        fail()   { printf '${L10nScripts.errorPrefix(language)}: %s\n' "${SH}*" >&2; exit 1; }
        # Copies a changed file aside, keeping the newest five
        backup() {
          [ -f "${SH}1" ] || return 0
          local last
          last="${SH}(ls -1d "${SH}1".bak.* 2>/dev/null | sort | tail -n 1 || true)"
          if [ -n "${SH}last" ] && cmp -s "${SH}1" "${SH}last"; then return 0; fi
          cp -a "${SH}1" "${SH}1.bak.${SH}(date +%s)"
          ls -1d "${SH}1".bak.* | sort | head -n -5 | xargs -r rm -f
        }
        # Retry a flaky command a few times with a linear backoff. Fresh servers
        # pull many large images at once (mailcow alone is ~15), and a single
        # transient registry error/timeout would otherwise abort the whole run
        # under `set -e` — the user then had to hit Retry by hand. The setup is
        # idempotent, so a re-pull just resumes cached layers.
        retry()  {
          local tries="${SH}1"; shift
          local i=1
          while true; do
            "${SH}@" && return 0
            if [ "${SH}i" -ge "${SH}tries" ]; then return 1; fi
            printf '\n(retry %d/%d) %s\n' "${SH}i" "${SH}tries" "${SH}*" >&2
            sleep ${SH}((i * 5))
            i=${SH}((i + 1))
          done
        }

        [ "${SH}(id -u)" -eq 0 ] || fail "${L10nScripts.rootRequired(language, "${SH}0")}"

        # ${L10nScripts.headerDistributionPinned(language)}
        # The path is a variable so the check can be exercised against a stub
        # file — the alternative was a test that runs a doctored copy of this
        # block and proves nothing about the artifact that ships. It is not a
        # privilege boundary: the script already runs as root.
        gd_os_release="${SH}{GRYONIXNEXUS_OS_RELEASE:-/etc/os-release}"
        [ -r "${SH}gd_os_release" ] || fail "${L10nScripts.osReleaseMissing(language)}"
        # shellcheck source=/dev/null
        . "${SH}gd_os_release"
        # A derivative (Devuan, Linux Mint, Pop!_OS, …) names its base in
        # ID_LIKE and behaves like it for apt and systemd, so it is accepted.
        # A distribution we support in its OWN right never passes as another
        # one: Ubuntu lists debian in ID_LIKE, and letting that through would
        # silently install with the wrong profile instead of saying so.
        if [ "${SH}{ID:-}" != "${profile.osReleaseID}" ]; then
          gd_like_base=0
          for gd_like in ${SH}{ID_LIKE:-}; do
            [ "${SH}gd_like" = "${profile.osReleaseID}" ] && gd_like_base=1
          done
          case "${SH}{ID:-}" in $supportedDistributionIDs) gd_like_base=0 ;; esac
          [ "${SH}gd_like_base" = "1" ] || fail "${L10nScripts.wrongDistribution(language, profile.displayName, detected)}"
          log "${L10nScripts.distributionDerivative(language, detected, profile.displayName)}"
        fi

        export DEBIAN_FRONTEND=noninteractive
        """.trimIndent()
    }

    fun dnsCheck(hostname: String, expectedIP: String, language: AppLanguage): String {
        val resolved = "${SH}{resolved:-${L10nScripts.nothingValue(language)}}"
        return """
        if [ "${SH}{GRYONIXNEXUS_SKIP_DNS_CHECK:-0}" != "1" ]; then
          log "${L10nScripts.dnsCheckLog(language, hostname, expectedIP)}"
          resolved="${SH}(getent ahostsv4 "$hostname" | awk 'NR==1{print ${SH}1}')" || resolved=""
          if [ "${SH}{resolved:-}" != "$expectedIP" ]; then
            echo "${SetupMarkers.DNS_CHECK_FAILED}"
            fail "@DNS_MISMATCH@"
          fi
        fi
        """.trimIndent().embedding(
            "DNS_MISMATCH" to L10nScripts.dnsMismatch(language, hostname, resolved, expectedIP,
                                                      "${SH}0")
        )
    }

    /** Non-interactive package install */
    fun installPackages(packages: List<String>, profile: DistributionProfile,
                        language: AppLanguage): String =
        listOf("log \"${L10nScripts.installingPackages(language)}\"",
               profile.installCommand(packages)).joinToString("\n")

    /** Writes a file via heredoc, backing up any existing one */
    fun writeFile(path: String, contents: String, delimiter: String): String = """
        backup $path
        cat > $path <<'$delimiter'
        @CONTENTS@
        $delimiter
        """.trimIndent().embedding("CONTENTS" to contents)

    /** Applies nftables: syntax check before applying, auto-start on boot */
    fun applyFirewall(ruleset: String): String = """
        log "Firewall (nftables, default-deny)"
        # The drop-in directory the ruleset includes, created BEFORE the syntax
        # check — `nft -c` parses the include too, and a glob that matches
        # nothing is not something every nft version forgives. The placeholder
        # is what guarantees at least one match; the agent writes one file PER
        # SERVICE next to it (`gryonixnexus-svc-<service>.nft`) when it opens a
        # port for something it installs, so removing one service's ports
        # cannot close another's — the chain itself is shared, and the agent
        # rebuilds it from every drop-in in one transaction (see
        # NftablesConfig.agentChainName and the agent's install/firewall.rs).
        install -d -m 755 /etc/nftables.d
        if [ ! -f /etc/nftables.d/gryonixnexus-00-placeholder.nft ]; then
          printf '%s\n' '# Managed by gryonixNexus — keeps the include glob matching. Do not remove.' \
            > /etc/nftables.d/gryonixnexus-00-placeholder.nft
        fi
        @FIREWALL@
        nft -c -f /etc/nftables.conf
        nft -f /etc/nftables.conf
        systemctl enable --now nftables >/dev/null 2>&1 || true

        if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker; then
          systemctl restart docker
        fi

        # **The same reason as the docker restart above, for the same flush.**
        # `flush ruleset` erases EVERY table, and CrowdSec's bans live in a
        # table of their own (`ip crowdsec` / `ip6 crowdsec6`, written by the
        # firewall bouncer). The bouncer does not notice: its unit stays
        # active, `cscli decisions list` keeps answering, and not one of those
        # decisions is in the packet filter any more. 20 live decisions, no crowdsec table, silent journal —
        # which is strictly worse than having no bouncer, because the dashboard
        # goes on reporting a defended host. Restarting it re-creates the
        # tables and re-applies what the engine holds.
        if systemctl is-active --quiet crowdsec-firewall-bouncer 2>/dev/null; then
          systemctl restart crowdsec-firewall-bouncer >/dev/null 2>&1 || true
        fi
        """.trimIndent()
        .embedding("FIREWALL" to writeFile("/etc/nftables.conf", ruleset, "EOF_NFT"))
}
