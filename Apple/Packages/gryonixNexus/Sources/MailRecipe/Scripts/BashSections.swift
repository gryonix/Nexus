import gryonixNexusCore
import ServiceCatalog

/// Shared bash sections for setup scripts
enum BashSections {
    static var supportedDistributionIDs: String {
        DistributionProfileID.allCases
            .map { $0.makeProfile().osReleaseID }
            .joined(separator: "|")
    }

    static func header(scriptName: String, purpose: String,
                       profile: any DistributionProfile, language: AppLanguage) -> String {
        #"""
        #!/usr/bin/env bash
        # Managed by gryonixNexus — \#(purpose)
        # \#(SetupMarkers.distribution): \#(profile.osReleaseID)
        # \#(L10nScripts.headerRunLine(language, script: scriptName))
        # \#(L10nScripts.headerSelfContained(language))
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

        log()    { printf '\n==> %s\n' "$*"; }
        fail()   { printf '\#(L10nScripts.errorPrefix(language)): %s\n' "$*" >&2; exit 1; }
        # Copies a changed file aside, keeping the newest five
        backup() {
          [ -f "$1" ] || return 0
          local last
          last="$(ls -1d "$1".bak.* 2>/dev/null | sort | tail -n 1 || true)"
          if [ -n "$last" ] && cmp -s "$1" "$last"; then return 0; fi
          cp -a "$1" "$1.bak.$(date +%s)"
          ls -1d "$1".bak.* | sort | head -n -5 | xargs -r rm -f
        }
        # Retry a flaky command a few times with a linear backoff. Fresh servers
        # pull many large images at once (mailcow alone is ~15), and a single
        # transient registry error/timeout would otherwise abort the whole run
        # under `set -e` — the user then had to hit Retry by hand. The setup is
        # idempotent, so a re-pull just resumes cached layers.
        retry()  {
          local tries="$1"; shift
          local i=1
          while true; do
            "$@" && return 0
            if [ "$i" -ge "$tries" ]; then return 1; fi
            printf '\n(retry %d/%d) %s\n' "$i" "$tries" "$*" >&2
            sleep $((i * 5))
            i=$((i + 1))
          done
        }

        [ "$(id -u)" -eq 0 ] || fail "\#(L10nScripts.rootRequired(language, script: "$0"))"

        # \#(L10nScripts.headerDistributionPinned(language))
        # The path is a variable so the check can be exercised against a stub
        # file — the alternative was a test that runs a doctored copy of this
        # block and proves nothing about the artifact that ships. It is not a
        # privilege boundary: the script already runs as root.
        gd_os_release="${GRYONIXNEXUS_OS_RELEASE:-/etc/os-release}"
        [ -r "$gd_os_release" ] || fail "\#(L10nScripts.osReleaseMissing(language))"
        # shellcheck source=/dev/null
        . "$gd_os_release"
        # A derivative (Devuan, Linux Mint, Pop!_OS, …) names its base in
        # ID_LIKE and behaves like it for apt and systemd, so it is accepted.
        # A distribution we support in its OWN right never passes as another
        # one: Ubuntu lists debian in ID_LIKE, and letting that through would
        # silently install with the wrong profile instead of saying so.
        if [ "${ID:-}" != "\#(profile.osReleaseID)" ]; then
          gd_like_base=0
          for gd_like in ${ID_LIKE:-}; do
            [ "$gd_like" = "\#(profile.osReleaseID)" ] && gd_like_base=1
          done
          case "${ID:-}" in \#(Self.supportedDistributionIDs)) gd_like_base=0 ;; esac
          [ "$gd_like_base" = "1" ] || fail "\#(L10nScripts.wrongDistribution(language, expected: profile.displayName, detected: "${PRETTY_NAME:-${ID:-\(L10nScripts.unknownValue(language))}}"))"
          log "\#(L10nScripts.distributionDerivative(language, detected: "${PRETTY_NAME:-${ID:-\(L10nScripts.unknownValue(language))}}", base: profile.displayName))"
        fi

        export DEBIAN_FRONTEND=noninteractive
        """#
    }

    static func dnsCheck(hostname: String, expectedIP: String, language: AppLanguage) -> String {
        #"""
        if [ "${GRYONIXNEXUS_SKIP_DNS_CHECK:-0}" != "1" ]; then
          log "\#(L10nScripts.dnsCheckLog(language, hostname: hostname, expectedIP: expectedIP))"
          resolved="$(getent ahostsv4 "\#(hostname)" | awk 'NR==1{print $1}')" || resolved=""
          if [ "${resolved:-}" != "\#(expectedIP)" ]; then
            echo "\#(SetupMarkers.dnsCheckFailed)"
            fail "\#(L10nScripts.dnsMismatch(language, hostname: hostname, resolved: "${resolved:-\(L10nScripts.nothingValue(language))}", expectedIP: expectedIP, script: "$0"))"
          fi
        fi
        """#
    }

    /// Non-interactive package install
    static func installPackages(
        _ packages: [String],
        profile: any DistributionProfile,
        language: AppLanguage
    ) -> String {
        [
            "log \"\(L10nScripts.installingPackages(language))\"",
            profile.installCommand(for: packages)
        ].joined(separator: "\n")
    }

    /// Writes a file via heredoc, backing up any existing one
    static func writeFile(path: String, contents: String, delimiter: String) -> String {
        #"""
        backup \#(path)
        cat > \#(path) <<'\#(delimiter)'
        \#(contents)
        \#(delimiter)
        """#
    }

    /// Applies nftables: syntax check before applying, auto-start on boot
    static func applyFirewall(ruleset: String) -> String {
        return #"""
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
        \#(writeFile(path: "/etc/nftables.conf", contents: ruleset, delimiter: "EOF_NFT"))
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
        """#
    }
}
