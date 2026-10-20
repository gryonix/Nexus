package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.BackupSpec
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.embedding

internal object UpdateControlSections {
    const val HEALTHY_SETTLE_SAMPLES = 3

    const val SCRIPT_PATH = "/opt/gryonixnexus-update-ctl.sh"
    const val DONE_MARKER = "GRYONIXNEXUS_UPDATE_CTL_DONE"

    /** One line per image that moved: `<marker> <service> <image>` */
    const val AVAILABLE_MARKER = "GRYONIXNEXUS_UPDATE_AVAILABLE"

    const val CURRENT_MARKER = "GRYONIXNEXUS_UPDATE_CURRENT"

    const val UNKNOWN_MARKER = "GRYONIXNEXUS_UPDATE_UNKNOWN"

    /** `<marker> <service>` after a successful update */
    const val UPDATED_MARKER = "GRYONIXNEXUS_UPDATE_DONE"

    const val ROLLED_BACK_MARKER = "GRYONIXNEXUS_UPDATE_ROLLED_BACK"

    const val FAILED_MARKER = "GRYONIXNEXUS_UPDATE_FAILED"

    const val CONFIG_DIRECTORY = BackupControlSections.CONFIG_DIRECTORY

    const val CONFIG_PATH = "$CONFIG_DIRECTORY/autoupdate.conf"

    const val STATUS_PATH = "/var/lib/gryonixnexus/autoupdate-status.txt"

    const val TIMER_NAME = "gryonixnexus-autoupdate.timer"
    const val SERVICE_NAME = "gryonixnexus-autoupdate.service"

    /** The argument the timer passes */
    const val SCHEDULED_FLAG = "--scheduled"

    /** Removal of everything this section installs, for the uninstall wrapper */
    fun uninstallLines(indent: String): List<String> = listOf(
        "$indent# Scheduled updates: the timer is armed by set-schedule, not by",
        "$indent# setup, so it outlives the services unless it is stopped here.",
        "${indent}systemctl disable --now '$TIMER_NAME' >/dev/null 2>&1 || true",
        "${indent}rm -f /etc/systemd/system/$TIMER_NAME /etc/systemd/system/$SERVICE_NAME",
        "${indent}rm -f '$CONFIG_PATH' '$STATUS_PATH'",
        "${indent}rm -f '$SCRIPT_PATH'"
    )

    /** One service this wrapper can update */
    private data class Target(
        val id: String,
        val project: String,
        /** Directory holding the compose file */
        val directory: String,
        /** Which arm of the BACKUP wrapper to run first */
        val backupTarget: String,
        val images: List<String>
    )

    private fun plan(services: List<ManagedService>,
                     context: ServiceContext): Pair<List<Target>, List<String>> {
        val targets = mutableListOf<Target>()
        val selfManaged = mutableListOf<String>()
        for (service in services) {
            val spec = service.updateSpec(context)
            when (spec.flavour) {
                UpdateSpec.Flavour.OWN_UPDATER -> selfManaged.add(service.id.rawValue)
                UpdateSpec.Flavour.BUILT_ON_SERVER -> continue
                UpdateSpec.Flavour.COMPOSE_PULL -> {
                    val project = (service.runtime as? ServiceRuntime.Docker)?.composeProject
                        ?: continue
                    val directory = service.composeFile(context)?.directory ?: continue
                    if (spec.images.isEmpty()) continue
                    val backupTarget = when (val backup = service.actions(context).backup) {
                        is BackupSpec.WrapperScript -> backup.spec.wrapperTarget
                        is BackupSpec.EncryptedVolume -> service.id.rawValue
                        null -> ""
                    }
                    targets.add(Target(id = service.id.rawValue, project = project,
                                       directory = directory, backupTarget = backupTarget,
                                       images = spec.images))
                }
            }
        }
        return targets to selfManaged
    }

    /** True when this deployment has anything to update — i.e */
    fun isUsed(services: List<ManagedService>, context: ServiceContext): Boolean =
        plan(services, context).first.isNotEmpty()

