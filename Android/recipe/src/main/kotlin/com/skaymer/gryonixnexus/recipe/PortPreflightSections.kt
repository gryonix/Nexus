package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.PublishedHostPort
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.embedding
import com.skaymer.gryonixnexus.catalog.publishedHostPorts

internal object PortPreflightSections {
    /** How long `gd_pp_settled` watches, and how often */
    const val SETTLE_TRIES = 12
    const val SETTLE_INTERVAL_SECONDS = 5
    const val SETTLE_QUIET_SAMPLES = 3

    data class Wanted(
        val port: PublishedHostPort,
        val project: String,
        val displayName: String
    )

    fun wanted(context: MailContext): List<Wanted> {
        val seen = mutableSetOf<String>()
        return context.allSelectedServices.flatMap { service ->
            val project = (service.runtime as? ServiceRuntime.Docker)?.composeProject
                ?: return@flatMap emptyList()
            service.publishedHostPorts(context.serviceContext).mapNotNull { port ->
                if (!seen.add("$project|${port.address}|${port.label}")) return@mapNotNull null
                Wanted(port = port, project = project, displayName = service.displayName)
            }
        }
    }

    fun verifyArgument(service: ManagedService, context: MailContext): String =
        service.publishedHostPorts(context.serviceContext)
            .joinToString(" ") { "${it.address}:${it.port}/${it.proto.wireValue}" }

