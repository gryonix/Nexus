package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.ArchiveBackupPlan
import com.skaymer.gryonixnexus.catalog.BackupDatabase
import com.skaymer.gryonixnexus.catalog.BackupPlan
import com.skaymer.gryonixnexus.catalog.BackupSpec
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.embedding

internal object BackupControlSections {
    const val SCRIPT_PATH = "/opt/gryonixnexus-backup-ctl.sh"
    const val DONE_MARKER = "GRYONIXNEXUS_BACKUP_CTL_DONE"

    /** Printed by a finished backup: `<marker> <bytes> <path>` */
    const val BACKUP_DONE_MARKER = "GRYONIXNEXUS_BACKUP_DONE"

    /** Printed by `estimate`: `<marker> <data bytes> <free bytes>` */
    const val ESTIMATE_MARKER = "GRYONIXNEXUS_BACKUP_ESTIMATE"

    /** Directory holding the schedule config and the passphrase */
    const val CONFIG_DIRECTORY = "/etc/gryonixnexus"

    /** Where the schedule lives */
    const val CONFIG_PATH = "$CONFIG_DIRECTORY/autobackup.conf"

    /** The GPG passphrase for unattended encrypted backups */
    const val PASSPHRASE_PATH = "$CONFIG_DIRECTORY/autobackup.pass"

    const val DESTINATION_PATH = "$CONFIG_DIRECTORY/autobackup-dest.conf"

    const val DESTINATION_SECRET_PATH = "$CONFIG_DIRECTORY/autobackup-dest.key"

    const val DESTINATION_PUBLIC_KEY_PATH = "$CONFIG_DIRECTORY/autobackup-dest.key.pub"

    /** What the last shipment did */
    const val DESTINATION_STATUS_PATH = "$CONFIG_DIRECTORY/autobackup-dest.status"

    /** Where the far side's host key is pinned */
    const val DESTINATION_KNOWN_HOSTS_PATH = "$CONFIG_DIRECTORY/autobackup-dest.known_hosts"

    const val TIMER_NAME = "gryonixnexus-autobackup.timer"
    const val SERVICE_NAME = "gryonixnexus-autobackup.service"

    fun needsStoredPassphrase(services: List<ManagedService>, context: ServiceContext): Boolean =
        services.any { it.actions(context).backup?.encryptsByDefault == true }

    /** Generates the host's automatic-backup passphrase, once */
    fun passphraseSection(services: List<ManagedService>, context: ServiceContext): String {
        if (!needsStoredPassphrase(services, context)) return ""
        return """
        log "Backup passphrase"
        install -d -m 755 '$CONFIG_DIRECTORY'
        if [ ! -s '$PASSPHRASE_PATH' ]; then
          # umask, not chmod after the fact: the secret must never exist as a
          # world-readable file, not even for the instant between the two.
          ( umask 077 && head -c 20 /dev/urandom | od -An -tx1 | tr -d '[:space:]' \
              > '$PASSPHRASE_PATH' )
          chmod 600 '$PASSPHRASE_PATH'
        fi
        """.trimIndent()
    }

    /** Removal of everything this section installs, for the uninstall wrapper */
    fun uninstallLines(indent: String): List<String> = listOf(
        "$indent# Scheduled backups: the timer is armed by set-schedule, not by",
        "$indent# setup, so it outlives the services unless it is stopped here.",
        "${indent}systemctl disable --now '$TIMER_NAME' >/dev/null 2>&1 || true",
        "${indent}rm -f /etc/systemd/system/$TIMER_NAME /etc/systemd/system/$SERVICE_NAME",
        "$indent# The destination, its key and its last result — the key is a real",
        "$indent# secret and the config names somebody else's machine.",
        "${indent}rm -f '$DESTINATION_PATH' '$DESTINATION_SECRET_PATH' '$DESTINATION_PUBLIC_KEY_PATH' " +
            "'$DESTINATION_STATUS_PATH' '$DESTINATION_KNOWN_HOSTS_PATH'",
        "${indent}rm -f '$SCRIPT_PATH'",
        "${indent}rm -rf '$CONFIG_DIRECTORY'"
    )

    private data class AutoBackupTarget(
        val id: String,
        val backupDir: String,
        val encryptsByDefault: Boolean,
        /** Paths the estimate sums */
        val sizePaths: List<String>,
        val body: String
    )

    private fun functionName(id: String): String = id.replace("-", "_")

    private fun quotedPath(path: String): String =
        path.split("*").joinToString("*") { if (it.isEmpty()) "" else "'$it'" }

    /** Every backup-capable service, in catalog order, described for the wrapper */
    private fun targets(access: DashboardAccessInput, services: List<ManagedService>,
                        context: ServiceContext): List<AutoBackupTarget> {
        val result = mutableListOf<AutoBackupTarget>()
        for (service in services) {
            when (val backup = service.actions(context).backup) {
                null -> continue

                is BackupSpec.WrapperScript -> {
                    val spec = backup.spec
                    when (val plan = spec.plan) {
                        is BackupPlan.ExternalScript -> result.add(AutoBackupTarget(
                            id = spec.wrapperTarget,
                            backupDir = spec.backupDir,
                            encryptsByDefault = false,
                            sizePaths = plan.sizePaths,
                            body = "  '${plan.path}'\n  gd_drive_copy_newest '${spec.backupDir}' '${spec.wrapperTarget}'"
                        ))

                        is BackupPlan.Archive -> result.add(AutoBackupTarget(
                            id = spec.wrapperTarget,
                            backupDir = spec.backupDir,
                            encryptsByDefault = plan.plan.encryptsByDefault,
                            sizePaths = plan.plan.sizePaths,
                            body = archiveBody(spec.wrapperTarget, spec.backupDir, plan.plan)
                        ))
                    }
                }

                is BackupSpec.EncryptedVolume -> result.add(AutoBackupTarget(
                    id = service.id.rawValue,
                    backupDir = backup.backupDir,
                    encryptsByDefault = true,
                    sizePaths = listOf(backup.dataPath),
                    body = """
                      local stamp plain
                      stamp="${SH}(date +%Y%m%d-%H%M%S)"
                      plain='${backup.backupDir}/vaultwarden-backup.tar.gz'
                      docker stop '${backup.container}' >/dev/null 2>&1 || true
                      local archived=0
                      tar -czf "${SH}plain" '${backup.dataPath}' 2>/dev/null && archived=1
                      # The container comes back up no matter what the archive did.
                      docker start '${backup.container}' >/dev/null 2>&1 || true
                      if [ "${SH}archived" -ne 1 ] || [ ! -s "${SH}plain" ]; then
                        rm -f "${SH}plain"
                        echo "the vaultwarden archive could not be written" >&2
                        return 1
                      fi
                      if ! printf '%s' "${SH}GD_PASS" | gpg --batch --quiet --yes --symmetric \
                           --cipher-algo AES256 --passphrase-fd 0 --pinentry-mode loopback \
                           --output "${SH}plain.${SH}stamp.gpg" "${SH}plain"; then
                        rm -f "${SH}plain"
                        echo "could not encrypt the vaultwarden backup" >&2
                        return 1
                      fi
                      # The plain archive never outlives the encrypted one.
                      rm -f "${SH}plain"
                      chmod 600 "${SH}plain.${SH}stamp.gpg"
                      chown "${SH}OWNER" "${SH}plain.${SH}stamp.gpg" 2>/dev/null || true
                      # Rotation: keep the newest RETENTION encrypted archives. The
                      # pipeline is guarded — with fewer archives than RETENTION,
                      # `ls` finds nothing to list and would fail the whole run
                      # under pipefail (which is every first run).
                      { ls -1t '${backup.backupDir}'/*.gpg 2>/dev/null || true; } \
                        | tail -n +${SH}((RETENTION + 1)) | xargs -r rm -f
                      printf '%s %s %s\n' '$BACKUP_DONE_MARKER' \
                        "${SH}(stat -c %s "${SH}plain.${SH}stamp.gpg" 2>/dev/null || echo 0)" "${SH}plain.${SH}stamp.gpg"
                      gd_drive_copy "${SH}plain.${SH}stamp.gpg" 'vaultwarden'
                    """.trimIndent().prependIndent("  ")
                ))
            }
        }
        return result
    }

