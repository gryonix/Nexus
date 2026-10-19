import gryonixNexusCore
import ServiceCatalog

enum PortPreflightSections {
    struct Wanted {
        let port: PublishedHostPort
        let project: String
        let displayName: String
    }

    static func wanted(_ context: MailContext) -> [Wanted] {
        var seen: Set<String> = []
        return context.allSelectedServices.flatMap { service -> [Wanted] in
            guard case .docker(let project) = service.runtime else { return [] }
            return service.publishedHostPorts(context.serviceContext).compactMap { port in
                guard seen.insert("\(project)|\(port.address)|\(port.label)").inserted else { return nil }
                return Wanted(port: port, project: project, displayName: service.displayName)
            }
        }
    }

    static func verifyArgument(_ service: any ManagedService, context: MailContext) -> String {
        service.publishedHostPorts(context.serviceContext)
            .map { "\($0.address):\($0.port)/\($0.proto.rawValue)" }
            .joined(separator: " ")
    }

    /// How long `gd_pp_settled` watches, and how often
    static let settleTries = 12
    static let settleIntervalSeconds = 5
    static let settleQuietSamples = 3

    static func section(_ context: MailContext) -> String? {
        let entries = wanted(context)
        guard !entries.isEmpty else { return nil }
        let language = context.language
        let table = entries
            .map { "\($0.port.address)|\($0.port.port)|\($0.port.proto.rawValue)|\($0.project)|\($0.displayName)" }
            .joined(separator: "\n")
        return #"""
        log "\#(L10nScripts.portPreflightLog(language))"
        # Which ports this host already holds, and who holds them, before
        # anything is created. Without this the answer arrives from docker at
        # `up -d`, after directories, secrets and image pulls — and only for
        # the container that lost: the rest of the run continues and waits for
        # a port that will never open.
        #
        # The tables are read straight out of /proc rather than through `ss`:
        # `ss` is not installed on every image, this section runs BEFORE the
        # package step on purpose, and a WireGuard interface is a kernel socket
        # with no process behind it — it appears in /proc/net/udp and in no
        # process listing at all. The path is a variable so the check can be
        # exercised against captured tables, the same way the distribution
        # check is.
        gd_proc_net="${GRYONIXNEXUS_PROC_NET:-/proc/net}"

        # `<hexaddr>|<hexport>` per holder. TCP counts only in LISTEN (0A) — an
        # established socket owns its own pair, not the port. UDP counts only
        # when unconnected (remote port 0000), so an in-flight outbound flow
        # that happened to pick one of these numbers is not called a listener.
        gd_pp_rows() {
          [ -r "$1" ] || return 0
          awk -v proto="$2" 'FNR>1 {
                if (proto == "tcp") { if ($4 != "0A") next }
                else { split($3, r, ":"); if (r[2] != "0000") next }
                split($2, l, ":"); print l[1] "|" l[2]
              }' "$1"
        }

