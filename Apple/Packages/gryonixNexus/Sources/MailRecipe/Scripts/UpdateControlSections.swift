import gryonixNexusCore
import ServiceCatalog

enum UpdateControlSections {
    static let healthySettleSamples = 3

    static let scriptPath = "/opt/gryonixnexus-update-ctl.sh"
    static let doneMarker = "GRYONIXNEXUS_UPDATE_CTL_DONE"
    /// One line per image that moved: `<marker> <service> <image>`
    static let availableMarker = "GRYONIXNEXUS_UPDATE_AVAILABLE"
    static let currentMarker = "GRYONIXNEXUS_UPDATE_CURRENT"
    static let unknownMarker = "GRYONIXNEXUS_UPDATE_UNKNOWN"
    /// `<marker> <service>` after a successful update
    static let updatedMarker = "GRYONIXNEXUS_UPDATE_DONE"
    static let rolledBackMarker = "GRYONIXNEXUS_UPDATE_ROLLED_BACK"
    static let failedMarker = "GRYONIXNEXUS_UPDATE_FAILED"

    static let configDirectory = BackupControlSections.configDirectory
    static let configPath = "\(configDirectory)/autoupdate.conf"
    static let statusPath = "/var/lib/gryonixnexus/autoupdate-status.txt"
    static let timerName = "gryonixnexus-autoupdate.timer"
    static let serviceName = "gryonixnexus-autoupdate.service"
    /// The argument the timer passes
    static let scheduledFlag = "--scheduled"

    /// Removal of everything this section installs, for the uninstall wrapper
    static func uninstallLines(indent: String) -> [String] {
        [
            "\(indent)# Scheduled updates: the timer is armed by set-schedule, not by",
            "\(indent)# setup, so it outlives the services unless it is stopped here.",
            "\(indent)systemctl disable --now '\(timerName)' >/dev/null 2>&1 || true",
            "\(indent)rm -f /etc/systemd/system/\(timerName) /etc/systemd/system/\(serviceName)",
            "\(indent)rm -f '\(configPath)' '\(statusPath)'",
            "\(indent)rm -f '\(scriptPath)'"
        ]
    }

    /// One service this wrapper can update
    private struct Target {
        let id: String
        let project: String
        /// Directory holding the compose file
        let directory: String
        /// Which arm of the BACKUP wrapper to run first
        let backupTarget: String
        let images: [String]
    }

    private static func plan(_ services: [any ManagedService],
                             context: ServiceContext) -> (targets: [Target], selfManaged: [String]) {
        var targets: [Target] = []
        var selfManaged: [String] = []
        for service in services {
            let spec = service.updateSpec(context)
            switch spec.flavour {
            case .ownUpdater:
                selfManaged.append(service.id.rawValue)
            case .builtOnServer:
                continue
            case .composePull:
                guard case .docker(let project) = service.runtime,
                      let directory = service.composeFile(context)?.directory,
                      !spec.images.isEmpty else { continue }
                var backupTarget = ""
                switch service.actions(context).backup {
                case .wrapperScript(let backup): backupTarget = backup.wrapperTarget
                case .encryptedVolume: backupTarget = service.id.rawValue
                case nil: break
                }
                targets.append(Target(id: service.id.rawValue, project: project,
                                      directory: directory, backupTarget: backupTarget,
                                      images: spec.images))
            }
        }
        return (targets, selfManaged)
    }

    /// True when this deployment has anything to update — i.e
    static func isUsed(_ services: [any ManagedService], context: ServiceContext) -> Bool {
        !plan(services, context: context).targets.isEmpty
    }