    /** The body of one generated `backup_<service>` function */
    private fun archiveBody(id: String, backupDir: String, plan: ArchiveBackupPlan): String {
        val project = plan.composeProject
        val quiesce = plan.quiesceServices.joinToString(" ") { "'$it'" }
        val dumps = ArchiveBackupPlan.DUMP_DIRECTORY_NAME
        val lines = mutableListOf(
            "  local stamp work plain rc=0",
            "  install -d -m 750 '$backupDir'",
            "  stamp=\"${SH}(date +%Y%m%d-%H%M%S)\"",
            "  work=\"${SH}(mktemp -d '$backupDir/.work-XXXXXX')\"",
            "  plain=\"${SH}work/$id-${SH}stamp.tar.gz\"",
            "  install -d -m 700 \"${SH}work/$dumps\"",
            "  if [ ! -d '${plan.dataPath}' ]; then",
            "    rm -rf \"${SH}work\"",
            "    echo \"$id has no data at ${plan.dataPath}\" >&2",
            "    return 1",
            "  fi"
        )
        if (plan.quiesceServices.isNotEmpty()) {
            lines += listOf(
                "  # Stopped for the archive only, and started again on EVERY path",
                "  # below — a backup that leaves the service down is an outage.",
                "  gd_compose_stop '$project' $quiesce"
            )
        }
        for (database in plan.databases) {
            val helper = if (database.engine == BackupDatabase.Engine.POSTGRES) {
                "gd_dump_postgres"
            } else {
                "gd_dump_mysql"
            }
            val named = database.databaseName?.let { " '$it'" } ?: ""
            lines += "  $helper '$project' '${database.service}' " +
                "\"${SH}work/$dumps/${database.fileName}\"$named || rc=1"
        }
        val excludes = plan.excludes.joinToString("") { " --exclude '$it'" }
        lines += listOf(
            "  if [ \"${SH}rc\" -eq 0 ]; then",
            "    tar --numeric-owner -czf \"${SH}plain\"$excludes \\",
            "        -C '${plan.dataParent}' '${plan.dataSlot}' \\",
            "        -C \"${SH}work\" '$dumps' || rc=1",
            "  fi"
        )
        if (plan.quiesceServices.isNotEmpty()) {
            lines += "  gd_compose_start '$project' $quiesce"
        }
        lines += listOf(
            "  if [ \"${SH}rc\" -ne 0 ]; then",
            "    rm -rf \"${SH}work\"",
            "    echo \"$id backup failed\" >&2",
            "    return 1",
            "  fi",
            "  gd_finish '$id' '$backupDir' \"${SH}plain\" \"${SH}work\""
        )
        return lines.joinToString("\n")
    }

    const val SCHEDULE_GRAMMAR = ScheduleSections.GRAMMAR