        # /proc/net writes IPv4 as little-endian hex; `00000000` is the
        # wildcard. An IPv6 row counts only when it IS the wildcard: a specific
        # v6 address cannot collide with the v4 mappings this catalog
        # publishes, and guessing about dual-stack sockets would make the check
        # red on healthy hosts.
        gd_pp_addr() {
          case "${#1}" in
            8)
              if [ "$1" = "00000000" ]; then printf '0.0.0.0'; return 0; fi
              printf '%d.%d.%d.%d' "$((16#${1:6:2}))" "$((16#${1:4:2}))" "$((16#${1:2:2}))" "$((16#${1:0:2}))"
              ;;
            32)
              case "$1" in
                *[!0]*) printf 'skip' ;;
                *)      printf '0.0.0.0' ;;
              esac
              ;;
            *) printf 'skip' ;;
          esac
        }

        GD_PP_HELD_TCP=""
        GD_PP_HELD_UDP=""
        for gd_pp_proto in tcp udp; do
          for gd_pp_row in $(gd_pp_rows "$gd_proc_net/$gd_pp_proto" "$gd_pp_proto"; \
                             gd_pp_rows "$gd_proc_net/${gd_pp_proto}6" "$gd_pp_proto"); do
            gd_pp_a="$(gd_pp_addr "${gd_pp_row%%|*}")"
            if [ "$gd_pp_a" = skip ]; then continue; fi
            gd_pp_entry=" $gd_pp_a:$((16#${gd_pp_row##*|})) "
            if [ "$gd_pp_proto" = tcp ]; then
              GD_PP_HELD_TCP="$GD_PP_HELD_TCP$gd_pp_entry"
            else
              GD_PP_HELD_UDP="$GD_PP_HELD_UDP$gd_pp_entry"
            fi
          done
        done

        # What docker published, per compose project — the only holder this
        # host can NAME. On a machine that has no docker yet there is nothing
        # to ask, and a binding with no name is still a conflict; it just gets
        # described instead of blamed on a container.
        GD_PP_DOCKER=""
        if command -v docker >/dev/null 2>&1; then
          GD_PP_DOCKER="$(docker ps --format '{{.Label "com.docker.compose.project"}}|{{.Names}}|{{.Ports}}' 2>/dev/null || true)"
        fi

        # `<project>|<container>` of whoever published this port, or nothing.
        # Only mappings with `->` are published on the host; a bare `443/tcp`
        # is merely EXPOSED by the image and holds nothing.
        gd_pp_docker_holder() {
          printf '%s\n' "$GD_PP_DOCKER" | awk -F'|' -v want_port="$1" -v want_proto="$2" '
            NF >= 3 {
              n = split($3, maps, ",")
              for (i = 1; i <= n; i++) {
                m = maps[i]; gsub(/^[ \t]+|[ \t]+$/, "", m)
                if (m !~ /->/) continue
                split(m, sides, "->")
                host = sides[1]; container = sides[2]
                proto = (container ~ /\/udp$/) ? "udp" : "tcp"
                if (proto != want_proto) continue
                # The number after the LAST colon, so the colons inside an
                # IPv6 literal cannot confuse it. No apostrophe may appear in
                # this comment: the awk program is one single-quoted shell
                # word, and an apostrophe ends it — shellcheck over the dumped
                # artifacts is what caught that.
                k = split(host, hp, ":")
                if (hp[k] != want_port) continue
                print $1 "|" $2
                exit
              }
            }'
        }

        # Is this mapping already bound? **The address half decides.** Every
        # Debian/Ubuntu host answers DNS on 127.0.0.53:53 and 127.0.0.54:53
        # (systemd-resolved), while the filters in this catalog publish
        # 127.0.0.1:53 — a check that compared port numbers alone would refuse
        # to install on every healthy machine in the fleet. Two different
        # specific addresses coexist; a wildcard on either side collides with
        # anything.
        gd_pp_bound() {
          case "$3" in
            *" $1:$2 "*)       return 0 ;;
            *" 0.0.0.0:$2 "*)  return 0 ;;
          esac
          if [ "$1" = "0.0.0.0" ]; then
            case "$3" in *":$2 "*) return 0 ;; esac
          fi
          return 1
        }

        GD_PP_CONFLICTS=""
        while IFS='|' read -r GD_PP_ADDR GD_PP_PORT GD_PP_PROTO GD_PP_PROJECT GD_PP_NAME; do
          [ -n "${GD_PP_PORT:-}" ] || continue
          GD_PP_HOLDER="$(gd_pp_docker_holder "$GD_PP_PORT" "$GD_PP_PROTO")"
          # Our own container holding the port is what a re-install looks like
          # from here, and it is not a conflict. The project name comes from
          # docker's own label, never from a name derived from the request.
          if [ -n "$GD_PP_HOLDER" ] && [ "${GD_PP_HOLDER%%|*}" = "$GD_PP_PROJECT" ]; then continue; fi
          if [ "$GD_PP_PROTO" = tcp ]; then GD_PP_HELD="$GD_PP_HELD_TCP"; else GD_PP_HELD="$GD_PP_HELD_UDP"; fi
          if [ -z "$GD_PP_HOLDER" ] && ! gd_pp_bound "$GD_PP_ADDR" "$GD_PP_PORT" "$GD_PP_HELD"; then continue; fi
          if [ -n "$GD_PP_HOLDER" ]; then
            GD_PP_LINE="\#(L10nScripts.portHeldByContainer(language, service: "$GD_PP_NAME", port: "$GD_PP_PORT/$GD_PP_PROTO", container: "${GD_PP_HOLDER##*|}", project: "${GD_PP_HOLDER%%|*}"))"
          else
            GD_PP_LINE="\#(L10nScripts.portHeldByUnknown(language, service: "$GD_PP_NAME", port: "$GD_PP_PORT/$GD_PP_PROTO"))"
          fi
          GD_PP_CONFLICTS="$GD_PP_CONFLICTS
          $GD_PP_LINE"
        done <<'EOF_GD_PORTS'
        \#(table)
        EOF_GD_PORTS

        if [ -n "$GD_PP_CONFLICTS" ]; then
          echo "\#(SetupMarkers.portsInUse)"
          fail "\#(L10nScripts.portsInUseFail(language, conflicts: "$GD_PP_CONFLICTS"))"
        fi

        # Did the container that just came up actually GET its ports?
        #
        # **`docker compose up -d` answers 0 for a container that is already
        # running without them.** The
        # first run died when `up -d` could not bind 127.0.0.1:53; the firewall
        # section of the next run restarted docker, the daemon brought that
        # container back up with NO published ports at all, and the re-run's
        # `up -d` then found it running, changed nothing and reported success.
        # Everything after that — the readiness wait, the Caddy site, the
        # credentials in the report — was about a service that did not exist.
        #
        # A few tries rather than one: `docker ps` right after `up -d` can
        # still be a moment behind, and a false "the ports are missing" would
        # abort a healthy install, which is the more expensive way to be wrong.
        gd_pp_verify() {
          gd_v_project="$1"; gd_v_wanted="$2"; gd_v_name="$3"
          gd_v_try=0
          while [ "$gd_v_try" -lt 5 ]; do
            gd_v_live="$(docker ps --filter "label=com.docker.compose.project=$gd_v_project" --format '{{.Ports}}' 2>/dev/null || true)"
            gd_v_missing=""
            for gd_v_map in $gd_v_wanted; do
              gd_v_proto="${gd_v_map##*/}"
              gd_v_port="${gd_v_map%/*}"; gd_v_port="${gd_v_port##*:}"
              case "$gd_v_live" in
                *":$gd_v_port->"*"/$gd_v_proto"*) ;;
                *) gd_v_missing="$gd_v_missing $gd_v_port/$gd_v_proto" ;;
              esac
            done
            [ -n "$gd_v_missing" ] || return 0
            gd_v_missing="${gd_v_missing# }"
            gd_v_try=$((gd_v_try + 1))
            sleep 2
          done
          fail "\#(L10nScripts.portsNotPublishedFail(language, service: "$gd_v_name", ports: "$gd_v_missing"))"
        }

        # The other way a started service is no service: it holds its ports
        # and keeps dying.
        #
        # The question asked is "did it ever HOLD STILL", not "is it restarting
        # right now". The second was tried first and has a blind spot big enough
        # to drive the original defect through: a container that runs four
        # seconds and dies, for ever, reads `running` on almost every sample,
        # because running is most of its cycle. What it never does is stop
        # moving. The passing condition is therefore something OBSERVED — a
        # watch that ends without having seen the service hold still has not
        # seen it work.
        #
        # A healthy service pays one floor's worth: three quiet looks and it is
        # released, so the ordinary cost is fifteen seconds rather than the whole
        # window. Immich is the case this must not fail — its server restarts
        # once while the database initialises and then holds, which is quiet well
        # inside the window.
        gd_pp_settled() {
          gd_s_project="$1"; gd_s_name="$2"
          gd_s_ids="$(docker ps -aq --filter "label=com.docker.compose.project=$gd_s_project" 2>/dev/null || true)"
          [ -n "$gd_s_ids" ] || return 0
          gd_s_base=""
          gd_s_quiet=0
          gd_s_try=0
          while [ "$gd_s_try" -lt \#(settleTries) ]; do
            # shellcheck disable=SC2086
            gd_s_now="$(docker inspect --format '{{.Name}} {{.RestartCount}} {{.State.Status}}' $gd_s_ids 2>/dev/null || true)"
            case "$gd_s_now" in
              *" restarting"*) gd_s_moving=1 ;;
              "") gd_s_moving=1 ;;
              *) gd_s_moving=0 ;;
            esac
            if [ "$gd_s_moving" = "0" ] && [ "$gd_s_now" = "$gd_s_base" ]; then
              gd_s_quiet=$((gd_s_quiet + 1))
              [ "$gd_s_quiet" -lt \#(settleQuietSamples) ] || return 0
            else
              gd_s_base="$gd_s_now"
              gd_s_quiet=0
            fi
            gd_s_try=$((gd_s_try + 1))
            sleep \#(settleIntervalSeconds)
          done
          fail "\#(L10nScripts.serviceCrashLoopFail(language, service: "$gd_s_name", seconds: settleTries * settleIntervalSeconds))"
        }
        """#
    }
}