    fun section(context: MailContext): String? {
        val entries = wanted(context)
        if (entries.isEmpty()) return null
        val language = context.language
        val table = entries.joinToString("\n") {
            "${it.port.address}|${it.port.port}|${it.port.proto.wireValue}|${it.project}|${it.displayName}"
        }
        val heldByContainer = L10nScripts.portHeldByContainer(
            language,
            service = "${SH}GD_PP_NAME",
            port = "${SH}GD_PP_PORT/${SH}GD_PP_PROTO",
            container = "${SH}{GD_PP_HOLDER##*|}",
            project = "${SH}{GD_PP_HOLDER%%|*}"
        )
        val heldByUnknown = L10nScripts.portHeldByUnknown(
            language, service = "${SH}GD_PP_NAME", port = "${SH}GD_PP_PORT/${SH}GD_PP_PROTO"
        )
        return """
        log "${L10nScripts.portPreflightLog(language)}"
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
        gd_proc_net="${SH}{GRYONIXNEXUS_PROC_NET:-/proc/net}"

        # `<hexaddr>|<hexport>` per holder. TCP counts only in LISTEN (0A) — an
        # established socket owns its own pair, not the port. UDP counts only
        # when unconnected (remote port 0000), so an in-flight outbound flow
        # that happened to pick one of these numbers is not called a listener.
        gd_pp_rows() {
          [ -r "${SH}1" ] || return 0
          awk -v proto="${SH}2" 'FNR>1 {
                if (proto == "tcp") { if (${SH}4 != "0A") next }
                else { split(${SH}3, r, ":"); if (r[2] != "0000") next }
                split(${SH}2, l, ":"); print l[1] "|" l[2]
              }' "${SH}1"
        }

        # /proc/net writes IPv4 as little-endian hex; `00000000` is the
        # wildcard. An IPv6 row counts only when it IS the wildcard: a specific
        # v6 address cannot collide with the v4 mappings this catalog
        # publishes, and guessing about dual-stack sockets would make the check
        # red on healthy hosts.
        gd_pp_addr() {
          case "${SH}{#1}" in
            8)
              if [ "${SH}1" = "00000000" ]; then printf '0.0.0.0'; return 0; fi
              printf '%d.%d.%d.%d' "${SH}((16#${SH}{1:6:2}))" "${SH}((16#${SH}{1:4:2}))" "${SH}((16#${SH}{1:2:2}))" "${SH}((16#${SH}{1:0:2}))"
              ;;
            32)
              case "${SH}1" in
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
          for gd_pp_row in ${SH}(gd_pp_rows "${SH}gd_proc_net/${SH}gd_pp_proto" "${SH}gd_pp_proto"; \
                             gd_pp_rows "${SH}gd_proc_net/${SH}{gd_pp_proto}6" "${SH}gd_pp_proto"); do
            gd_pp_a="${SH}(gd_pp_addr "${SH}{gd_pp_row%%|*}")"
            if [ "${SH}gd_pp_a" = skip ]; then continue; fi
            gd_pp_entry=" ${SH}gd_pp_a:${SH}((16#${SH}{gd_pp_row##*|})) "
            if [ "${SH}gd_pp_proto" = tcp ]; then
              GD_PP_HELD_TCP="${SH}GD_PP_HELD_TCP${SH}gd_pp_entry"
            else
              GD_PP_HELD_UDP="${SH}GD_PP_HELD_UDP${SH}gd_pp_entry"
            fi
          done
        done

        # What docker published, per compose project — the only holder this
        # host can NAME. On a machine that has no docker yet there is nothing
        # to ask, and a binding with no name is still a conflict; it just gets
        # described instead of blamed on a container.
        GD_PP_DOCKER=""
        if command -v docker >/dev/null 2>&1; then
          GD_PP_DOCKER="${SH}(docker ps --format '{{.Label "com.docker.compose.project"}}|{{.Names}}|{{.Ports}}' 2>/dev/null || true)"
        fi

        # `<project>|<container>` of whoever published this port, or nothing.
        # Only mappings with `->` are published on the host; a bare `443/tcp`
        # is merely EXPOSED by the image and holds nothing.
        gd_pp_docker_holder() {
          printf '%s\n' "${SH}GD_PP_DOCKER" | awk -F'|' -v want_port="${SH}1" -v want_proto="${SH}2" '
            NF >= 3 {
              n = split(${SH}3, maps, ",")
              for (i = 1; i <= n; i++) {
                m = maps[i]; gsub(/^[ \t]+|[ \t]+${SH}/, "", m)
                if (m !~ /->/) continue
                split(m, sides, "->")
                host = sides[1]; container = sides[2]
                proto = (container ~ /\/udp${SH}/) ? "udp" : "tcp"
                if (proto != want_proto) continue
                # The number after the LAST colon, so the colons inside an
                # IPv6 literal cannot confuse it. No apostrophe may appear in
                # this comment: the awk program is one single-quoted shell
                # word, and an apostrophe ends it — shellcheck over the dumped
                # artifacts is what caught that.
                k = split(host, hp, ":")
                if (hp[k] != want_port) continue
                print ${SH}1 "|" ${SH}2
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
          case "${SH}3" in
            *" ${SH}1:${SH}2 "*)       return 0 ;;
            *" 0.0.0.0:${SH}2 "*)  return 0 ;;
          esac
          if [ "${SH}1" = "0.0.0.0" ]; then
            case "${SH}3" in *":${SH}2 "*) return 0 ;; esac
          fi
          return 1
        }

        GD_PP_CONFLICTS=""
        while IFS='|' read -r GD_PP_ADDR GD_PP_PORT GD_PP_PROTO GD_PP_PROJECT GD_PP_NAME; do
          [ -n "${SH}{GD_PP_PORT:-}" ] || continue
          GD_PP_HOLDER="${SH}(gd_pp_docker_holder "${SH}GD_PP_PORT" "${SH}GD_PP_PROTO")"
          # Our own container holding the port is what a re-install looks like
          # from here, and it is not a conflict. The project name comes from
          # docker's own label, never from a name derived from the request.
          if [ -n "${SH}GD_PP_HOLDER" ] && [ "${SH}{GD_PP_HOLDER%%|*}" = "${SH}GD_PP_PROJECT" ]; then continue; fi
          if [ "${SH}GD_PP_PROTO" = tcp ]; then GD_PP_HELD="${SH}GD_PP_HELD_TCP"; else GD_PP_HELD="${SH}GD_PP_HELD_UDP"; fi
          if [ -z "${SH}GD_PP_HOLDER" ] && ! gd_pp_bound "${SH}GD_PP_ADDR" "${SH}GD_PP_PORT" "${SH}GD_PP_HELD"; then continue; fi
          if [ -n "${SH}GD_PP_HOLDER" ]; then
            GD_PP_LINE="${heldByContainer}"
          else
            GD_PP_LINE="${heldByUnknown}"
          fi
          GD_PP_CONFLICTS="${SH}GD_PP_CONFLICTS
          ${SH}GD_PP_LINE"
        done <<'EOF_GD_PORTS'
        @TABLE@
        EOF_GD_PORTS

        if [ -n "${SH}GD_PP_CONFLICTS" ]; then
          echo "${SetupMarkers.PORTS_IN_USE}"
          fail "@PORTS_IN_USE_FAIL@"
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
          gd_v_project="${SH}1"; gd_v_wanted="${SH}2"; gd_v_name="${SH}3"
          gd_v_try=0
          while [ "${SH}gd_v_try" -lt 5 ]; do
            gd_v_live="${SH}(docker ps --filter "label=com.docker.compose.project=${SH}gd_v_project" --format '{{.Ports}}' 2>/dev/null || true)"
            gd_v_missing=""
            for gd_v_map in ${SH}gd_v_wanted; do
              gd_v_proto="${SH}{gd_v_map##*/}"
              gd_v_port="${SH}{gd_v_map%/*}"; gd_v_port="${SH}{gd_v_port##*:}"
              case "${SH}gd_v_live" in
                *":${SH}gd_v_port->"*"/${SH}gd_v_proto"*) ;;
                *) gd_v_missing="${SH}gd_v_missing ${SH}gd_v_port/${SH}gd_v_proto" ;;
              esac
            done
            [ -n "${SH}gd_v_missing" ] || return 0
            gd_v_missing="${SH}{gd_v_missing# }"
            gd_v_try=${SH}((gd_v_try + 1))
            sleep 2
          done
          fail "@PORTS_NOT_PUBLISHED_FAIL@"
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
          gd_s_project="${SH}1"; gd_s_name="${SH}2"
          gd_s_ids="${SH}(docker ps -aq --filter "label=com.docker.compose.project=${SH}gd_s_project" 2>/dev/null || true)"
          [ -n "${SH}gd_s_ids" ] || return 0
          gd_s_base=""
          gd_s_quiet=0
          gd_s_try=0
          while [ "${SH}gd_s_try" -lt $SETTLE_TRIES ]; do
            # shellcheck disable=SC2086
            gd_s_now="${SH}(docker inspect --format '{{.Name}} {{.RestartCount}} {{.State.Status}}' ${SH}gd_s_ids 2>/dev/null || true)"
            case "${SH}gd_s_now" in
              *" restarting"*) gd_s_moving=1 ;;
              "") gd_s_moving=1 ;;
              *) gd_s_moving=0 ;;
            esac
            if [ "${SH}gd_s_moving" = "0" ] && [ "${SH}gd_s_now" = "${SH}gd_s_base" ]; then
              gd_s_quiet=${SH}((gd_s_quiet + 1))
              [ "${SH}gd_s_quiet" -lt $SETTLE_QUIET_SAMPLES ] || return 0
            else
              gd_s_base="${SH}gd_s_now"
              gd_s_quiet=0
            fi
            gd_s_try=${SH}((gd_s_try + 1))
            sleep $SETTLE_INTERVAL_SECONDS
          done
          fail "@SERVICE_CRASH_LOOP_FAIL@"
        }
        """.trimIndent().embedding(
            "TABLE" to table,
            "PORTS_IN_USE_FAIL" to L10nScripts.portsInUseFail(language, conflicts = "${SH}GD_PP_CONFLICTS"),
            "PORTS_NOT_PUBLISHED_FAIL" to L10nScripts.portsNotPublishedFail(
                language, service = "${SH}gd_v_name", ports = "${SH}gd_v_missing"
            ),
            "SERVICE_CRASH_LOOP_FAIL" to L10nScripts.serviceCrashLoopFail(
                language, service = "${SH}gd_s_name",
                seconds = SETTLE_TRIES * SETTLE_INTERVAL_SECONDS
            )
        )
    }
}