    /** The wrapper */
    fun wrapper(access: DashboardAccessInput, services: List<ManagedService>,
                context: ServiceContext, language: AppLanguage): String {
        val targets = targets(access, services, context)
        val dirCases = targets.joinToString("|") { "\"${it.backupDir}\"/*" }
        val functions = targets.joinToString("\n\n") { target ->
            """
            backup_${functionName(target.id)}() {
            @BODY@
            }
            """.trimIndent().embedding("BODY" to target.body)
        }
        val dispatchArms = targets.joinToString("\n") { target ->
            "    ${target.id}) gd_with_lock 'backup-${target.id}' " +
                "backup_${functionName(target.id)} ;;"
        }
        val encryptArms = targets.joinToString("\n") { target ->
            "    ${target.id}) echo ${if (target.encryptsByDefault) 1 else 0} ;;"
        }
        val estimateArms = targets.joinToString("\n") { target ->
            val paths = target.sizePaths.joinToString(" ") { quotedPath(it) }
            "    ${target.id}) dir='${target.backupDir}'; paths=($paths) ;;"
        }
        val allIDs = targets.joinToString(" ") { it.id }

        val script = """
        #!/bin/bash
        # Managed by gryonixNexus — backup housekeeping for the Server Dashboard.
        # Usage: gryonixnexus-backup-ctl.sh delete <path>
        #        gryonixnexus-backup-ctl.sh set-schedule $SCHEDULE_GRAMMAR <retention> [services...]
        #        gryonixnexus-backup-ctl.sh set-passphrase   (passphrase on stdin)
        #        gryonixnexus-backup-ctl.sh run
        #        gryonixnexus-backup-ctl.sh backup <service> [--encrypt|--no-encrypt]
        #                                       (GPG passphrase on stdin when encrypting)
        #        gryonixnexus-backup-ctl.sh estimate <service>
        #        gryonixnexus-backup-ctl.sh set-destination <kind> <host> <port> <user> <path> <bucket> <keep>
        #                                       (credential on stdin, optional)
        #        gryonixnexus-backup-ctl.sh show-destination
        #        gryonixnexus-backup-ctl.sh test-destination
        #        gryonixnexus-backup-ctl.sh set-drives <both|local|drive> <1|0> [uuids...]
        #        gryonixnexus-backup-ctl.sh show-drives
        set -euo pipefail

        ACTION="${SH}{1:-}"
        CONFIG='$CONFIG_PATH'
        PASSFILE='$PASSPHRASE_PATH'
        DESTCONF='$DESTINATION_PATH'
        DESTKEY='$DESTINATION_SECRET_PATH'
        DESTPUB='$DESTINATION_PUBLIC_KEY_PATH'
        DESTSTATUS='$DESTINATION_STATUS_PATH'
        RETENTION=${access.keptBackups}
        SERVICES='$allIDs'
        SCHEDULE=off
        # The control user. Finished archives are chowned to it: the app
        # downloads and shares them, and what keeps other accounts away is the
        # 0750 on the enclosing backup root, not the file's owner.
        OWNER='${access.sshUser}'
        # Encryption state of the CURRENT run. The passphrase lives in a shell
        # variable and reaches gpg down a pipe — never in argv, which is
        # world-readable through /proc.
        GD_ENCRYPT=0
        GD_PASS=""

        load_config() {
          # shellcheck disable=SC1090
          [ -f "${SH}CONFIG" ] && . "${SH}CONFIG"
          # A config from an older build may not set every value.
          : "${SH}{SCHEDULE:=off}" "${SH}{RETENTION:=${access.keptBackups}}" "${SH}{SERVICES:=$allIDs}"
          case "${SH}RETENTION" in ''|*[!0-9]*|0) RETENTION=1 ;; esac
        }

        # Where finished archives are sent, if anywhere. Its own file and its
        # own loader: a host that never chose a destination keeps every default
        # below, which together mean "leave the archive where it is".
        DEST_KIND=none
        DEST_HOST=""
        DEST_PORT=22
        DEST_USER=""
        DEST_PATH=""
        DEST_BUCKET=""
        DEST_KEEP=0
        load_destination() {
          # shellcheck disable=SC1090
          [ -f "${SH}DESTCONF" ] && . "${SH}DESTCONF"
          : "${SH}{DEST_KIND:=none}" "${SH}{DEST_PORT:=22}" "${SH}{DEST_KEEP:=0}"
        }

        # **Where a copy of this machine's archives lands so they survive the
        # machine.** Called after every archive this wrapper finishes, by the
        # timer and by the app's own button alike — one body, both callers, the
        # rule this whole file is built on.
        #
        # Failure NEVER fails the backup: the archive on this disk is real and
        # already written, and refusing it because a bucket was unreachable
        # would turn a bad night into no backup at all. What a failure does is
        # get RECORDED, because a copy that silently never leaves is the exact
        # defect this exists to end.
        gd_ship() {
          local out="${SH}1" service="${SH}{2:-check}" error="" ok=0
          load_destination
          [ "${SH}DEST_KIND" = "none" ] && return 0
          # One folder per machine and service, so rotation stays inside it.
          local machine
          machine="${SH}(hostname -s 2>/dev/null || echo server)-${SH}(cut -c1-8 /etc/machine-id 2>/dev/null || echo 0)"
          local folder="${SH}{DEST_PATH%/}/${SH}machine/${SH}service"
          case "${SH}DEST_KIND" in
            ssh)
              if [ -z "${SH}DEST_HOST" ] || [ -z "${SH}DEST_USER" ] || [ ! -s "${SH}DESTKEY" ]; then
                error="the destination is incomplete (host, user or key missing)"
              else
                # **A known_hosts this machine can actually write.** Run from the agent's unit,
                # ssh cannot create /root/.ssh — ProtectHome=yes and
                # ProtectSystem=full — so `accept-new` pinned nothing and every
                # shipment carried "Could not create directory /root/.ssh" into
                # the status file, where it reads as the failure. This path is
                # inside the agent's ReadWritePaths and is root-owned, so the
                # timer and the app's button pin the same key in the same file.
                local known="${SH}{DESTCONF%/*}/autobackup-dest.known_hosts"
                [ -e "${SH}known" ] || ( umask 077 && : > "${SH}known" )
                # `accept-new`, not `no`: the first sight of the far side is
                # pinned, and a CHANGED key after that stops the copy — which
                # is the one moment somebody must be told rather than obeyed.
                error="${SH}(ssh -i "${SH}DESTKEY" -p "${SH}DEST_PORT" \
                          -o StrictHostKeyChecking=accept-new \
                          -o UserKnownHostsFile="${SH}known" \
                          -o BatchMode=yes -o ConnectTimeout=20 \
                          "${SH}DEST_USER@${SH}DEST_HOST" "mkdir -p '${SH}folder'" 2>&1)" \
                  && error="${SH}(scp -i "${SH}DESTKEY" -P "${SH}DEST_PORT" \
                          -o StrictHostKeyChecking=accept-new \
                          -o UserKnownHostsFile="${SH}known" \
                          -o BatchMode=yes -o ConnectTimeout=20 \
                          "${SH}out" "${SH}DEST_USER@${SH}DEST_HOST:${SH}folder/" 2>&1)" \
                  && ok=1
                # **A warning is not a failure.** ssh writes advice to stderr on
                # runs that worked, and this field is what the app shows as the
                # reason the copy did not leave; keeping it would report a
                # successful shipment as a broken one.
                [ "${SH}ok" -eq 1 ] && error=""
                if [ "${SH}ok" -eq 1 ] && [ "${SH}DEST_KEEP" -gt 0 ]; then
                  # Rotation on the FAR side, and only there: what this machine
                  # keeps is RETENTION, and the two are different numbers on
                  # purpose — a phone-sized disk here, a big one there.
                  ssh -i "${SH}DESTKEY" -p "${SH}DEST_PORT" -o StrictHostKeyChecking=accept-new \
                      -o UserKnownHostsFile="${SH}known" \
                      -o BatchMode=yes "${SH}DEST_USER@${SH}DEST_HOST" \
                      "ls -1t '${SH}folder' 2>/dev/null | tail -n +${SH}((DEST_KEEP + 1)) | while read -r old; do rm -rf -- '${SH}folder'/\"\${SH}old\"; done" \
                      >/dev/null 2>&1 || true
                fi
              fi
              ;;
            s3)
              if ! command -v rclone >/dev/null 2>&1; then
                error="rclone is not installed on this server"
              elif [ ! -s "${SH}DESTKEY" ]; then
                error="no credentials stored for the bucket"
              else
                # The credentials reach rclone as ENVIRONMENT, never argv:
                # /proc/<pid>/cmdline is world-readable and an access key in it
                # is an access key given away.
                error="${SH}(
                  AWS_ACCESS_KEY_ID="${SH}(cut -d: -f1 "${SH}DESTKEY")" \
                  AWS_SECRET_ACCESS_KEY="${SH}(cut -d: -f2- "${SH}DESTKEY")" \
                  RCLONE_CONFIG_GD_TYPE=s3 \
                  RCLONE_CONFIG_GD_PROVIDER=Other \
                  RCLONE_CONFIG_GD_ENV_AUTH=true \
                  RCLONE_CONFIG_GD_ENDPOINT="${SH}DEST_HOST" \
                  rclone copy "${SH}out" "gd:${SH}DEST_BUCKET/${SH}folder/" 2>&1
                )" && ok=1
              fi
              ;;
            *) error="unknown destination kind: ${SH}DEST_KIND" ;;
          esac
          {
            echo "AT=${SH}(date +%s)"
            echo "OK=${SH}ok"
            # One line, and the far side's own words: three different repairs
            # hide behind "it failed". QUOTED, and with quotes of its own
            # removed — see `do_test_destination` on what reading this file
            # as shell used to cost.
            # **Carriage returns too, not just newlines.** ssh ends its own
            # warnings with CR, and a reader that renders them the way a
            # terminal does — the agent's does, for progress bars — keeps only
            # what follows the last one and throws the rest away. The marker line vanished and the app was told the
            # copy failed, with no reason, while the file had landed.
            echo "ERROR='${SH}(printf '%s' "${SH}error" | tr '\r\n\t' '   ' | tr -d "'" | cut -c1-400)'"
          } > "${SH}DESTSTATUS"
          chmod 644 "${SH}DESTSTATUS"
          return 0
        }

        # The key this server ships WITH, made once and never replaced: the
        # public half is already authorized on the far side, and a new pair
        # would silently stop every copy.
        gd_ensure_dest_key() {
          [ -s "${SH}DESTKEY" ] && return 0
          # **The folder first.** A server that never had the agent installed
          # has no /etc/gryonixnexus, and ssh-keygen into a folder that is not
          # there failed with its output thrown away: `set-destination` stopped
          # on the chmod that followed and answered rc 1 with not one word.
          # The app's own screen showed
          # "could not save" and nothing else.
          install -d -m 755 "${SH}(dirname "${SH}DESTKEY")"
          rm -f "${SH}DESTKEY" "${SH}DESTPUB"
          if ! ssh-keygen -t ed25519 -N '' -C 'gryonixnexus-backup' -f "${SH}DESTKEY" >/dev/null 2>&1; then
            echo "could not create the key this server ships backups with" >&2
            exit 2
          fi
          chmod 600 "${SH}DESTKEY"
          chmod 644 "${SH}DESTPUB" 2>/dev/null || true
        }

        do_set_destination() {
          local kind="${SH}{1:-none}" host="${SH}{2:-}" port="${SH}{3:-22}" user="${SH}{4:-}"
          local path="${SH}{5:-}" bucket="${SH}{6:-}" keep="${SH}{7:-0}"
          case "${SH}kind" in
            none|ssh|s3) ;;
            *) echo "unsupported destination: ${SH}{kind}" >&2; exit 2 ;;
          esac
          case "${SH}port${SH}keep" in
            ''|*[!0-9]*) echo "invalid port or keep count" >&2; exit 2 ;;
          esac
          case "${SH}host${SH}user${SH}path${SH}bucket" in
            *[\'\"\\\`\${SH}]*|*${SH}'\n'*|*${SH}'\r'*)
              echo "the destination may not contain quotes, backslashes, \${SH}, backticks or line breaks" >&2
              exit 2 ;;
          esac
          # A secret on stdin, never argv — the same rule the passphrase
          # follows one function down.
          if [ ! -t 0 ]; then
            local secret
            secret="${SH}(cat)"
            if [ -n "${SH}secret" ]; then
              install -d -m 755 "${SH}(dirname "${SH}DESTKEY")"
              ( umask 077 && printf '%s' "${SH}secret" > "${SH}DESTKEY" )
              chmod 600 "${SH}DESTKEY"
            fi
          fi
          [ "${SH}kind" = "ssh" ] && gd_ensure_dest_key
          install -d -m 755 "${SH}(dirname "${SH}DESTCONF")"
          cat > "${SH}DESTCONF" <<EOF_DEST
        DEST_KIND=${SH}kind
        DEST_HOST='${SH}host'
        DEST_PORT=${SH}port
        DEST_USER='${SH}user'
        DEST_PATH='${SH}path'
        DEST_BUCKET='${SH}bucket'
        DEST_KEEP=${SH}keep
        EOF_DEST
          # 0640 and owned by root: it names a host and an account, which is
          # the owner's business and not every account's on this machine. The
          # app reads it through this wrapper, which runs as root.
          chmod 640 "${SH}DESTCONF"
          # Printed so the app can authorize it on the far side without a
          # second call — a public key, and nothing else, is safe on stdout.
          [ -s "${SH}DESTPUB" ] && printf 'GRYONIXNEXUS_DEST_PUBKEY %s\n' "${SH}(cat "${SH}DESTPUB")"
        }

        # Everything `show-destination` answers, in one read: the app draws the
        # destination, the public key to authorize and what the last shipment
        # did on a single screen.
        do_show_destination() {
          load_destination
          printf 'DEST_KIND=%s\nDEST_HOST=%s\nDEST_PORT=%s\nDEST_USER=%s\nDEST_PATH=%s\nDEST_BUCKET=%s\nDEST_KEEP=%s\n' \
            "${SH}DEST_KIND" "${SH}DEST_HOST" "${SH}DEST_PORT" "${SH}DEST_USER" "${SH}DEST_PATH" "${SH}DEST_BUCKET" "${SH}DEST_KEEP"
          [ -s "${SH}DESTPUB" ] && printf 'DEST_PUBKEY=%s\n' "${SH}(cat "${SH}DESTPUB")"
          [ -s "${SH}DESTSTATUS" ] && cat "${SH}DESTSTATUS"
          return 0
        }

        # One small file, sent the same way a real archive is. The only way to
        # learn a destination is wrong BEFORE the nightly run trusts it.
        do_test_destination() {
          load_destination
          if [ "${SH}DEST_KIND" = "none" ]; then
            echo "GRYONIXNEXUS_DEST_TEST 0 no destination is set"
            return 0
          fi
          local probe
          probe="${SH}(mktemp /tmp/gryonixnexus-dest-XXXXXX.txt)"
          date -u +'gryonixNexus destination check %Y-%m-%dT%H:%M:%SZ' > "${SH}probe"
          gd_ship "${SH}probe" check
          rm -f "${SH}probe"
          # Read back out of the status file rather than kept in a variable:
          # what the app will see later is exactly what it is told now.
          local ok="0" error=""
          # **Parsed, never sourced.** This file carries the FAR SIDE's own
          # words, and reading it with `.` made them shell: a message with
          # "(ED25519)" in it broke the read outright, and one carrying ${SH}(…)
          # would have run here as root.
          if [ -f "${SH}DESTSTATUS" ]; then
            ok="${SH}(sed -n 's/^OK=//p' "${SH}DESTSTATUS" | head -1)"
            error="${SH}(sed -n "s/^ERROR='\(.*\)'\${SH}/\1/p" "${SH}DESTSTATUS" | head -1)"
          fi
          ok="${SH}{ok:-0}"
          echo "GRYONIXNEXUS_DEST_TEST ${SH}ok ${SH}error"
        }

        # USB drives that take a copy of every archive. A host that never
        # chose one keeps every archive here, exactly as before.
        DRIVECONF='/etc/gryonixnexus/backup-drives.conf'
        DRIVESTATUS='/etc/gryonixnexus/backup-drives.status'
        DRIVELAST='/etc/gryonixnexus/backup-drives.last'
        DRIVEROOT='/srv/gryonix-backup'
        DRIVE_MODE=both
        DRIVE_ENCRYPT=1
        DRIVES=""
        GD_DRIVE_ERROR=""
        load_drives() {
          # shellcheck disable=SC1090
          [ -f "${SH}DRIVECONF" ] && . "${SH}DRIVECONF"
          : "${SH}{DRIVE_MODE:=both}" "${SH}{DRIVE_ENCRYPT:=1}"
        }

        # Where fstab mounts one drive, whether or not it is plugged in.
        gd_drive_fstab() {
          findmnt --fstab -rno TARGET -S "UUID=${SH}1" 2>/dev/null | head -n 1
        }

        # The drive's mount point, only when it is mounted and marked.
        gd_drive_target() {
          local target
          target="${SH}(gd_drive_fstab "${SH}1")"
          case "${SH}target" in "${SH}DRIVEROOT"/*) ;; *) return 0 ;; esac
          # Never a bare folder: writing there fills the system disk.
          mountpoint -q "${SH}target" || return 0
          grep -qx "${SH}1" "${SH}target/.gryonix-backup-drive" 2>/dev/null || return 0
          printf '%s\n' "${SH}target"
        }

        # Mounts a drive plugged in after boot, through systemd.
        gd_drive_ready() {
          local target
          target="${SH}(gd_drive_target "${SH}1")"
          if [ -z "${SH}target" ] && [ -b "/dev/disk/by-uuid/${SH}1" ]; then
            target="${SH}(gd_drive_fstab "${SH}1")"
            case "${SH}target" in
              "${SH}DRIVEROOT"/*)
                systemctl start "${SH}(systemd-escape -p --suffix=mount "${SH}target")" >/dev/null 2>&1 || true ;;
            esac
            target="${SH}(gd_drive_target "${SH}1")"
          fi
          printf '%s' "${SH}target"
        }

        # The drive's name: the last part of its mount point.
        gd_drive_name() {
          local target
          target="${SH}(gd_drive_fstab "${SH}1")"
          if [ -n "${SH}target" ]; then printf '%s' "${SH}{target##*/}"; else printf '%s' "${SH}1"; fi
        }

        # Why a write to a drive failed.
        gd_drive_why() {
          local avail
          case ",${SH}(findmnt -no OPTIONS --target "${SH}1" 2>/dev/null || true)," in
            *,ro,*) echo "the drive went read-only; check it"; return 0 ;;
          esac
          avail="${SH}(df -B1 --output=avail "${SH}1" 2>/dev/null | tail -n 1 | tr -cd '0-9')"
          if [ "${SH}{avail:-0}" -lt 1048576 ]; then
            echo "the drive is full"
          else
            echo "the drive could not be written"
          fi
        }

        # Copies one archive to a drive, encrypting it when asked.
        gd_drive_write() {
          local src="${SH}1" dest="${SH}2" pass=""
          GD_DRIVE_ERROR=""
          if [ "${SH}{dest%.gpg}" = "${SH}dest" ] || [ "${SH}{src%.gpg}" != "${SH}src" ]; then
            cp "${SH}src" "${SH}dest" 2>/dev/null && return 0
            GD_DRIVE_ERROR="${SH}(gd_drive_why "${SH}{dest%/*}")"
            return 1
          fi
          pass="${SH}GD_PASS"
          [ -n "${SH}pass" ] || pass="${SH}(cat "${SH}PASSFILE" 2>/dev/null || true)"
          if [ -z "${SH}pass" ]; then
            GD_DRIVE_ERROR="no backup passphrase is stored for encrypted copies"
            return 1
          fi
          printf '%s' "${SH}pass" | gpg --batch --quiet --yes --symmetric \
               --cipher-algo AES256 --passphrase-fd 0 --pinentry-mode loopback \
               --output "${SH}dest" "${SH}src" 2>/dev/null && return 0
          GD_DRIVE_ERROR="${SH}(gd_drive_why "${SH}{dest%/*}")"
          return 1
        }

        # Keeps the newest RETENTION copies in one folder.
        gd_drive_rotate() {
          { ls -1t "${SH}1" 2>/dev/null || true; } | tail -n +${SH}((RETENTION + 1)) \
            | while IFS= read -r old; do rm -rf -- "${SH}{1:?}/${SH}old"; done || true
        }

        # What the last drive copy did, read by show-drives.
        gd_drive_status() {
          install -d -m 755 "${SH}{DRIVESTATUS%/*}" 2>/dev/null || true
          {
            echo "DRIVE_AT=${SH}(date +%s)"
            if [ -z "${SH}1" ]; then echo "DRIVE_OK=1"; else echo "DRIVE_OK=0"; fi
            echo "DRIVE_ERROR='${SH}(printf '%s' "${SH}1" | tr '\r\n\t' '   ' | tr -d "'" | sed 's/^ *//' | cut -c1-400)'"
          } > "${SH}DRIVESTATUS" 2>/dev/null || true
          chmod 644 "${SH}DRIVESTATUS" 2>/dev/null || true
        }

        # Records when a drive last took a copy.
        gd_drive_seen() {
          if { grep -v "^${SH}1 " "${SH}DRIVELAST" 2>/dev/null || true; echo "${SH}1 ${SH}(date +%s)"; } \
               > "${SH}DRIVELAST.new" 2>/dev/null; then
            mv -f "${SH}DRIVELAST.new" "${SH}DRIVELAST" 2>/dev/null || true
            chmod 644 "${SH}DRIVELAST" 2>/dev/null || true
          fi
        }

        # Writes one copy to one drive; prints where it landed, or why not.
        gd_drive_put() {
          local out="${SH}1" folder="${SH}2/${SH}3" name="${SH}4"
          if ! install -d -m 700 "${SH}folder" 2>/dev/null; then
            echo "the drive could not be written"
            return 1
          fi
          # Leftovers of a copy cut short when the drive was pulled.
          rm -f "${SH}folder"/.partial-* 2>/dev/null || true
          if gd_drive_write "${SH}out" "${SH}folder/.partial-${SH}name" \
             && mv -f "${SH}folder/.partial-${SH}name" "${SH}folder/${SH}name" 2>/dev/null; then
            sync -f "${SH}folder/${SH}name" 2>/dev/null || true
            chmod 600 "${SH}folder/${SH}name" 2>/dev/null || true
            gd_drive_rotate "${SH}folder"
            printf '%s\n' "${SH}folder/${SH}name"
            return 0
          fi
          rm -f "${SH}folder/.partial-${SH}name" 2>/dev/null || true
          printf '%s\n' "${SH}{GD_DRIVE_ERROR:-the drive could not be written}"
          return 1
        }

        # **A copy of each archive on every chosen USB drive.** A missing
        # or full drive never fails the backup; it is recorded instead.
        gd_drive_copy() {
          local out="${SH}1" service="${SH}2" name uuid target landed first="" failed=""
          load_drives
          if [ -z "${SH}DRIVES" ] || [ "${SH}DRIVE_MODE" = "local" ]; then return 0; fi
          name="${SH}(basename "${SH}out")"
          if [ "${SH}DRIVE_ENCRYPT" -eq 1 ] && [ "${SH}{name%.gpg}" = "${SH}name" ]; then name="${SH}name.gpg"; fi
          for uuid in ${SH}DRIVES; do
            target="${SH}(gd_drive_ready "${SH}uuid")"
            if [ -z "${SH}target" ]; then
              failed="${SH}failed ${SH}(gd_drive_name "${SH}uuid"): not connected;"
              continue
            fi
            if landed="${SH}(gd_drive_put "${SH}out" "${SH}target" "${SH}service" "${SH}name")"; then
              printf '%s %s %s\n' 'GRYONIXNEXUS_DRIVE_COPY' "${SH}uuid" "${SH}landed"
              [ -n "${SH}first" ] || first="${SH}landed"
              gd_drive_seen "${SH}uuid"
            else
              failed="${SH}failed ${SH}{target##*/}: ${SH}landed;"
            fi
          done
          gd_drive_status "${SH}failed"
          # Drives only: the local archive goes once a drive holds it.
          if [ "${SH}DRIVE_MODE" = "drive" ] && [ -n "${SH}first" ]; then
            rm -f "${SH}out"
            printf '%s %s %s\n' 'GRYONIXNEXUS_BACKUP_DONE' \
              "${SH}(stat -c %s "${SH}first" 2>/dev/null || echo 0)" "${SH}first"
          fi
          return 0
        }

        # Copies the newest archive an external tool wrote.
        gd_drive_copy_newest() {
          local newest
          newest="${SH}({ ls -1t "${SH}1/${SH}2"-*.tar.gz 2>/dev/null || true; } | head -n 1)"
          [ -n "${SH}newest" ] || return 0
          gd_drive_copy "${SH}newest" "${SH}2"
          # Drives only: the unpacked folder leaves with its archive.
          if [ ! -e "${SH}newest" ] && [ -d "${SH}{newest%.tar.gz}" ]; then rm -rf "${SH}{newest%.tar.gz}"; fi
        }

        do_set_drives() {
          local mode="${SH}{1:-both}" encrypt="${SH}{2:-1}" checked="" uuid
          shift 2 || true
          case "${SH}mode" in
            both|local|drive) ;;
            *) echo "unsupported drive mode: ${SH}{mode}" >&2; exit 2 ;;
          esac
          case "${SH}encrypt" in
            0|1) ;;
            *) echo "invalid encryption flag: ${SH}{encrypt}" >&2; exit 2 ;;
          esac
          for uuid in "${SH}@"; do
            case "${SH}uuid" in
              ''|*[!0-9A-Fa-f-]*) echo "invalid drive id: ${SH}{uuid}" >&2; exit 2 ;;
            esac
            checked="${SH}checked ${SH}uuid"
          done
          install -d -m 755 "${SH}(dirname "${SH}DRIVECONF")"
          cat > "${SH}DRIVECONF" <<EOF_DRIVES
        DRIVE_MODE=${SH}mode
        DRIVE_ENCRYPT=${SH}encrypt
        DRIVES='${SH}{checked# }'
        EOF_DRIVES
          chmod 644 "${SH}DRIVECONF"
          # A newly chosen drive counts from now.
          for uuid in ${SH}checked; do
            grep -q "^${SH}uuid " "${SH}DRIVELAST" 2>/dev/null || gd_drive_seen "${SH}uuid"
          done
        }

        # Settings, each drive's state and the last copy, in one read.
        do_show_drives() {
          local uuid target size avail
          load_drives
          printf 'DRIVE_MODE=%s\nDRIVE_ENCRYPT=%s\nDRIVES=%s\n' "${SH}DRIVE_MODE" "${SH}DRIVE_ENCRYPT" "${SH}DRIVES"
          if [ -s "${SH}PASSFILE" ]; then echo 'DRIVE_PASS=1'; else echo 'DRIVE_PASS=0'; fi
          for uuid in ${SH}DRIVES; do
            target="${SH}(gd_drive_target "${SH}uuid")"
            size=0
            avail=0
            if [ -n "${SH}target" ]; then
              read -r size avail < <(df -B1 --output=size,avail "${SH}target" 2>/dev/null | tail -n 1) || true
              printf 'DRIVE=%s 1 %s %s %s\n' "${SH}uuid" "${SH}{size:-0}" "${SH}{avail:-0}" "${SH}target"
            else
              printf 'DRIVE=%s 0 0 0 %s\n' "${SH}uuid" "${SH}(gd_drive_fstab "${SH}uuid")"
            fi
          done
          [ -s "${SH}DRIVESTATUS" ] && cat "${SH}DRIVESTATUS"
          return 0
        }

        # --- per-service locking (see LockSections) --------------------------

        @LOCK_HELPER@

        # --- helpers shared by every generated service body -----------------

        gd_compose_stop() {
          local project="${SH}1"
          shift
          docker compose -p "${SH}project" stop "${SH}@" >/dev/null 2>&1 || true
        }

        gd_compose_start() {
          local project="${SH}1"
          shift
          docker compose -p "${SH}project" start "${SH}@" >/dev/null 2>&1 || true
        }

        # Container id of one compose service; empty when it is not running.
        gd_container() {
          docker compose -p "${SH}1" ps -q "${SH}2" 2>/dev/null | head -n 1
        }

        # A tar of a live database directory is a corrupt backup, so the
        # database is dumped through its own client instead. The credentials
        # come from the container's OWN environment — compose already put them
        # there — because passing them from here would place the password in
        # the argv of `docker exec`, readable by every account on the host.
        gd_dump_postgres() {
          local cid
          cid="${SH}(gd_container "${SH}1" "${SH}2")"
          if [ -z "${SH}cid" ]; then
            echo "the ${SH}1 database container is not running" >&2
            return 1
          fi
          if ! docker exec "${SH}cid" sh -c \
               'PGPASSWORD="${SH}POSTGRES_PASSWORD" exec pg_dump --clean --if-exists -U "${SH}POSTGRES_USER" -d "${SH}POSTGRES_DB"' \
               > "${SH}3"; then
            echo "the ${SH}1 database dump failed" >&2
            return 1
          fi
          [ -s "${SH}3" ] || { echo "the ${SH}1 database dump is empty" >&2; return 1; }
        }

        # --single-transaction is what makes a dump of a RUNNING InnoDB
        # database trustworthy: one consistent snapshot, no instance-wide lock.
        # mariadb-dump on current images, mysqldump on older ones.
        #
        # A fourth argument names the database explicitly, for a service that
        # keeps several in one engine and whose container therefore sets no
        # MYSQL_DATABASE at all; without it the container's own variable is
        # used, as it always was. Only the NAME travels here — the password is
        # still read inside the container, never put in the argv of docker exec
        # where /proc hands it to every account on the host.
        gd_dump_mysql() {
          local cid
          cid="${SH}(gd_container "${SH}1" "${SH}2")"
          if [ -z "${SH}cid" ]; then
            echo "the ${SH}1 database container is not running" >&2
            return 1
          fi
          if ! docker exec "${SH}cid" sh -c \
               'if command -v mariadb-dump >/dev/null 2>&1; then D=mariadb-dump; else D=mysqldump; fi; MYSQL_PWD="${SH}MYSQL_ROOT_PASSWORD" exec "${SH}D" --single-transaction --quick -u root "${SH}{1:-${SH}MYSQL_DATABASE}"' \
               sh "${SH}{4:-}" > "${SH}3"; then
            echo "the ${SH}1 database dump failed" >&2
            return 1
          fi
          [ -s "${SH}3" ] || { echo "the ${SH}1 database dump is empty" >&2; return 1; }
        }

        # Keeps the newest RETENTION archives of one service — encrypted and
        # plain together, they are one series. The pipeline is guarded: with
        # fewer archives than RETENTION `ls` finds nothing to list and would
        # fail the whole run under pipefail, which is every first run.
        gd_rotate() {
          { ls -1t "${SH}1/${SH}2"-*.tar.gz "${SH}1/${SH}2"-*.tar.gz.gpg 2>/dev/null || true; } \
            | tail -n +${SH}((RETENTION + 1)) | xargs -r rm -f
        }

        # Encrypt (or not), put the archive in place, rotate, announce.
        gd_finish() {
          local name="${SH}1" dir="${SH}2" plain="${SH}3" work="${SH}4" out=""
          if [ ! -s "${SH}plain" ]; then
            rm -rf "${SH}work"
            echo "the ${SH}name archive is empty" >&2
            return 1
          fi
          if [ "${SH}GD_ENCRYPT" -eq 1 ]; then
            out="${SH}dir/${SH}(basename "${SH}plain").gpg"
            if ! printf '%s' "${SH}GD_PASS" | gpg --batch --quiet --yes --symmetric \
                 --cipher-algo AES256 --passphrase-fd 0 --pinentry-mode loopback \
                 --output "${SH}out" "${SH}plain"; then
              rm -rf "${SH}work"
              echo "could not encrypt the ${SH}name backup" >&2
              return 1
            fi
          else
            out="${SH}dir/${SH}(basename "${SH}plain")"
            mv "${SH}plain" "${SH}out"
          fi
          # The plain archive never outlives the encrypted one.
          rm -rf "${SH}work"
          chmod 600 "${SH}out"
          chown "${SH}OWNER" "${SH}out" 2>/dev/null || true
          gd_rotate "${SH}dir" "${SH}name"
          # A streamed command carries no exit status back to the app, so the
          # archive announces itself: marker, size in bytes, path.
          printf '%s %s %s\n' '$BACKUP_DONE_MARKER' \
            "${SH}(stat -c %s "${SH}out" 2>/dev/null || echo 0)" "${SH}out"
          # And then it leaves the machine, if a destination was chosen. After
          # the marker on purpose: the archive exists and is announced whatever
          # the far side does.
          gd_ship "${SH}out" "${SH}name"
          # A copy on each USB drive, after the far side.
          gd_drive_copy "${SH}out" "${SH}name"
        }

        # --- per-service bodies (generated from each service's BackupSpec) ---

        @FUNCTIONS@

        # The ONE dispatch both callers go through: the timer's `run` and the
        # app's `backup`. Two copies of these bodies is exactly the drift this
        # wrapper exists to prevent.
        gd_run_service() {
          case "${SH}1" in
        @DISPATCH@
            *) echo "unsupported service: ${SH}1" >&2; return 2 ;;
          esac
        }

        # Whether a run of this service encrypts unless the caller says
        # otherwise. Secret stores yes; bulk media no — GPG over a photo
        # library costs hours of CPU on a Raspberry Pi.
        gd_default_encrypt() {
          case "${SH}1" in
        @ENCRYPT@
            *) echo 0 ;;
          esac
        }

        do_delete() {
          local path="${SH}{1:-}"
          # The path must sit inside a backup directory this deployment owns.
          # Without the check a whitelisted wrapper would delete ANY file.
          case "${SH}path" in
            *..*) echo "invalid path: ${SH}{path}" >&2; exit 2 ;;
          esac
          case "${SH}path" in
            ${if (dirCases.isEmpty()) "\"\"" else dirCases}) ;;
            "${SH}DRIVEROOT"/*/*/*) ;;
            *) echo "path outside the backup directories: ${SH}{path}" >&2; exit 2 ;;
          esac
          [ -e "${SH}path" ] || { echo "no such backup: ${SH}{path}" >&2; exit 2; }
          rm -rf "${SH}path"
        }

        do_run() {
          load_config
          local failed=""
          for svc in ${SH}SERVICES; do
            # Each service runs in its own subshell, and the `||` keeps errexit
            # from firing on a failure: an unattended run must not let one
            # broken service cancel the backups of every service after it.
            (
              GD_ENCRYPT="${SH}(gd_default_encrypt "${SH}svc")"
              GD_PASS=""
              if [ "${SH}GD_ENCRYPT" -eq 1 ]; then
                # Unattended, so there is nobody to ask: the stored passphrase
                # is the only source. Without it the service refuses rather
                # than quietly writing its secrets out in the clear.
                if [ ! -s "${SH}PASSFILE" ]; then
                  echo "no backup passphrase stored for ${SH}svc" >&2
                  exit 1
                fi
                GD_PASS="${SH}(cat "${SH}PASSFILE")"
              fi
              gd_run_service "${SH}svc"
            ) || failed="${SH}failed ${SH}svc"
          done
          if [ -n "${SH}failed" ]; then
            echo "backup failed for:${SH}failed" >&2
            exit 1
          fi
        }

        # One service, on demand. Same bodies the timer runs; the only
        # difference is where the passphrase comes from.
        do_backup() {
          local svc="${SH}{1:-}"
          shift || true
          load_config
          GD_ENCRYPT="${SH}(gd_default_encrypt "${SH}svc")"
          for arg in "${SH}@"; do
            case "${SH}arg" in
              --encrypt) GD_ENCRYPT=1 ;;
              --no-encrypt) GD_ENCRYPT=0 ;;
              *) echo "unsupported option: ${SH}{arg}" >&2; exit 2 ;;
            esac
          done
          if [ "${SH}GD_ENCRYPT" -eq 1 ]; then
            # On stdin, never argv. A terminal means nobody piped anything in,
            # and reading would hang forever.
            if [ ! -t 0 ]; then GD_PASS="${SH}(cat)"; fi
            # No passphrase given: fall back to the stored one, so an
            # encrypted run is possible without re-typing it.
            if [ -z "${SH}GD_PASS" ] && [ -s "${SH}PASSFILE" ]; then GD_PASS="${SH}(cat "${SH}PASSFILE")"; fi
            if [ -z "${SH}GD_PASS" ]; then
              echo "an encrypted backup needs a passphrase on stdin" >&2
              exit 2
            fi
          fi
          gd_run_service "${SH}svc"
        }

        # What a backup of this service would cost, in bytes, and what the
        # backup filesystem still has free. Read-only, and the only reason the
        # app can warn BEFORE starting an hours-long run.
        do_estimate() {
          local svc="${SH}{1:-}" dir="" total=0 free="" sz=""
          local -a paths=()
          case "${SH}svc" in
        @ESTIMATE@
            *) echo "unsupported service: ${SH}{svc}" >&2; exit 2 ;;
          esac
          install -d -m 750 "${SH}dir"
          local p
          for p in "${SH}{paths[@]}"; do
            [ -e "${SH}p" ] || continue
            sz="${SH}(du -sb "${SH}p" 2>/dev/null | cut -f1)" || sz=""
            total=${SH}((total + ${SH}{sz:-0}))
          done
          free="${SH}(df -B1 --output=avail "${SH}dir" 2>/dev/null | tail -n 1 | tr -cd '0-9')"
          printf '%s %s %s\n' '$ESTIMATE_MARKER' "${SH}total" "${SH}{free:-0}"
        }

        do_set_schedule() {
        @SCHEDULE_COMMENT@
          local schedule="${SH}{1:-off}" retention="${SH}{2:-${access.keptBackups}}"
          shift 2 || true
          local services="${SH}*"
        @SCHEDULE_PARSER@
          case "${SH}retention" in
            ''|*[!0-9]*) echo "invalid retention: ${SH}{retention}" >&2; exit 2 ;;
          esac
          [ "${SH}retention" -ge 1 ] || { echo "invalid retention: ${SH}{retention}" >&2; exit 2; }
          # Only services this wrapper knows about may end up in the config.
          local checked=""
          for svc in ${SH}services; do
            for known in ${if (allIDs.isEmpty()) "''" else allIDs}; do
              if [ "${SH}svc" = "${SH}known" ]; then checked="${SH}checked ${SH}svc"; fi
            done
          done
          install -d -m 755 "${SH}(dirname "${SH}CONFIG")"
          cat > "${SH}CONFIG" <<EOF_CONF
        SCHEDULE=${SH}schedule
        RETENTION=${SH}retention
        SERVICES='${SH}{checked# }'
        EOF_CONF
          # World-readable on purpose: it holds no secrets (the passphrase is
          # a separate 0600 file) and the app reads it without sudo.
          chmod 644 "${SH}CONFIG"
        @TIMER_ACTIVATION@
        }

        do_set_passphrase() {
          install -d -m 755 "${SH}(dirname '$PASSPHRASE_PATH')"
          # From stdin, never argv: argv is world-readable in /proc.
          local pass
          pass="${SH}(cat)"
          if [ -z "${SH}pass" ]; then echo "an empty passphrase is refused" >&2; exit 2; fi
          ( umask 077 && printf '%s' "${SH}pass" > '$PASSPHRASE_PATH' )
          chmod 600 '$PASSPHRASE_PATH'
        }

        case "${SH}ACTION" in
          delete) do_delete "${SH}{2:-}" ;;
          run) do_run ;;
          backup) shift; do_backup "${SH}@" ;;
          estimate) do_estimate "${SH}{2:-}" ;;
          set-schedule) shift; do_set_schedule "${SH}@" ;;
          set-passphrase) do_set_passphrase ;;
          set-destination) shift; do_set_destination "${SH}@" ;;
          show-destination) do_show_destination ;;
          test-destination) do_test_destination ;;
          set-drives) shift; do_set_drives "${SH}@" ;;
          show-drives) do_show_drives ;;
          *) echo "unsupported action: ${SH}{ACTION}" >&2; exit 2 ;;
        esac
        echo '$DONE_MARKER'
        """.trimIndent().embedding(
            "LOCK_HELPER" to LockSections.helper,
            "FUNCTIONS" to functions.ifEmpty { ": # no backup-capable service is installed" },
            "DISPATCH" to dispatchArms,
            "ENCRYPT" to encryptArms,
            "ESTIMATE" to estimateArms,
            "SCHEDULE_COMMENT" to ScheduleSections.argumentComment,
            "SCHEDULE_PARSER" to ScheduleSections.parser,
            "TIMER_ACTIVATION" to ScheduleSections.timerActivation(
                timerName = TIMER_NAME,
                description = "gryonixNexus scheduled backups",
                delimiter = "EOF_TIMER"
            )
        )

        val unit = """
        [Unit]
        Description=gryonixNexus scheduled backup run
        After=docker.service
        [Service]
        Type=oneshot
        ExecStart=$SCRIPT_PATH run
        """.trimIndent()

        return """
        log "${L10nScripts.backupControlWrapperLog(language)}"
        @SCRIPT_FILE@
        chmod 750 '$SCRIPT_PATH'
        # 755: the schedule config inside is read by the app without sudo; the
        # passphrase file next to it carries its own 0600.
        install -d -m 755 $CONFIG_DIRECTORY
        @UNIT_FILE@
        systemctl daemon-reload
        # The timer itself is created only when the user turns the schedule on.
        """.trimIndent().embedding(
            "SCRIPT_FILE" to BashSections.writeFile(SCRIPT_PATH, script, "EOF_BACKUP_CTL"),
            "UNIT_FILE" to BashSections.writeFile(
                "/etc/systemd/system/$SERVICE_NAME", unit, "EOF_AUTOBACKUP_UNIT"
            )
        )
    }
}