    /// The wrapper
    static func wrapper(services: [any ManagedService],
                        context: ServiceContext, language: AppLanguage) -> String {
        let (targets, selfManaged) = plan(services, context: context)
        let knownIDs = targets.map(\.id).joined(separator: " ")
        let selfManagedIDs = selfManaged.joined(separator: " ")
        let serviceArms = targets.map { target in
            "    \(target.id)) PROJECT='\(target.project)'; DIR='\(target.directory)'; "
                + "BACKUP_TARGET='\(target.backupTarget)'; "
                + "IMAGES='\(target.images.joined(separator: " "))' ;;"
        }.joined(separator: "\n")

        let script = #"""
        #!/bin/bash
        # Managed by gryonixNexus — update housekeeping for the Server Dashboard.
        # Usage: gryonixnexus-update-ctl.sh check <service|--all>
        #        gryonixnexus-update-ctl.sh run <service|\#(scheduledFlag)>
        #        gryonixnexus-update-ctl.sh set-schedule \#(ScheduleSections.grammar) [services...]
        #        gryonixnexus-update-ctl.sh status
        set -euo pipefail

        ACTION="${1:-}"
        CONFIG='\#(configPath)'
        STATUS_FILE='\#(statusPath)'
        # The one thing that makes a backup on this host. An update takes one
        # BEFORE it changes anything, and it calls this rather than carrying its
        # own copy of tar/pg_dump/gpg — the whole reason that wrapper exists.
        BACKUP_CTL='\#(BackupControlSections.scriptPath)'
        # Every service this wrapper can update. Baked in; the config below may
        # only ever be a subset of it.
        KNOWN='\#(knownIDs)'
        # Services that ship their own updater (mailcow's update.sh, GitLab's
        # omnibus, which migrates and reconfigures itself on start). Named so
        # the refusal can say WHY instead of "unsupported service" — swapping
        # their images on a schedule breaks an installation rather than
        # updating it, and their own updater is the app's per-service Update
        # button.
        SELF_MANAGED='\#(selfManagedIDs)'
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
        HEALTH_TIMEOUT="${GRYONIXNEXUS_UPDATE_HEALTH_TIMEOUT:-300}"
        # Per-request budget for a registry. A slow registry is a normal
        # condition, not a fault: it ends as UNKNOWN, never as a failed run.
        HTTP_TIMEOUT="${GRYONIXNEXUS_UPDATE_HTTP_TIMEOUT:-20}"
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
          [ -f "$CONFIG" ] && . "$CONFIG"
          # A config from an older build may not set every value.
          : "${SCHEDULE:=off}" "${SERVICES:=}"
        }

        # --- per-service locking (see LockSections) --------------------------

        \#(LockSections.helper)

        # --- arguments -------------------------------------------------------