    /** The wrapper */
    fun wrapper(services: List<ManagedService>, context: ServiceContext,
                language: AppLanguage): String {
        val (targets, selfManaged) = plan(services, context)
        val knownIDs = targets.joinToString(" ") { it.id }
        val selfManagedIDs = selfManaged.joinToString(" ")
        val serviceArms = targets.joinToString("\n") { target ->
            "    ${target.id}) PROJECT='${target.project}'; DIR='${target.directory}'; " +
                "BACKUP_TARGET='${target.backupTarget}'; " +
                "IMAGES='${target.images.joinToString(" ")}' ;;"
        }

        val script = """
        #!/bin/bash
        # Managed by gryonixNexus — update housekeeping for the Server Dashboard.
        # Usage: gryonixnexus-update-ctl.sh check <service|--all>
        #        gryonixnexus-update-ctl.sh run <service|$SCHEDULED_FLAG>
        #        gryonixnexus-update-ctl.sh set-schedule ${ScheduleSections.GRAMMAR} [services...]
        #        gryonixnexus-update-ctl.sh status
        set -euo pipefail

        ACTION="${SH}{1:-}"
        CONFIG='$CONFIG_PATH'
        STATUS_FILE='$STATUS_PATH'
        # The one thing that makes a backup on this host. An update takes one
        # BEFORE it changes anything, and it calls this rather than carrying its
        # own copy of tar/pg_dump/gpg — the whole reason that wrapper exists.
        BACKUP_CTL='${BackupControlSections.SCRIPT_PATH}'
        # Every service this wrapper can update. Baked in; the config below may
        # only ever be a subset of it.
        KNOWN='$knownIDs'
        # Services that ship their own updater (mailcow's update.sh, GitLab's
        # omnibus, which migrates and reconfigures itself on start). Named so
        # the refusal can say WHY instead of "unsupported service" — swapping
        # their images on a schedule breaks an installation rather than
        # updating it, and their own updater is the app's per-service Update
        # button.
        SELF_MANAGED='$selfManagedIDs'
        # What the schedule covers. Empty until set-schedule writes the config:
        # a run that found no configuration must update NOTHING, never
        # everything.
        SERVICES=''
        SCHEDULE=off

        # How long a service gets to come back up after its images changed
        # before the update is called failed and rolled back. Overridable only
        # from the environment of a root caller — sudo resets the environment,
        # so this is not a way for the app to widen anything; it exists so the
        # test harness does not have to wait five minutes.
        HEALTH_TIMEOUT="${SH}{GRYONIXNEXUS_UPDATE_HEALTH_TIMEOUT:-300}"
        # Per-request budget for a registry. A slow registry is a normal
        # condition, not a fault: it ends as UNKNOWN, never as a failed run.
        HTTP_TIMEOUT="${SH}{GRYONIXNEXUS_UPDATE_HTTP_TIMEOUT:-20}"
        # Both list and single-manifest media types, in both the OCI and the
        # Docker spelling: a multi-arch tag resolves to an INDEX, and asking
        # without these gets either a 404 or the digest of one architecture —
        # which would read as "moved" on every check.
        ACCEPT_HEADER='Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'

        # Filled by gd_load_service from the table below, never from an argument.
        PROJECT=''
        DIR=''
        BACKUP_TARGET=''
        IMAGES=''

        load_config() {
          # shellcheck disable=SC1090
          [ -f "${SH}CONFIG" ] && . "${SH}CONFIG"
          # A config from an older build may not set every value.
          : "${SH}{SCHEDULE:=off}" "${SH}{SERVICES:=}"
        }

        # --- per-service locking (see LockSections) --------------------------

        @LOCK_HELPER@

        # --- arguments -------------------------------------------------------

        # A service label and nothing else. This script is whitelisted in
        # sudoers with no arguments pinned, which is only acceptable because it
        # validates its own input: an unchecked argument that reaches docker
        # here is an argument that reached root.
        gd_valid_label() {
          case "${SH}{1:-}" in
            ''|*[!a-z0-9-]*) echo "invalid service: ${SH}{1:-}" >&2; return 2 ;;
          esac
          return 0
        }

        # The table. Everything an update needs comes from HERE — the caller's
        # bytes only choose an arm, they are never spliced into a command.
        gd_load_service() {
          case "${SH}1" in
        @SERVICE_ARMS@
            *) echo "unsupported service: ${SH}{1}" >&2; return 2 ;;
          esac
        }

        gd_is_self_managed() {
          local known
          for known in ${SH}SELF_MANAGED; do
            if [ "${SH}1" = "${SH}known" ]; then return 0; fi
          done
          return 1
        }

        # Deliberately NOT a marker: what these run is decided by their own
        # updater at run time, so this wrapper has no standing to call them
        # current, available or unknown. A line of prose is what a person
        # reading the log gets; the app's parser ignores it.
        gd_self_managed_note() {
          printf '%s: updated by its own updater, not by this wrapper\n' "${SH}1"
        }

        # --- the registry ----------------------------------------------------

        # The digest `docker pull` recorded for THIS reference — not the image
        # id, which is a local content address with no counterpart in a
        # registry. Empty when the host has never pulled it.
        gd_local_digest() {
          local ref="${SH}1" name="${SH}{1%:*}"
          # Docker records Docker Hub images by their short name
          name="${SH}{name#docker.io/}"; name="${SH}{name#library/}"
          # Guarded as a whole: `head` closes the pipe early, and a SIGPIPE'd
          # `docker` would fail the run under pipefail.
          { docker image inspect "${SH}ref" --format '{{range .RepoDigests}}{{println .}}{{end}}' 2>/dev/null \
              | grep -F "${SH}name@" | head -n 1 | sed 's/.*@//'; } || true
        }

        # One HEAD against a registry. Never `curl -f`: it throws the body and
        # the status away, and here the RESPONSE is the answer — a 401 carries
        # the challenge that names the token endpoint. Never fatal either.
        gd_registry_head() {
          if [ -n "${SH}2" ]; then
            curl -sS -I --max-time "${SH}HTTP_TIMEOUT" -D - -o /dev/null \
              -H "${SH}ACCEPT_HEADER" -H "Authorization: Bearer ${SH}2" "${SH}1" 2>/dev/null || true
          else
            curl -sS -I --max-time "${SH}HTTP_TIMEOUT" -D - -o /dev/null \
              -H "${SH}ACCEPT_HEADER" "${SH}1" 2>/dev/null || true
          fi
        }

        # `key="value"` out of a WWW-Authenticate challenge.
        gd_challenge_field() {
          printf '%s' "${SH}1" | sed -n "s/.*${SH}2=\"\([^\"]*\)\".*/\1/p" | head -n 1
        }

        gd_status_code() {
          printf '%s\n' "${SH}1" | awk 'toupper(${SH}1) ~ /^HTTP/ {c=${SH}2} END {print c}'
        }

        # An anonymous pull token. Parsed with sed rather than jq: jq is not a
        # dependency of this script, and its absence would turn every check on
        # the host into UNKNOWN. The pattern also matches "access_token", which
        # is the same value wherever both are sent.
        gd_registry_token() {
          local body=""
          body="${SH}(curl -sS --max-time "${SH}HTTP_TIMEOUT" --get \
                    --data-urlencode "service=${SH}2" --data-urlencode "scope=${SH}3" "${SH}1" 2>/dev/null)" || true
          printf '%s' "${SH}body" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p' | head -n 1
        }

        # What the tag resolves to in its own registry, right now. Empty when
        # the question could not be answered — the caller turns that into
        # UNKNOWN, never into "up to date".
        gd_remote_digest() {
          local ref="${SH}1" host repo tag url response code challenge realm service scope token digest
          # A reference pinned by digest cannot move: it already IS what it
          # resolves to, and there is nothing to ask anyone.
          case "${SH}ref" in
            *@sha256:*) printf '%s' "${SH}{ref##*@}"; return 0 ;;
          esac
          case "${SH}ref" in
            */*)
              host="${SH}{ref%%/*}"
              case "${SH}host" in
                # A first component with a dot or a port is a registry host;
                # anything else is a Docker Hub namespace (`adguard/…`).
                *.*|*:*|localhost) repo="${SH}{ref#*/}" ;;
                *) host='registry-1.docker.io'; repo="${SH}ref" ;;
              esac
              ;;
            *) host='registry-1.docker.io'; repo="library/${SH}ref" ;;
          esac
          case "${SH}host" in
            docker.io|index.docker.io) host='registry-1.docker.io' ;;
          esac
          case "${SH}repo" in
            *:*) tag="${SH}{repo##*:}"; repo="${SH}{repo%:*}" ;;
            *) tag='latest' ;;
          esac
          url="https://${SH}host/v2/${SH}repo/manifests/${SH}tag"
          response="${SH}(gd_registry_head "${SH}url" '')"
          code="${SH}(gd_status_code "${SH}response")"
          if [ "${SH}code" = "401" ]; then
            challenge="${SH}({ printf '%s\n' "${SH}response" | grep -i '^www-authenticate:' | head -n 1 | tr -d '\r'; } || true)"
            realm="${SH}(gd_challenge_field "${SH}challenge" realm)"
            service="${SH}(gd_challenge_field "${SH}challenge" service)"
            scope="${SH}(gd_challenge_field "${SH}challenge" scope)"
            [ -n "${SH}scope" ] || scope="repository:${SH}repo:pull"
            [ -n "${SH}realm" ] || return 1
            token="${SH}(gd_registry_token "${SH}realm" "${SH}service" "${SH}scope")"
            [ -n "${SH}token" ] || return 1
            response="${SH}(gd_registry_head "${SH}url" "${SH}token")"
            code="${SH}(gd_status_code "${SH}response")"
          fi
          [ "${SH}code" = "200" ] || return 1
          digest="${SH}({ printf '%s\n' "${SH}response" | grep -i '^docker-content-digest:' \
                        | head -n 1 | tr -d '\r' | awk '{print ${SH}2}'; } || true)"
          [ -n "${SH}digest" ] || return 1
          printf '%s' "${SH}digest"
        }

        # --- the check -------------------------------------------------------

        gd_check_service() {
          local svc="${SH}1" moved=0 unknown='' img local_digest remote_digest
          gd_load_service "${SH}svc" || return 2
          for img in ${SH}IMAGES; do
            local_digest="${SH}(gd_local_digest "${SH}img")"
            if [ -z "${SH}local_digest" ]; then
              # The host is not running this image at all, so there is nothing
              # to compare. Saying "up to date" here would be a guess.
              unknown=not_pulled
              continue
            fi
            remote_digest="${SH}(gd_remote_digest "${SH}img")" || remote_digest=''
            if [ -z "${SH}remote_digest" ]; then
              unknown=registry_unreachable
              continue
            fi
            if [ "${SH}local_digest" != "${SH}remote_digest" ]; then
              printf '%s %s %s\n' '$AVAILABLE_MARKER' "${SH}svc" "${SH}img"
              moved=1
            fi
          done
          # Order matters: an unanswered image outranks "nothing moved", so a
          # partial answer can never be printed as CURRENT. An image that DID
          # move is reported either way — the app already prefers it.
          if [ -n "${SH}unknown" ]; then
            printf '%s %s %s\n' '$UNKNOWN_MARKER' "${SH}svc" "${SH}unknown"
          elif [ "${SH}moved" -eq 0 ]; then
            printf '%s %s\n' '$CURRENT_MARKER' "${SH}svc"
          fi
        }

        # True only when every image is known and none has moved. Unknown
        # answers count as "maybe moved", so a scheduled run still goes ahead.
        gd_is_current() {
          local svc="${SH}1" img local_digest remote_digest
          gd_load_service "${SH}svc" || return 1
          [ -n "${SH}IMAGES" ] || return 1
          for img in ${SH}IMAGES; do
            local_digest="${SH}(gd_local_digest "${SH}img")"
            [ -n "${SH}local_digest" ] || return 1
            remote_digest="${SH}(gd_remote_digest "${SH}img")" || remote_digest=''
            [ "${SH}local_digest" = "${SH}remote_digest" ] || return 1
          done
          return 0
        }

        do_check() {
          local target="${SH}{1:---all}" svc
          if ! command -v docker >/dev/null 2>&1; then
            # No docker means no local digests, i.e. no answer for anything.
            for svc in ${SH}KNOWN; do
              printf '%s %s %s\n' '$UNKNOWN_MARKER' "${SH}svc" 'docker_unavailable'
            done
            return 0
          fi
          if [ "${SH}target" = "--all" ]; then
            for svc in ${SH}KNOWN; do gd_check_service "${SH}svc"; done
            for svc in ${SH}SELF_MANAGED; do gd_self_managed_note "${SH}svc"; done
            return 0
          fi
          gd_valid_label "${SH}target" || exit 2
          if gd_is_self_managed "${SH}target"; then gd_self_managed_note "${SH}target"; return 0; fi
          gd_check_service "${SH}target" || exit 2
        }

        # --- applying one ----------------------------------------------------

        gd_image_id() {
          { docker image inspect "${SH}1" --format '{{.Id}}' 2>/dev/null | head -n 1; } || true
        }

        # Puts every tag back on the image it pointed at before the pull.
        # `docker pull` does not delete what it replaced — it only moves the
        # tag — so this needs no registry and works with the network down,
        # which is exactly the state a failed update can leave a host in.
        gd_restore_images() {
          local img old now
          while read -r img old; do
            if [ -z "${SH}old" ]; then
              echo "no previous image to put back for ${SH}img" >&2
              continue
            fi
            now="${SH}(gd_image_id "${SH}img")"
            if [ "${SH}now" = "${SH}old" ]; then continue; fi
            docker tag "${SH}old" "${SH}img" >/dev/null 2>&1 || echo "could not put ${SH}img back" >&2
          done < "${SH}1"
        }

        # Waits for every container of the project to be up, and prints WHY it
        # is not when the deadline passes. Progress goes to stderr so the
        # reason stays the only thing on stdout.
        # **One clean look is not health.** A wait that accepted its
        # first clean look therefore called a broken update good and never rolled
        # back. That was fixed for container GROUPS in the agent and did not
        # reach here, which is the cost of one rule living in two places.
        #
        # So: clean on $HEALTHY_SETTLE_SAMPLES looks in a row, AND the restart
        # counters unchanged across them — the second catches a loop whose
        # up-windows happen to line up with the polls.
        gd_wait_healthy() {
          local project="${SH}1" deadline now beat ids cid state status restarting exitcode health bad
          local clean=0 counters="" counters_now=""
          now="${SH}(date +%s)"
          deadline=${SH}((now + ${SH}2))
          beat=${SH}((now + 30))
          while : ; do
            bad=''
            ids="${SH}(docker compose -p "${SH}project" ps -q 2>/dev/null || true)"
            if [ -z "${SH}ids" ]; then
              bad='no container is running'
            else
              for cid in ${SH}ids; do
                state="${SH}(docker inspect -f '{{.State.Status}} {{.State.Restarting}} {{.State.ExitCode}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${SH}cid" 2>/dev/null || true)"
                if [ -z "${SH}state" ]; then bad='a container disappeared'; continue; fi
                read -r status restarting exitcode health <<< "${SH}state"
                if [ "${SH}restarting" = "true" ]; then bad='a container is restarting'; continue; fi
                case "${SH}status" in
                  running)
                    case "${SH}health" in
                      unhealthy) bad='a container reports unhealthy' ;;
                      starting) bad='a container is still starting' ;;
                    esac
                    ;;
                  # A one-shot container that finished cleanly is not a fault:
                  # several stacks here run an init container that exits 0.
                  exited)
                    if [ "${SH}exitcode" != "0" ]; then bad="a container exited with ${SH}exitcode"; fi
                    ;;
                  *) bad="a container is ${SH}status" ;;
                esac
              done
            fi
            if [ -z "${SH}bad" ]; then
              # shellcheck disable=SC2086
              counters_now="${SH}(docker inspect -f '{{.Name}} {{.RestartCount}}' ${SH}ids 2>/dev/null || true)"
              if [ "${SH}clean" -eq 0 ] || [ "${SH}counters_now" != "${SH}counters" ]; then
                clean=1
                counters="${SH}counters_now"
              else
                clean=${SH}((clean + 1))
              fi
              if [ "${SH}clean" -ge $HEALTHY_SETTLE_SAMPLES ]; then return 0; fi
              bad='waiting for the containers to hold still'
            else
              clean=0
            fi
            now="${SH}(date +%s)"
            if [ "${SH}now" -ge "${SH}deadline" ]; then printf '%s\n' "${SH}bad"; return 1; fi
            if [ "${SH}now" -ge "${SH}beat" ]; then
              # The app streams this; minutes of silence read as a hung run.
              echo "waiting for ${SH}project: ${SH}bad" >&2
              beat=${SH}((now + 30))
            fi
            sleep 5
          done
        }

        # The entry point both callers go through: the timer's scheduled run
        # and the app's button. Validates and refuses BEFORE taking the lock
        # (an unknown or self-managed id was never going to run at all, so
        # there is nothing to serialise against), then hands off to the
        # locked body below. `gd_with_lock` calls it as a plain function in
        # THIS shell, not a subshell or a fork, so the globals `gd_load_service`
        # just filled (PROJECT/DIR/BACKUP_TARGET/IMAGES) stay visible to it.
        gd_update_service() {
          local svc="${SH}1"
          # Neither refusal below is recorded: both answer a question that was
          # never a run. A scheduled run cannot reach them at all — set-schedule
          # keeps self-managed and unknown ids out of SERVICES — so a record
          # here could only ever describe a button press whose answer the person
          # who pressed it is already reading.
          if gd_is_self_managed "${SH}svc"; then
            echo "${SH}svc ships its own updater, so this wrapper does not swap its images" >&2
            return 2
          fi
          gd_load_service "${SH}svc" || return 2

          local rc=0
          gd_with_lock "update-${SH}svc" gd_update_service_locked "${SH}svc" || rc=${SH}?
          if [ "${SH}rc" -eq "${SH}GD_LOCK_BUSY" ]; then
            # UNLIKE the refusals above, this IS recorded: the service was
            # eligible to run and did not, which is exactly the failure mode
            # `autoupdate-status.txt` exists to catch — a scheduled run that
            # skips silently reads as "nothing happened" to whoever checks
            # back later (see LockSections).
            gd_record "${SH}(printf '%s %s %s' '$FAILED_MARKER' "${SH}svc" \
              'another update for this service was already running')"
          fi
          return "${SH}rc"
        }

        # The ONE body both callers go through, once the lock is held. Two
        # copies of this is the drift the backup wrapper already exists to
        # prevent.
        gd_update_service_locked() {
          local svc="${SH}1" img old work='' reason='' health=''

          # 1. A backup FIRST, through the wrapper that owns backups. A failed
          # backup stops the update: the point of taking one is that the update
          # is the risky part.
          if [ -n "${SH}BACKUP_TARGET" ]; then
            if [ ! -x "${SH}BACKUP_CTL" ]; then
              echo "the backup helper is missing, so ${SH}svc was not updated" >&2
              gd_record "${SH}(printf '%s %s %s' '$FAILED_MARKER' "${SH}svc" 'the backup helper is missing')"
              return 1
            fi
            echo "backing up ${SH}svc before updating it"
            # stdin is /dev/null on purpose. The backup wrapper reads a
            # passphrase from stdin when it encrypts, and an open pipe with
            # nobody writing would park it forever; closed, it falls back to the
            # stored passphrase and refuses if there is none — which is the
            # right answer for an unattended run over a secret store.
            if ! "${SH}BACKUP_CTL" backup "${SH}BACKUP_TARGET" < /dev/null; then
              echo "the backup of ${SH}svc failed, so the update was not applied" >&2
              gd_record "${SH}(printf '%s %s %s' '$FAILED_MARKER' "${SH}svc" 'the backup failed')"
              return 1
            fi
          else
            echo "${SH}svc declares no backup, so none was taken before this update"
          fi

          # 2. What a rollback would return to. Readable only now: after the
          # pull the tag points somewhere else.
          work="${SH}(mktemp -d)"
          : > "${SH}work/before"
          for img in ${SH}IMAGES; do
            old="${SH}(gd_image_id "${SH}img")"
            printf '%s %s\n' "${SH}img" "${SH}old" >> "${SH}work/before"
          done

          # 3. Pull, then restart. `cd` because pull and up need the compose
          # FILE (ps finds the project by label, these do not).
          if ! ( cd "${SH}DIR" && docker compose -p "${SH}PROJECT" pull ); then
            # Nothing was restarted, so the service is still the one that was
            # running — but a partial pull may have moved a tag, and the next
            # `up` anywhere would then apply it silently.
            gd_restore_images "${SH}work/before"
            rm -rf "${SH}work"
            echo "could not pull the new images for ${SH}svc" >&2
            gd_record "${SH}(printf '%s %s %s' '$FAILED_MARKER' "${SH}svc" 'could not pull the new images')"
            return 1
          fi
          if ! ( cd "${SH}DIR" && docker compose -p "${SH}PROJECT" up -d ); then
            reason=did_not_start
          else
            if ! health="${SH}(gd_wait_healthy "${SH}PROJECT" "${SH}HEALTH_TIMEOUT")"; then
              reason="${SH}{health:-unhealthy}"
            fi
          fi

          # 4. Roll back to the images the host was already running.
          if [ -n "${SH}reason" ]; then
            gd_restore_images "${SH}work/before"
            ( cd "${SH}DIR" && docker compose -p "${SH}PROJECT" up -d ) || true
            rm -rf "${SH}work"
            gd_record "${SH}(printf '%s %s %s' '$ROLLED_BACK_MARKER' "${SH}svc" "${SH}reason")"
            return 1
          fi
          rm -rf "${SH}work"
          gd_record "${SH}(printf '%s %s' '$UPDATED_MARKER' "${SH}svc")"
        }

        # --- the record ------------------------------------------------------

        # Printed AND kept. The print is for the app streaming this run; the
        # copy is for the app that was closed when the timer fired.
        gd_record() {
          printf '%s\n' "${SH}1"
          install -d -m 755 "${SH}(dirname "${SH}STATUS_FILE")" 2>/dev/null || true
          printf '%s\n' "${SH}1" >> "${SH}STATUS_FILE" 2>/dev/null || true
          # Bounded: manual runs append here too and nothing else prunes it.
          { tail -n 200 "${SH}STATUS_FILE" > "${SH}STATUS_FILE.tmp" && mv "${SH}STATUS_FILE.tmp" "${SH}STATUS_FILE"; } 2>/dev/null || true
          chmod 644 "${SH}STATUS_FILE" 2>/dev/null || true
        }

        do_status() {
          # Read-only, and missing is not an error: a server that has never run
          # an update has nothing to report, which is not the same as broken.
          { cat "${SH}STATUS_FILE" 2>/dev/null; } || true
        }

        do_run() {
          local target="${SH}{1:-}" svc failed=''
          if [ "${SH}target" = '$SCHEDULED_FLAG' ]; then
            load_config
            install -d -m 755 "${SH}(dirname "${SH}STATUS_FILE")" 2>/dev/null || true
            printf 'last-run %s\n' "${SH}(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${SH}STATUS_FILE" 2>/dev/null || true
            for svc in ${SH}SERVICES; do
              # Each service in its own subshell, and the `||` keeps errexit
              # from firing: an unattended run must not let one broken service
              # cancel the updates of every service after it.
              # Gone from this host since the schedule was set: nothing to update.
              if ! ( gd_load_service "${SH}svc" ) >/dev/null 2>&1; then
                echo "${SH}svc is no longer on this server, skipped"
                continue
              fi
              # Nothing new: no backup and no pull, so the night's backup stays the only one.
              if ( gd_is_current "${SH}svc" ); then
                echo "${SH}svc is up to date"
                continue
              fi
              ( gd_update_service "${SH}svc" ) || failed="${SH}failed ${SH}svc"
            done
            if [ -n "${SH}failed" ]; then
              echo "the update failed for:${SH}failed" >&2
              exit 1
            fi
            return 0
          fi
          gd_valid_label "${SH}target" || exit 2
          gd_update_service "${SH}target"
        }

        do_set_schedule() {
        @SCHEDULE_COMMENT@
          local schedule="${SH}{1:-off}"
          shift || true
          local services="${SH}*"
        @SCHEDULE_PARSER@
          # Only services this wrapper can actually update may end up in the
          # config — a self-managed one ticked in the app is dropped HERE rather
          # than accepted and skipped later, because the app reads this file
          # back and the switch has to show what the server will really do.
          local checked=""
          for svc in ${SH}services; do
            # Membership tested against the baked-in list itself, so the set of
            # updatable services exists ONCE in this script and cannot disagree
            # with itself. The quotes inside the pattern are what make the
            # comparison literal: a caller sending `*` matches nothing.
            case " ${SH}KNOWN " in
              *" ${SH}svc "*) checked="${SH}checked ${SH}svc" ;;
            esac
          done
          install -d -m 755 "${SH}(dirname "${SH}CONFIG")"
          cat > "${SH}CONFIG" <<EOF_UP_CONF
        SCHEDULE=${SH}schedule
        SERVICES='${SH}{checked# }'
        EOF_UP_CONF
          # World-readable on purpose: it holds no secrets and the app reads it
          # without sudo.
          chmod 644 "${SH}CONFIG"
        @TIMER_ACTIVATION@
        }

        case "${SH}ACTION" in
          check) shift; do_check "${SH}@" ;;
          run) shift; do_run "${SH}@" ;;
          set-schedule) shift; do_set_schedule "${SH}@" ;;
          status) do_status ;;
          *) echo "unsupported action: ${SH}{ACTION}" >&2; exit 2 ;;
        esac
        echo '$DONE_MARKER'
        """.trimIndent().embedding(
            "LOCK_HELPER" to LockSections.helper,
            "SERVICE_ARMS" to serviceArms.ifEmpty {
                "    __none__) ;; # nothing here updates through a pull"
            },
            "SCHEDULE_COMMENT" to ScheduleSections.argumentComment,
            "SCHEDULE_PARSER" to ScheduleSections.parser,
            "TIMER_ACTIVATION" to ScheduleSections.timerActivation(
                timerName = TIMER_NAME,
                description = "gryonixNexus scheduled updates",
                delimiter = "EOF_UP_TIMER"
            )
        )

        val unit = """
        [Unit]
        Description=gryonixNexus scheduled update run
        After=docker.service
        [Service]
        Type=oneshot
        ExecStart=$SCRIPT_PATH run $SCHEDULED_FLAG
        """.trimIndent()

        return """
        log "${L10nScripts.updateControlWrapperLog(language)}"
        @SCRIPT_FILE@
        chmod 750 '$SCRIPT_PATH'
        # 755: the schedule config inside is read by the app without sudo.
        install -d -m 755 $CONFIG_DIRECTORY
        @UNIT_FILE@
        systemctl daemon-reload
        # The timer itself is created only when the user turns the schedule on.
        """.trimIndent().embedding(
            "SCRIPT_FILE" to BashSections.writeFile(SCRIPT_PATH, script, "EOF_UPDATE_CTL"),
            "UNIT_FILE" to BashSections.writeFile(
                "/etc/systemd/system/$SERVICE_NAME", unit, "EOF_AUTOUPDATE_UNIT"
            )
        )
    }
}