        # A service label and nothing else. This script is whitelisted in
        # sudoers with no arguments pinned, which is only acceptable because it
        # validates its own input: an unchecked argument that reaches docker
        # here is an argument that reached root.
        gd_valid_label() {
          case "${1:-}" in
            ''|*[!a-z0-9-]*) echo "invalid service: ${1:-}" >&2; return 2 ;;
          esac
          return 0
        }

        # The table. Everything an update needs comes from HERE — the caller's
        # bytes only choose an arm, they are never spliced into a command.
        gd_load_service() {
          case "$1" in
        \#(serviceArms.isEmpty ? "    __none__) ;; # nothing here updates through a pull" : serviceArms)
            *) echo "unsupported service: ${1}" >&2; return 2 ;;
          esac
        }

        gd_is_self_managed() {
          local known
          for known in $SELF_MANAGED; do
            if [ "$1" = "$known" ]; then return 0; fi
          done
          return 1
        }

        # Deliberately NOT a marker: what these run is decided by their own
        # updater at run time, so this wrapper has no standing to call them
        # current, available or unknown. A line of prose is what a person
        # reading the log gets; the app's parser ignores it.
        gd_self_managed_note() {
          printf '%s: updated by its own updater, not by this wrapper\n' "$1"
        }

        # --- the registry ----------------------------------------------------

        # The digest `docker pull` recorded for THIS reference — not the image
        # id, which is a local content address with no counterpart in a
        # registry. Empty when the host has never pulled it.
        gd_local_digest() {
          local ref="$1" name="${1%:*}"
          # Docker records Docker Hub images by their short name
          name="${name#docker.io/}"; name="${name#library/}"
          # Guarded as a whole: `head` closes the pipe early, and a SIGPIPE'd
          # `docker` would fail the run under pipefail.
          { docker image inspect "$ref" --format '{{range .RepoDigests}}{{println .}}{{end}}' 2>/dev/null \
              | grep -F "$name@" | head -n 1 | sed 's/.*@//'; } || true
        }

        # One HEAD against a registry. Never `curl -f`: it throws the body and
        # the status away, and here the RESPONSE is the answer — a 401 carries
        # the challenge that names the token endpoint. Never fatal either.
        gd_registry_head() {
          if [ -n "$2" ]; then
            curl -sS -I --max-time "$HTTP_TIMEOUT" -D - -o /dev/null \
              -H "$ACCEPT_HEADER" -H "Authorization: Bearer $2" "$1" 2>/dev/null || true
          else
            curl -sS -I --max-time "$HTTP_TIMEOUT" -D - -o /dev/null \
              -H "$ACCEPT_HEADER" "$1" 2>/dev/null || true
          fi
        }

        # `key="value"` out of a WWW-Authenticate challenge.
        gd_challenge_field() {
          printf '%s' "$1" | sed -n "s/.*$2=\"\([^\"]*\)\".*/\1/p" | head -n 1
        }

        gd_status_code() {
          printf '%s\n' "$1" | awk 'toupper($1) ~ /^HTTP/ {c=$2} END {print c}'
        }

        # An anonymous pull token. Parsed with sed rather than jq: jq is not a
        # dependency of this script, and its absence would turn every check on
        # the host into UNKNOWN. The pattern also matches "access_token", which
        # is the same value wherever both are sent.
        gd_registry_token() {
          local body=""
          body="$(curl -sS --max-time "$HTTP_TIMEOUT" --get \
                    --data-urlencode "service=$2" --data-urlencode "scope=$3" "$1" 2>/dev/null)" || true
          printf '%s' "$body" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p' | head -n 1
        }

        # What the tag resolves to in its own registry, right now. Empty when
        # the question could not be answered — the caller turns that into
        # UNKNOWN, never into "up to date".
        gd_remote_digest() {
          local ref="$1" host repo tag url response code challenge realm service scope token digest
          # A reference pinned by digest cannot move: it already IS what it
          # resolves to, and there is nothing to ask anyone.
          case "$ref" in
            *@sha256:*) printf '%s' "${ref##*@}"; return 0 ;;
          esac
          case "$ref" in
            */*)
              host="${ref%%/*}"
              case "$host" in
                # A first component with a dot or a port is a registry host;
                # anything else is a Docker Hub namespace (`adguard/…`).
                *.*|*:*|localhost) repo="${ref#*/}" ;;
                *) host='registry-1.docker.io'; repo="$ref" ;;
              esac
              ;;
            *) host='registry-1.docker.io'; repo="library/$ref" ;;
          esac
          case "$host" in
            docker.io|index.docker.io) host='registry-1.docker.io' ;;
          esac
          case "$repo" in
            *:*) tag="${repo##*:}"; repo="${repo%:*}" ;;
            *) tag='latest' ;;
          esac
          url="https://$host/v2/$repo/manifests/$tag"
          response="$(gd_registry_head "$url" '')"
          code="$(gd_status_code "$response")"
          if [ "$code" = "401" ]; then
            challenge="$({ printf '%s\n' "$response" | grep -i '^www-authenticate:' | head -n 1 | tr -d '\r'; } || true)"
            realm="$(gd_challenge_field "$challenge" realm)"
            service="$(gd_challenge_field "$challenge" service)"
            scope="$(gd_challenge_field "$challenge" scope)"
            [ -n "$scope" ] || scope="repository:$repo:pull"
            [ -n "$realm" ] || return 1
            token="$(gd_registry_token "$realm" "$service" "$scope")"
            [ -n "$token" ] || return 1
            response="$(gd_registry_head "$url" "$token")"
            code="$(gd_status_code "$response")"
          fi
          [ "$code" = "200" ] || return 1
          digest="$({ printf '%s\n' "$response" | grep -i '^docker-content-digest:' \
                        | head -n 1 | tr -d '\r' | awk '{print $2}'; } || true)"
          [ -n "$digest" ] || return 1
          printf '%s' "$digest"
        }

        # --- the check -------------------------------------------------------

        gd_check_service() {
          local svc="$1" moved=0 unknown='' img local_digest remote_digest
          gd_load_service "$svc" || return 2
          for img in $IMAGES; do
            local_digest="$(gd_local_digest "$img")"
            if [ -z "$local_digest" ]; then
              # The host is not running this image at all, so there is nothing
              # to compare. Saying "up to date" here would be a guess.
              unknown=not_pulled
              continue
            fi
            remote_digest="$(gd_remote_digest "$img")" || remote_digest=''
            if [ -z "$remote_digest" ]; then
              unknown=registry_unreachable
              continue
            fi
            if [ "$local_digest" != "$remote_digest" ]; then
              printf '%s %s %s\n' '\#(availableMarker)' "$svc" "$img"
              moved=1
            fi
          done
          # Order matters: an unanswered image outranks "nothing moved", so a
          # partial answer can never be printed as CURRENT. An image that DID
          # move is reported either way — the app already prefers it.
          if [ -n "$unknown" ]; then
            printf '%s %s %s\n' '\#(unknownMarker)' "$svc" "$unknown"
          elif [ "$moved" -eq 0 ]; then
            printf '%s %s\n' '\#(currentMarker)' "$svc"
          fi
        }

        do_check() {
          local target="${1:---all}" svc
          if ! command -v docker >/dev/null 2>&1; then
            # No docker means no local digests, i.e. no answer for anything.
            for svc in $KNOWN; do
              printf '%s %s %s\n' '\#(unknownMarker)' "$svc" 'docker_unavailable'
            done
            return 0
          fi
          if [ "$target" = "--all" ]; then
            for svc in $KNOWN; do gd_check_service "$svc"; done
            for svc in $SELF_MANAGED; do gd_self_managed_note "$svc"; done
            return 0
          fi
          gd_valid_label "$target" || exit 2
          if gd_is_self_managed "$target"; then gd_self_managed_note "$target"; return 0; fi
          gd_check_service "$target" || exit 2
        }

        # --- applying one ----------------------------------------------------

        gd_image_id() {
          { docker image inspect "$1" --format '{{.Id}}' 2>/dev/null | head -n 1; } || true
        }

        # Puts every tag back on the image it pointed at before the pull.
        # `docker pull` does not delete what it replaced — it only moves the
        # tag — so this needs no registry and works with the network down,
        # which is exactly the state a failed update can leave a host in.
        gd_restore_images() {
          local img old now
          while read -r img old; do
            if [ -z "$old" ]; then
              echo "no previous image to put back for $img" >&2
              continue
            fi
            now="$(gd_image_id "$img")"
            if [ "$now" = "$old" ]; then continue; fi
            docker tag "$old" "$img" >/dev/null 2>&1 || echo "could not put $img back" >&2
          done < "$1"
        }

        # Waits for every container of the project to be up, and prints WHY it
        # is not when the deadline passes. Progress goes to stderr so the
        # reason stays the only thing on stdout.
        # **One clean look is not health.** A wait that accepted its
        # first clean look therefore called a broken update good and never rolled
        # back. That was fixed for container GROUPS in the agent and did not
        # reach here, which is the cost of one rule living in two places.
        #
        # So: clean on \#(healthySettleSamples) looks in a row, AND the restart
        # counters unchanged across them — the second catches a loop whose
        # up-windows happen to line up with the polls.
        gd_wait_healthy() {
          local project="$1" deadline now beat ids cid state status restarting exitcode health bad
          local clean=0 counters="" counters_now=""
          now="$(date +%s)"
          deadline=$((now + $2))
          beat=$((now + 30))
          while : ; do
            bad=''
            ids="$(docker compose -p "$project" ps -q 2>/dev/null || true)"
            if [ -z "$ids" ]; then
              bad='no container is running'
            else
              for cid in $ids; do
                state="$(docker inspect -f '{{.State.Status}} {{.State.Restarting}} {{.State.ExitCode}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" 2>/dev/null || true)"
                if [ -z "$state" ]; then bad='a container disappeared'; continue; fi
                read -r status restarting exitcode health <<< "$state"
                if [ "$restarting" = "true" ]; then bad='a container is restarting'; continue; fi
                case "$status" in
                  running)
                    case "$health" in
                      unhealthy) bad='a container reports unhealthy' ;;
                      starting) bad='a container is still starting' ;;
                    esac
                    ;;
                  # A one-shot container that finished cleanly is not a fault:
                  # several stacks here run an init container that exits 0.
                  exited)
                    if [ "$exitcode" != "0" ]; then bad="a container exited with $exitcode"; fi
                    ;;
                  *) bad="a container is $status" ;;
                esac
              done
            fi
            if [ -z "$bad" ]; then
              # shellcheck disable=SC2086
              counters_now="$(docker inspect -f '{{.Name}} {{.RestartCount}}' $ids 2>/dev/null || true)"
              if [ "$clean" -eq 0 ] || [ "$counters_now" != "$counters" ]; then
                clean=1
                counters="$counters_now"
              else
                clean=$((clean + 1))
              fi
              if [ "$clean" -ge \#(healthySettleSamples) ]; then return 0; fi
              bad='waiting for the containers to hold still'
            else
              clean=0
            fi
            now="$(date +%s)"
            if [ "$now" -ge "$deadline" ]; then printf '%s\n' "$bad"; return 1; fi
            if [ "$now" -ge "$beat" ]; then
              # The app streams this; minutes of silence read as a hung run.
              echo "waiting for $project: $bad" >&2
              beat=$((now + 30))
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
          local svc="$1"
          # Neither refusal below is recorded: both answer a question that was
          # never a run. A scheduled run cannot reach them at all — set-schedule
          # keeps self-managed and unknown ids out of SERVICES — so a record
          # here could only ever describe a button press whose answer the person
          # who pressed it is already reading.
          if gd_is_self_managed "$svc"; then
            echo "$svc ships its own updater, so this wrapper does not swap its images" >&2
            return 2
          fi
          gd_load_service "$svc" || return 2

          local rc=0
          gd_with_lock "update-$svc" gd_update_service_locked "$svc" || rc=$?
          if [ "$rc" -eq "$GD_LOCK_BUSY" ]; then
            # UNLIKE the refusals above, this IS recorded: the service was
            # eligible to run and did not, which is exactly the failure mode
            # `autoupdate-status.txt` exists to catch — a scheduled run that
            # skips silently reads as "nothing happened" to whoever checks
            # back later (see LockSections).
            gd_record "$(printf '%s %s %s' '\#(failedMarker)' "$svc" \
              'another update for this service was already running')"
          fi
          return "$rc"
        }

        # The ONE body both callers go through, once the lock is held. Two
        # copies of this is the drift the backup wrapper already exists to
        # prevent.
        gd_update_service_locked() {
          local svc="$1" img old work='' reason='' health=''

          # 1. A backup FIRST, through the wrapper that owns backups. A failed
          # backup stops the update: the point of taking one is that the update
          # is the risky part.
          if [ -n "$BACKUP_TARGET" ]; then
            if [ ! -x "$BACKUP_CTL" ]; then
              echo "the backup helper is missing, so $svc was not updated" >&2
              gd_record "$(printf '%s %s %s' '\#(failedMarker)' "$svc" 'the backup helper is missing')"
              return 1
            fi
            echo "backing up $svc before updating it"
            # stdin is /dev/null on purpose. The backup wrapper reads a
            # passphrase from stdin when it encrypts, and an open pipe with
            # nobody writing would park it forever; closed, it falls back to the
            # stored passphrase and refuses if there is none — which is the
            # right answer for an unattended run over a secret store.
            if ! "$BACKUP_CTL" backup "$BACKUP_TARGET" < /dev/null; then
              echo "the backup of $svc failed, so the update was not applied" >&2
              gd_record "$(printf '%s %s %s' '\#(failedMarker)' "$svc" 'the backup failed')"
              return 1
            fi
          else
            echo "$svc declares no backup, so none was taken before this update"
          fi

          # 2. What a rollback would return to. Readable only now: after the
          # pull the tag points somewhere else.
          work="$(mktemp -d)"
          : > "$work/before"
          for img in $IMAGES; do
            old="$(gd_image_id "$img")"
            printf '%s %s\n' "$img" "$old" >> "$work/before"
          done

          # 3. Pull, then restart. `cd` because pull and up need the compose
          # FILE (ps finds the project by label, these do not).
          if ! ( cd "$DIR" && docker compose -p "$PROJECT" pull ); then
            # Nothing was restarted, so the service is still the one that was
            # running — but a partial pull may have moved a tag, and the next
            # `up` anywhere would then apply it silently.
            gd_restore_images "$work/before"
            rm -rf "$work"
            echo "could not pull the new images for $svc" >&2
            gd_record "$(printf '%s %s %s' '\#(failedMarker)' "$svc" 'could not pull the new images')"
            return 1
          fi
          if ! ( cd "$DIR" && docker compose -p "$PROJECT" up -d ); then
            reason=did_not_start
          else
            if ! health="$(gd_wait_healthy "$PROJECT" "$HEALTH_TIMEOUT")"; then
              reason="${health:-unhealthy}"
            fi
          fi

          # 4. Roll back to the images the host was already running.
          if [ -n "$reason" ]; then
            gd_restore_images "$work/before"
            ( cd "$DIR" && docker compose -p "$PROJECT" up -d ) || true
            rm -rf "$work"
            gd_record "$(printf '%s %s %s' '\#(rolledBackMarker)' "$svc" "$reason")"
            return 1
          fi
          rm -rf "$work"
          gd_record "$(printf '%s %s' '\#(updatedMarker)' "$svc")"
        }

        # --- the record ------------------------------------------------------

        # Printed AND kept. The print is for the app streaming this run; the
        # copy is for the app that was closed when the timer fired.
        gd_record() {
          printf '%s\n' "$1"
          install -d -m 755 "$(dirname "$STATUS_FILE")" 2>/dev/null || true
          printf '%s\n' "$1" >> "$STATUS_FILE" 2>/dev/null || true
          # Bounded: manual runs append here too and nothing else prunes it.
          { tail -n 200 "$STATUS_FILE" > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"; } 2>/dev/null || true
          chmod 644 "$STATUS_FILE" 2>/dev/null || true
        }

        do_status() {
          # Read-only, and missing is not an error: a server that has never run
          # an update has nothing to report, which is not the same as broken.
          { cat "$STATUS_FILE" 2>/dev/null; } || true
        }

        do_run() {
          local target="${1:-}" svc failed=''
          if [ "$target" = '\#(scheduledFlag)' ]; then
            load_config
            install -d -m 755 "$(dirname "$STATUS_FILE")" 2>/dev/null || true
            printf 'last-run %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATUS_FILE" 2>/dev/null || true
            for svc in $SERVICES; do
              # Each service in its own subshell, and the `||` keeps errexit
              # from firing: an unattended run must not let one broken service
              # cancel the updates of every service after it.
              ( gd_update_service "$svc" ) || failed="$failed $svc"
            done
            if [ -n "$failed" ]; then
              echo "the update failed for:$failed" >&2
              exit 1
            fi
            return 0
          fi
          gd_valid_label "$target" || exit 2
          gd_update_service "$target"
        }

        do_set_schedule() {
        \#(ScheduleSections.argumentComment)
          local schedule="${1:-off}"
          shift || true
          local services="$*"
        \#(ScheduleSections.parser)
          # Only services this wrapper can actually update may end up in the
          # config — a self-managed one ticked in the app is dropped HERE rather
          # than accepted and skipped later, because the app reads this file
          # back and the switch has to show what the server will really do.
          local checked=""
          for svc in $services; do
            # Membership tested against the baked-in list itself, so the set of
            # updatable services exists ONCE in this script and cannot disagree
            # with itself. The quotes inside the pattern are what make the
            # comparison literal: a caller sending `*` matches nothing.
            case " $KNOWN " in
              *" $svc "*) checked="$checked $svc" ;;
            esac
          done
          install -d -m 755 "$(dirname "$CONFIG")"
          cat > "$CONFIG" <<EOF_UP_CONF
        SCHEDULE=$schedule
        SERVICES='${checked# }'
        EOF_UP_CONF
          # World-readable on purpose: it holds no secrets and the app reads it
          # without sudo.
          chmod 644 "$CONFIG"
        \#(ScheduleSections.timerActivation(timerName: timerName,
                                            description: "gryonixNexus scheduled updates",
                                            delimiter: "EOF_UP_TIMER"))
        }

        case "$ACTION" in
          check) shift; do_check "$@" ;;
          run) shift; do_run "$@" ;;
          set-schedule) shift; do_set_schedule "$@" ;;
          status) do_status ;;
          *) echo "unsupported action: ${ACTION}" >&2; exit 2 ;;
        esac
        echo '\#(doneMarker)'
        """#

        let unit = #"""
        [Unit]
        Description=gryonixNexus scheduled update run
        After=docker.service
        [Service]
        Type=oneshot
        ExecStart=\#(scriptPath) run \#(scheduledFlag)
        """#

        return #"""
        log "\#(L10nScripts.updateControlWrapperLog(language))"
        \#(BashSections.writeFile(path: scriptPath, contents: script, delimiter: "EOF_UPDATE_CTL"))
        chmod 750 '\#(scriptPath)'
        # 755: the schedule config inside is read by the app without sudo.
        install -d -m 755 \#(configDirectory)
        \#(BashSections.writeFile(path: "/etc/systemd/system/\(serviceName)", contents: unit, delimiter: "EOF_AUTOUPDATE_UNIT"))
        systemctl daemon-reload
        # The timer itself is created only when the user turns the schedule on.
        """#
    }
}
