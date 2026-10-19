package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.ArchiveBackupPlan
import com.skaymer.gryonixnexus.catalog.BackupDatabase
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRuntime
import com.skaymer.gryonixnexus.catalog.embedding
import com.skaymer.gryonixnexus.core.NetworkAddress
import com.skaymer.gryonixnexus.core.ServerRole
import com.skaymer.gryonixnexus.core.WireGuardDefaults

internal object DashboardAccessSections {
    /** Root-owned wrapper that starts/stops/restarts a single container */
    const val CONTAINER_CONTROL_SCRIPT_PATH = "/opt/gryonixnexus-container-ctl.sh"

    /** Root-owned wrapper that restores one service from one backup file */
    const val RESTORE_SCRIPT_PATH = "/opt/gryonixnexus-restore.sh"

    // MARK: - Control user + app SSH key

    /** Creates the dedicated control (bot) user if missing */
    fun controlUser(access: DashboardAccessInput, language: AppLanguage): String {
        val user = access.sshUser
        if (!access.createUser) {
            return """
            log "${L10nScripts.dashboardExistingUserLog(language, user)}"
            id -u '$user' >/dev/null 2>&1 || fail "${L10nScripts.existingUserMissing(language, user)}"
            """.trimIndent()
        }
        return """
        log "${L10nScripts.dashboardCreateUserLog(language, user)}"
        if ! id -u '$user' >/dev/null 2>&1; then
          useradd --create-home --shell /bin/bash '$user'
        fi
        passwd -l '$user' >/dev/null 2>&1 || true
        """.trimIndent()
    }

    fun authorizedKey(access: DashboardAccessInput, language: AppLanguage): String {
        val user = access.sshUser
        return """
        log "${L10nScripts.dashboardSSHKeyLog(language, user)}"
        APP_KEY='${access.appPublicKey}'
        USER_HOME="${SH}(getent passwd '$user' | cut -d: -f6)"
        [ -n "${SH}USER_HOME" ] || fail "${L10nScripts.homeDirectoryFail(language, user)}"
        install -d -m 700 -o '$user' "${SH}USER_HOME/.ssh"
        touch "${SH}USER_HOME/.ssh/authorized_keys"
        grep -qxF "${SH}APP_KEY" "${SH}USER_HOME/.ssh/authorized_keys" || echo "${SH}APP_KEY" >> "${SH}USER_HOME/.ssh/authorized_keys"
        chmod 600 "${SH}USER_HOME/.ssh/authorized_keys"
        chown '$user' "${SH}USER_HOME/.ssh" "${SH}USER_HOME/.ssh/authorized_keys"
        """.trimIndent()
    }

    fun revokeInstallKey(access: DashboardAccessInput, language: AppLanguage): String = """
        log "${L10nScripts.revokeInstallKeyLog(language)}"
        APP_KEY='${access.appPublicKey}'
        CONTROL_USER='${access.sshUser}'
        revoke_key_for() {
          # Explicit ifs rather than `[ … ] && …` chains: this runs under
          # `set -e`, where a chain whose test fails carries that status on.
          if [ "${SH}1" = "${SH}CONTROL_USER" ]; then return 0; fi
          home_dir="${SH}(getent passwd "${SH}1" | cut -d: -f6 || true)"
          if [ -z "${SH}home_dir" ]; then return 0; fi
          keys="${SH}home_dir/.ssh/authorized_keys"
          if [ ! -f "${SH}keys" ]; then return 0; fi
          if ! grep -qxF "${SH}APP_KEY" "${SH}keys"; then return 0; fi
          grep -vxF "${SH}APP_KEY" "${SH}keys" > "${SH}keys.gryonixnexus" || true
          mv "${SH}keys.gryonixnexus" "${SH}keys"
          chmod 600 "${SH}keys"
          # The rewrite runs as root, so the file it leaves behind is
          # root-owned — and sshd opens authorized_keys AS THE ACCOUNT, not as
          # root. A root-owned 0600 file is unreadable to it ("Could not open
          # user 'x' authorized keys … Permission denied"), so revoking the
          # app's key takes EVERY OTHER key on that account with it: the
          # owner's own key stops working at the last step of an install that
          # just reported success, and a `sudo -n` install locks them out of
          # the account they installed from. Ownership has to be put back
          # explicitly — the install path above chowns for the same reason.
          chown "${SH}1" "${SH}keys"
          echo "${L10nScripts.revokeInstallKeyDone(language)}"
        }
        # SUDO_USER is set when the app reached root through `sudo -n <user>`;
        # a direct root login leaves it empty and only root is cleaned.
        revoke_key_for root
        if [ -n "${SH}{SUDO_USER:-}" ] && [ "${SH}{SUDO_USER}" != "root" ]; then
          revoke_key_for "${SH}SUDO_USER"
        fi
        """.trimIndent()

    // MARK: - sudoers

    fun sudoers(lines: List<String>, language: AppLanguage): String = """
        log "${L10nScripts.dashboardSudoersLog(language)}"
        cat > /etc/sudoers.d/gryonixnexus-control.staged <<'EOF_SUDOERS'
        # Managed by gryonixNexus — Server Dashboard command whitelist.
        # sudo matches these commands verbatim; do not add flags client-side.
        @LINES@
        EOF_SUDOERS
        chmod 440 /etc/sudoers.d/gryonixnexus-control.staged
        visudo -cf /etc/sudoers.d/gryonixnexus-control.staged || { rm -f /etc/sudoers.d/gryonixnexus-control.staged; fail "${L10nScripts.sudoersRejected(language)}"; }
        mv /etc/sudoers.d/gryonixnexus-control.staged /etc/sudoers.d/gryonixnexus-control
        """.trimIndent().embedding("LINES" to lines.joinToString("\n"))

    /** The agent's package updater */
    const val SYSTEM_CONTROL_SCRIPT_PATH = "/opt/gryonixnexus-system-ctl.sh"

    /** VPS whitelist */
    fun vpsSudoersLines(user: String, wgInterface: String): List<String> = listOf(
        "$user ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart wg-quick@$wgInterface",
        "$user ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart sshd",
        "$user ALL=(ALL) NOPASSWD: /usr/bin/systemctl reboot",
        "$user ALL=(ALL) NOPASSWD: /usr/bin/systemctl poweroff",
        "$user ALL=(ALL) NOPASSWD: $SYSTEM_CONTROL_SCRIPT_PATH",
        "$user ALL=(ALL) NOPASSWD: /sbin/sysctl net.ipv4.ip_forward",
        "$user ALL=(ALL) NOPASSWD: /usr/bin/wg show",
        // Full cleanup of the relay — the wrapper validates its target.
        "$user ALL=(ALL) NOPASSWD: ${UninstallSections.SCRIPT_PATH}",
        "$user ALL=(ALL) NOPASSWD: ${AgentBootstrapSections.SCRIPT_PATH}",
        "$user ALL=(ALL) NOPASSWD: ${AgentBootstrapSections.BRIDGE_SUDOERS_TARGET}",
        "$user ALL=(ALL) NOPASSWD: ${AgentBootstrapSections.PAIR_CODE_SUDOERS_TARGET}"
    )

    fun servicesHostSudoersLines(access: DashboardAccessInput, wgInterface: String,
                                 includeWireGuard: Boolean, services: List<ManagedService>,
                                 serviceContext: ServiceContext): List<String> {
        val user = access.sshUser
        val lines = mutableListOf(
            "$user ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart sshd",
            "$user ALL=(ALL) NOPASSWD: /usr/bin/systemctl reboot",
            "$user ALL=(ALL) NOPASSWD: /usr/bin/systemctl poweroff",
            "$user ALL=(ALL) NOPASSWD: $SYSTEM_CONTROL_SCRIPT_PATH"
        )
        if (includeWireGuard) {
            lines.add(0, "$user ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart wg-quick@$wgInterface")
            lines.add("$user ALL=(ALL) NOPASSWD: /usr/sbin/sysctl net.ipv4.ip_forward")
            lines.add("$user ALL=(ALL) NOPASSWD: /usr/bin/wg show")
        }
        if (services.any { it.runtime is ServiceRuntime.Docker }) {
            lines.add("$user ALL=(ALL) NOPASSWD: /usr/bin/docker ps")
            lines.add("$user ALL=(ALL) NOPASSWD: $CONTAINER_CONTROL_SCRIPT_PATH")
        }
        // Service removal / full cleanup — the wrapper validates its targets.
        lines.add("$user ALL=(ALL) NOPASSWD: ${UninstallSections.SCRIPT_PATH}")
        lines.add("$user ALL=(ALL) NOPASSWD: ${AgentBootstrapSections.SCRIPT_PATH}")
        lines.add("$user ALL=(ALL) NOPASSWD: ${AgentBootstrapSections.BRIDGE_SUDOERS_TARGET}")
        lines.add("$user ALL=(ALL) NOPASSWD: ${AgentBootstrapSections.PAIR_CODE_SUDOERS_TARGET}")
        if (services.any { it.actions(serviceContext).backup != null }) {
            lines.add("$user ALL=(ALL) NOPASSWD: ${BackupControlSections.SCRIPT_PATH}")
        }
        if (UpdateControlSections.isUsed(services, serviceContext)) {
            lines.add("$user ALL=(ALL) NOPASSWD: ${UpdateControlSections.SCRIPT_PATH}")
        }
        for (service in services) {
            for (line in service.sudoersLines(serviceContext)) {
                if (line !in lines) lines.add(line)
            }
        }
        return lines
    }

    /** Installs the per-container control wrapper on a docker host */
    fun containerControlWrapper(language: AppLanguage): String {
        val script = """
        #!/bin/bash
        # Managed by gryonixNexus — per-container control for the Server Dashboard.
        # Usage: gryonixnexus-container-ctl.sh <start|stop|restart> <container>
        # Whitelisted once in sudoers; validates its arguments before docker.
        set -euo pipefail
        ACTION="${SH}{1:-}"
        NAME="${SH}{2:-}"
        case "${SH}ACTION" in
          start|stop|restart) ;;
          *) echo "unsupported action: ${SH}{ACTION}" >&2; exit 2 ;;
        esac
        case "${SH}NAME" in
          [A-Za-z0-9]*) ;;
          *) echo "invalid container name: ${SH}{NAME}" >&2; exit 2 ;;
        esac
        case "${SH}NAME" in
          *[!A-Za-z0-9_.-]*) echo "invalid container name: ${SH}{NAME}" >&2; exit 2 ;;
        esac
        exec docker "${SH}ACTION" "${SH}NAME"
        """.trimIndent()
        return """
        log "${L10nScripts.containerControlWrapperLog(language)}"
        @SCRIPT_FILE@
        chmod 750 '$CONTAINER_CONTROL_SCRIPT_PATH'
        """.trimIndent().embedding(
            "SCRIPT_FILE" to BashSections.writeFile(
                CONTAINER_CONTROL_SCRIPT_PATH, script, "EOF_CONTAINER_CTL"
            )
        )
    }

    /** Installs the restore wrapper on a docker host */
    fun restoreWrapper(access: DashboardAccessInput, context: MailContext,
                       language: AppLanguage): String {
        val serviceContext = context.serviceContext
        val restorable = context.allSelectedServices.filter {
            it.actions(serviceContext).restore != null
        }
        val services = restorable.map { it.id }.toSet()
        val archivePlans: List<Pair<String, ArchiveBackupPlan>> = restorable.mapNotNull {
            val target = it.actions(serviceContext).restore?.wrapperTarget ?: return@mapNotNull null
            val plan = it.actions(serviceContext).backup?.wrapper?.plan?.archive
                ?: return@mapNotNull null
            target to plan
        }
        val backupDirs = restorable.mapNotNull { it.actions(serviceContext).restore?.backupDir }
        val dirPatterns = (listOf("\"${SH}MAILCOW_BACKUPS\"/*", "\"${SH}VW_BACKUPS\"/*") +
            backupDirs.filter {
                it != access.mailcowBackupDir && it != access.vaultwardenBackupDir
            }.map { "\"$it\"/*" }).joinToString("|")
        val generatedHelpers = if (archivePlans.isEmpty()) "" else "\n" + RESTORE_HELPERS + "\n"
        val generatedArms = archivePlans.joinToString("\n\n") { (target, plan) ->
            restoreArchiveFunction(target, plan)
        }
        val generatedCases = archivePlans.joinToString("\n") { (target, _) ->
            "  $target) restore_${target.replace("-", "_")} ;;"
        }
        val usageTargets = restorable.joinToString("|") {
            it.actions(serviceContext).restore?.wrapperTarget ?: ""
        }

        val script = """
        #!/bin/bash
        # Managed by gryonixNexus — restore a service from a backup.
        # Usage: gryonixnexus-restore.sh <$usageTargets> <archive>
        #        GPG passphrase (encrypted archives only) on stdin.
        set -euo pipefail

        SERVICE="${SH}{1:-}"
        ARCHIVE="${SH}{2:-}"

        MAILCOW_PATH='${access.mailcowPath}'
        MAILCOW_BACKUPS='${access.mailcowBackupDir}'
        VW_CONTAINER='${access.vaultwardenContainer}'
        VW_DATA='${access.vaultwardenDataPath}'
        VW_BACKUPS='${access.vaultwardenBackupDir}'
        STAMP="${SH}(date +%Y%m%d-%H%M%S)"

        # The archive must sit inside a backup directory this deployment owns.
        # Without the check a whitelisted wrapper would happily unpack ANY
        # root-readable file over a service's data directory.
        case "${SH}ARCHIVE" in
          *..*) echo "invalid path: ${SH}{ARCHIVE}" >&2; exit 2 ;;
        esac
        case "${SH}ARCHIVE" in
          $dirPatterns) ;;
          *) echo "path outside the backup directories: ${SH}{ARCHIVE}" >&2; exit 2 ;;
        esac
        [ -e "${SH}ARCHIVE" ] || { echo "no such backup: ${SH}{ARCHIVE}" >&2; exit 2; }
        @HELPERS@
        restore_mailcow() {
          [ -x "${SH}MAILCOW_PATH/helper-scripts/backup_and_restore.sh" ] \
            || { echo "${L10nScripts.mailcowNotFound(language, access.mailcowPath)}" >&2; exit 1; }
          # mailcow's helper restores from a DIRECTORY inside its backup
          # location and picks it from a numbered menu. Stage the chosen backup
          # alone in a scratch location so that menu has exactly one entry.
          local stage="${SH}MAILCOW_BACKUPS/.restore-${SH}STAMP"
          mkdir -p "${SH}stage"
          chmod 0777 "${SH}stage"
          # shellcheck disable=SC2064
          trap "rm -rf '${SH}stage'" EXIT
          local plain="${SH}ARCHIVE"
          case "${SH}ARCHIVE" in
            *.gpg)
              plain="${SH}stage/.restore.tar.gz"
              gpg --batch --quiet --yes --decrypt --passphrase-fd 0 \
                  --pinentry-mode loopback --output "${SH}plain" "${SH}ARCHIVE" \
                || { echo "could not decrypt the backup (wrong passphrase?)" >&2; exit 1; }
              ;;
          esac
          if [ -d "${SH}ARCHIVE" ]; then
            cp -a "${SH}ARCHIVE" "${SH}stage/"
          else
            tar -xzf "${SH}plain" -C "${SH}stage"
            rm -f "${SH}stage/.restore.tar.gz"
          fi
          export MAILCOW_BACKUP_LOCATION="${SH}stage"
          # Bounded input, never `yes` (SIGPIPE under pipefail kills the pipeline).
          # The helper asks exactly two questions and then restores ONCE:
          # "Select a restore point" -> 1, the only staged backup; "Select a
          # dataset to restore" -> 0, the "[ 0 ] - all" entry, which expands to
          # every dataset in the backup (restore() loops over its arguments).
          # Feeding component indices one after another instead — as this did —
          # restores a SINGLE component and discards the rest of the input when
          # the helper exits, and which component index 1 refers to is whatever
          # `ls -f` returns first, so the survivor varied per run while the
          # wrapper still reported success.
          # The trailing "n" answers the vmail branch's "Force a resync now?";
          # extra input is harmless, a missing answer would depend on EOF.
          # Under `timeout` because an unrecognised prompt would otherwise wait
          # for a human that is never coming.
          printf '1\n0\nn\n' \
            | timeout 3600 "${SH}MAILCOW_PATH/helper-scripts/backup_and_restore.sh" restore
        }

        restore_vaultwarden() {
          local plain="${SH}ARCHIVE" tmp="" stage="" root="" previous="" saved=0
          case "${SH}ARCHIVE" in
            *.gpg)
              tmp="${SH}(mktemp -d)"
              # shellcheck disable=SC2064
              trap "rm -rf '${SH}tmp'" EXIT
              plain="${SH}tmp/restore.tar.gz"
              # --passphrase-fd 0: the secret arrives on stdin, never in argv.
              gpg --batch --quiet --yes --decrypt --passphrase-fd 0 \
                  --pinentry-mode loopback --output "${SH}plain" "${SH}ARCHIVE" \
                || { echo "could not decrypt the backup (wrong passphrase?)" >&2; exit 1; }
              ;;
          esac
          # Verify BEFORE touching live data: a truncated upload must not cost
          # the user the data they still have.
          tar -tzf "${SH}plain" >/dev/null 2>&1 \
            || { echo "the backup archive is not readable" >&2; exit 1; }
          # Unpacked aside; only the archived data directory is moved in.
          root="${SH}(tar -tzf "${SH}plain" | sed -n '1{s|^\./||;s|/*${SH}||;p;}')"
          case "/${SH}root/" in
            //|*/../*|*/./*) echo "the archive carries no vaultwarden data" >&2; exit 1 ;;
          esac
          mkdir -p "${SH}(dirname "${SH}VW_DATA")"
          stage="${SH}(mktemp -d "${SH}(dirname "${SH}VW_DATA")/.restore-XXXXXX")"
          # shellcheck disable=SC2064
          trap "rm -rf '${SH}stage' '${SH}tmp'" EXIT
          tar --numeric-owner -xzf "${SH}plain" -C "${SH}stage" \
            || { echo "the backup archive is not readable" >&2; exit 1; }
          if [ ! -d "${SH}stage/${SH}root" ] || [ -L "${SH}stage/${SH}root" ]; then
            echo "the archive carries no vaultwarden data" >&2
            exit 1
          fi
          docker stop "${SH}VW_CONTAINER" >/dev/null 2>&1 || true
          # The old data is moved aside, never deleted: if the move fails it is
          # the only way back, and the container must come up again either way.
          previous="${SH}{VW_DATA}.pre-restore-${SH}STAMP"
          if [ -d "${SH}VW_DATA" ]; then mv "${SH}VW_DATA" "${SH}previous"; saved=1; fi
          if mv "${SH}stage/${SH}root" "${SH}VW_DATA"; then
            if [ "${SH}saved" -eq 1 ]; then echo "previous data kept at ${SH}{previous}"; fi
          else
            echo "restore failed, rolling back to the previous data" >&2
            rm -rf "${SH}VW_DATA"
            if [ "${SH}saved" -eq 1 ]; then mv "${SH}previous" "${SH}VW_DATA"; fi
            docker start "${SH}VW_CONTAINER" >/dev/null 2>&1 || true
            exit 1
          fi
          docker start "${SH}VW_CONTAINER" >/dev/null 2>&1 || true
        }

        @ARMS@

        case "${SH}SERVICE" in
          mailcow) restore_mailcow ;;
          vaultwarden) restore_vaultwarden ;;
        @CASES@
          *) echo "unsupported service: ${SH}{SERVICE}" >&2; exit 2 ;;
        esac
        # A streamed command carries no exit status back to the app, so success
        # is announced with a fixed ASCII marker (never the localized line —
        # the app must not have to know which language the script was made in).
        echo "${L10nScripts.restoreDone(language)}"
        echo 'GRYONIXNEXUS_RESTORE_DONE'
        """.trimIndent().embedding(
            "HELPERS" to generatedHelpers,
            "ARMS" to generatedArms,
            "CASES" to generatedCases
        )
        val staging = mutableListOf<String>()
        if (ServiceID.MAILCOW in services) {
            val dir = uploadStagingDirectory(access.mailcowBackupDir)
            staging.add("""
            install -d '$dir'
            chgrp "${SH}(id -gn '${access.sshUser}')" '$dir'
            chmod 0770 '$dir'
            """.trimIndent())
        }
        if (ServiceID.VAULTWARDEN in services) {
            staging.add("install -d -o '${access.sshUser}' -m 0750 " +
                            "'${uploadStagingDirectory(access.vaultwardenBackupDir)}'")
        }
        for (dir in backupDirs) {
            if (dir == access.mailcowBackupDir || dir == access.vaultwardenBackupDir) continue
            staging.add("install -d -o '${access.sshUser}' -m 0750 " +
                            "'${uploadStagingDirectory(dir)}'")
        }
        return """
        log "${L10nScripts.restoreWrapperLog(language)}"
        @SCRIPT_FILE@
        chmod 750 '$RESTORE_SCRIPT_PATH'
        @STAGING@
        """.trimIndent().embedding(
            "SCRIPT_FILE" to BashSections.writeFile(RESTORE_SCRIPT_PATH, script, "EOF_RESTORE"),
            "STAGING" to staging.joinToString("\n")
        )
    }

    /** Helpers the generated restore arms share */
    private val RESTORE_HELPERS = """
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

        # Everything the project has, so the service is up again whatever the
        # restore did — the same guarantee the vaultwarden arm gives.
        gd_compose_start_all() {
          docker compose -p "${SH}1" start >/dev/null 2>&1 || true
        }

        gd_container() {
          docker compose -p "${SH}1" ps -q "${SH}2" 2>/dev/null | head -n 1
        }

        # A container that has just been started reports "up" long before its
        # engine accepts connections, and a dump loaded into it then fails with
        # a connection error that reads exactly like a corrupt backup.
        gd_db_wait() {
          local cid="${SH}1" engine="${SH}2" deadline
          deadline=${SH}(( ${SH}(date +%s) + 180 ))
          while [ "${SH}(date +%s)" -lt "${SH}deadline" ]; do
            case "${SH}engine" in
              postgres)
                if docker exec "${SH}cid" sh -c 'exec pg_isready -q -U "${SH}POSTGRES_USER"' >/dev/null 2>&1; then
                  return 0
                fi
                ;;
              mysql)
                if docker exec "${SH}cid" sh -c 'if command -v mariadb-admin >/dev/null 2>&1; then A=mariadb-admin; else A=mysqladmin; fi; MYSQL_PWD="${SH}MYSQL_ROOT_PASSWORD" exec "${SH}A" ping -u root' >/dev/null 2>&1; then
                  return 0
                fi
                ;;
            esac
            sleep 3
          done
          return 1
        }

        # The credentials come from the container's OWN environment (compose
        # put them there), never from the argv of docker exec — that is
        # world-readable through /proc on the host.
        gd_load_postgres() {
          local cid
          cid="${SH}(gd_container "${SH}1" "${SH}2")"
          if [ -z "${SH}cid" ]; then echo "the ${SH}1 database container is not running" >&2; return 1; fi
          if ! gd_db_wait "${SH}cid" postgres; then echo "the ${SH}1 database never became ready" >&2; return 1; fi
          if [ ! -s "${SH}3" ]; then echo "the archive carries no ${SH}1 database dump" >&2; return 1; fi
          # ON_ERROR_STOP: without it psql replays half a dump and still exits
          # 0, i.e. reports a restore that did not happen.
          if ! docker exec -i "${SH}cid" sh -c \
               'PGPASSWORD="${SH}POSTGRES_PASSWORD" exec psql -v ON_ERROR_STOP=1 -q -U "${SH}POSTGRES_USER" -d "${SH}POSTGRES_DB"' \
               < "${SH}3"; then
            echo "the ${SH}1 database could not be loaded" >&2
            return 1
          fi
        }

        # The fourth argument mirrors gd_dump_mysql: a service that keeps
        # several databases in one engine names each one, and the load has to
        # put each dump back where it came from.
        gd_load_mysql() {
          local cid
          cid="${SH}(gd_container "${SH}1" "${SH}2")"
          if [ -z "${SH}cid" ]; then echo "the ${SH}1 database container is not running" >&2; return 1; fi
          if ! gd_db_wait "${SH}cid" mysql; then echo "the ${SH}1 database never became ready" >&2; return 1; fi
          if [ ! -s "${SH}3" ]; then echo "the archive carries no ${SH}1 database dump" >&2; return 1; fi
          if ! docker exec -i "${SH}cid" sh -c \
               'if command -v mariadb >/dev/null 2>&1; then C=mariadb; else C=mysql; fi; MYSQL_PWD="${SH}MYSQL_ROOT_PASSWORD" exec "${SH}C" -u root "${SH}{1:-${SH}MYSQL_DATABASE}"' \
               sh "${SH}{4:-}" < "${SH}3"; then
            echo "the ${SH}1 database could not be loaded" >&2
            return 1
          fi
        }
        """.trimIndent()

    private fun restoreArchiveFunction(target: String, plan: ArchiveBackupPlan): String {
        val name = target.replace("-", "_")
        val project = plan.composeProject
        val lines = restoreUnpackLines(name, target, plan)
        if (plan.quiesceServices.isNotEmpty()) {
            val quiesce = plan.quiesceServices.joinToString(" ") { "'$it'" }
            lines.add("  gd_compose_stop '$project' $quiesce")
        }
        lines += restoreSwapLines(project, plan.dataPath, plan)
        lines += restoreDatabaseLines(project, plan)
        lines += restoreFinishLines(project, target)
        return lines.joinToString("\n")
    }

    private fun restoreUnpackLines(name: String, target: String, plan: ArchiveBackupPlan): MutableList<String> =
        mutableListOf(
            "restore_$name() {",
            "  local plain=\"${SH}ARCHIVE\" tmp=\"\" stage=\"\" previous=\"\" saved=0 rc=0",
            "  case \"${SH}ARCHIVE\" in",
            "    *.gpg)",
            "      tmp=\"${SH}(mktemp -d \"${SH}(dirname \"${SH}ARCHIVE\")/.gpg-XXXXXX\")\"",
            "      plain=\"${SH}tmp/restore.tar.gz\"",
            "      # --passphrase-fd 0: the secret arrives on stdin, never in argv.",
            "      if ! gpg --batch --quiet --yes --decrypt --passphrase-fd 0 \\",
            "           --pinentry-mode loopback --output \"${SH}plain\" \"${SH}ARCHIVE\"; then",
            "        rm -rf \"${SH}tmp\"",
            "        echo \"could not decrypt the backup (wrong passphrase?)\" >&2",
            "        exit 1",
            "      fi",
            "      ;;",
            "  esac",
            "  # Verified BEFORE anything is stopped: a truncated upload must not",
            "  # cost the user the data they still have.",
            "  if ! tar -tzf \"${SH}plain\" >/dev/null 2>&1; then",
            "    rm -rf \"${SH}tmp\"",
            "    echo \"the backup archive is not readable\" >&2",
            "    exit 1",
            "  fi",
            "  # Staged on the SERVICE's own filesystem, so putting the data back",
            "  # is a rename rather than a second copy of the whole directory.",
            "  stage=\"${SH}(mktemp -d '${plan.dataParent}/.restore-XXXXXX')\"",
            "  # shellcheck disable=SC2064",
            "  trap \"rm -rf '${SH}stage' '${SH}tmp'\" EXIT",
            "  tar --numeric-owner -xzf \"${SH}plain\" -C \"${SH}stage\"",
            "  if [ ! -d \"${SH}stage/${plan.dataSlot}\" ]; then",
            "    echo \"the archive carries no $target data\" >&2",
            "    exit 1",
            "  fi"
        )

    private fun restoreSwapLines(project: String, data: String, plan: ArchiveBackupPlan): List<String> =
        listOf(
            "  # The old data is moved aside, never deleted: if the move back",
            "  # fails it is the only way home.",
            "  previous='$data'\".pre-restore-${SH}STAMP\"",
            "  if [ -d '$data' ]; then mv '$data' \"${SH}previous\"; saved=1; fi",
            "  if mv \"${SH}stage/${plan.dataSlot}\" '$data'; then",
            "    if [ \"${SH}saved\" -eq 1 ]; then echo \"previous data kept at ${SH}{previous}\"; fi",
            "  else",
            "    echo \"restore failed, rolling back to the previous data\" >&2",
            "    rm -rf '$data'",
            "    if [ \"${SH}saved\" -eq 1 ]; then mv \"${SH}previous\" '$data'; fi",
            "    gd_compose_start_all '$project'",
            "    exit 1",
            "  fi"
        )

    private fun restoreDatabaseLines(project: String, plan: ArchiveBackupPlan): List<String> {
        val lines = mutableListOf<String>()
        for (database in plan.databases) {
            val helper = if (database.engine == BackupDatabase.Engine.POSTGRES) {
                "gd_load_postgres"
            } else {
                "gd_load_mysql"
            }
            lines += listOf(
                "  # The database container has to be up to take its dump back;",
                "  # the rest of the project stays down until it is loaded.",
                "  gd_compose_start '$project' '${database.service}'",
                "  $helper '$project' '${database.service}' " +
                    "\"${SH}stage/${ArchiveBackupPlan.DUMP_DIRECTORY_NAME}/${database.fileName}\"" +
                    (database.databaseName?.let { " '$it'" } ?: "") + " || rc=1"
            )
        }
        return lines
    }

    private fun restoreFinishLines(project: String, target: String): List<String> =
        listOf(
            "  # Up again on every path, restored or not.",
            "  gd_compose_start_all '$project'",
            "  if [ \"${SH}rc\" -ne 0 ]; then",
            "    echo \"the $target database could not be restored\" >&2",
            "    exit 1",
            "  fi",
            "}"
        )

    fun serviceBackupDirs(access: DashboardAccessInput, context: MailContext): String? {
        val serviceContext = context.serviceContext
        val dirs = context.allSelectedServices
            .mapNotNull { it.actions(serviceContext).backup?.listDirectory }
            .filter { it != access.mailcowBackupDir && it != access.vaultwardenBackupDir }
        if (dirs.isEmpty()) return null
        val lines = mutableListOf("log \"${L10nScripts.serviceBackupDirLog(context.language)}\"")
        for (root in dirs.mapNotNull { enclosingBackupRoot(it) }.toSet().sorted()) {
            lines.add("""
            install -d '$root'
            chgrp "${SH}(id -gn '${access.sshUser}')" '$root'
            chmod 0750 '$root'
            """.trimIndent())
        }
        for (dir in dirs) {
            lines.add("install -d -o '${access.sshUser}' -m 0750 '$dir'")
        }
        return lines.joinToString("\n")
    }

    fun uploadStagingDirectory(backupDir: String): String = "$backupDir/incoming"

    fun mailcowBackupWrapper(access: DashboardAccessInput, language: AppLanguage): String {
        val wrapper = """
        #!/bin/bash
        # Managed by gryonixNexus — mailcow backup wrapper for the Server Dashboard.
        # sudo strips env vars (env_reset): MAILCOW_BACKUP_LOCATION is set here.
        set -euo pipefail
        [ -x '${access.mailcowPath}/helper-scripts/backup_and_restore.sh' ] || { echo "${L10nScripts.mailcowNotFound(language, access.mailcowPath)}" >&2; exit 1; }
        export MAILCOW_BACKUP_LOCATION='${access.mailcowBackupDir}'
        mkdir -p "${SH}MAILCOW_BACKUP_LOCATION"
        # mailcow's backup_and_restore.sh requires the location to be writable
        # by others (its containers write as different UIDs); it aborts with
        # "is not write-able for others" otherwise. What keeps the archives out
        # of other accounts' reach is the 0750 on the ENCLOSING directory (see
        # enclosingBackupRoot) — this 0777 cannot be narrowed.
        chmod 0777 "${SH}MAILCOW_BACKUP_LOCATION"
        '${access.mailcowPath}/helper-scripts/backup_and_restore.sh' backup all
        # mailcow writes each backup as a DIRECTORY, which the dashboard cannot
        # download and share. Archive the newest one into a single .tar.gz next
        # to it (0644 like everything mailcow itself writes here — the 0777 on
        # this directory makes narrowing the files pointless; the enclosing
        # directory is what blocks other accounts), so "Share backup" has a
        # real file to hand off.
        NEWEST=""
        for d in "${SH}MAILCOW_BACKUP_LOCATION"/mailcow-*/; do
          [ -d "${SH}d" ] || continue
          if [ -z "${SH}NEWEST" ] || [ "${SH}d" -nt "${SH}NEWEST" ]; then NEWEST="${SH}d"; fi
        done
        if [ -n "${SH}NEWEST" ]; then
          base="${SH}(basename "${SH}NEWEST")"
          tar -czf "${SH}MAILCOW_BACKUP_LOCATION/${SH}base.tar.gz" -C "${SH}MAILCOW_BACKUP_LOCATION" "${SH}base"
          chmod 0644 "${SH}MAILCOW_BACKUP_LOCATION/${SH}base.tar.gz"
        fi
        # Rotation (as root — backups are root-owned): keep the newest
        # ${access.keptBackups} of each kind (directories and archives).
        ls -1dt "${SH}MAILCOW_BACKUP_LOCATION"/mailcow-*/ 2>/dev/null | tail -n +${access.keptBackups + 1} | xargs -r rm -rf
        ls -1t "${SH}MAILCOW_BACKUP_LOCATION"/mailcow-*.tar.gz 2>/dev/null | tail -n +${access.keptBackups + 1} | xargs -r rm -f
        """.trimIndent()
        return """
        log "${L10nScripts.mailcowBackupWrapperLog(language, access.mailcowPath)}"
        install -d '${access.mailcowPath}'
        @WRAPPER_FILE@
        chmod 750 '${access.mailcowPath}/bot-backup.sh'
        """.trimIndent().embedding(
            "WRAPPER_FILE" to BashSections.writeFile(
                "${access.mailcowPath}/bot-backup.sh", wrapper, "EOF_MC_BACKUP"
            )
        )
    }

    fun mailcowBackupDir(access: DashboardAccessInput, language: AppLanguage): String {
        val lines = mutableListOf("log \"${L10nScripts.mailcowBackupDirLog(language)}\"")
        enclosingBackupRoot(access.mailcowBackupDir)?.let { root ->
            lines.add("""
            install -d '$root'
            chgrp "${SH}(id -gn '${access.sshUser}')" '$root'
            chmod 0750 '$root'
            """.trimIndent())
        }
        lines.add("""
        install -d '${access.mailcowBackupDir}'
        chgrp "${SH}(id -gn '${access.sshUser}')" '${access.mailcowBackupDir}'
        chmod 750 '${access.mailcowBackupDir}'
        """.trimIndent())
        return lines.joinToString("\n")
    }

    fun enclosingBackupRoot(dir: String): String? {
        val path = dir.removeSuffix("/")
        val slash = path.lastIndexOf('/')
        if (slash < 0) return null
        val parent = path.substring(0, slash)
        if (!parent.drop(1).contains("/")) return null
        return parent
    }

    fun vaultwardenBackupDir(access: DashboardAccessInput, language: AppLanguage): String = """
        log "${L10nScripts.vaultwardenBackupDirLog(language)}"
        install -d -o '${access.sshUser}' -m 750 '${access.vaultwardenBackupDir}'
        """.trimIndent()

    // MARK: - Assembled sections

    /** Everything the VPS needs: app key + minimal sudoers */
    fun vpsSection(access: DashboardAccessInput, language: AppLanguage): String {
        val sections = mutableListOf(controlUser(access, language))
        if (access.createUser) sections.add(authorizedKey(access, language))
        sections.add(sudoers(
            vpsSudoersLines(access.sshUser, WireGuardDefaults.INTERFACE_NAME), language
        ))
        sections.add(UninstallSections.vpsWrapper(access, language))
        sections.add(AgentBootstrapSections.wrapper(access.sshUser))
        sections.add(passwordAuthClose(access, language))
        return sections.joinToString("\n\n")
    }

    fun servicesHostSection(access: DashboardAccessInput, context: MailContext,
                            includeWireGuard: Boolean): String {
        val serviceContext = context.serviceContext.copy(sshUser = access.sshUser)
        val services = context.allSelectedServices
        val language = context.language
        val sections = mutableListOf(controlUser(access, language))
        if (access.createUser) sections.add(authorizedKey(access, language))
        sections.add(sudoers(
            servicesHostSudoersLines(access, WireGuardDefaults.INTERFACE_NAME, includeWireGuard,
                                     services, serviceContext),
            language
        ))
        if (services.any { it.runtime is ServiceRuntime.Docker }) {
            sections.add(containerControlWrapper(language))
        }
        if (ServiceID.MAILCOW in context.input.services) {
            sections.add(mailcowBackupWrapper(access, language))
            sections.add(mailcowBackupDir(access, language))
        }
        if (ServiceID.VAULTWARDEN in context.input.services) {
            sections.add(vaultwardenBackupDir(access, language))
        }
        serviceBackupDirs(access, context)?.let { sections.add(it) }
        // Restore wrapper last: it needs every backup directory to exist.
        if (services.any { it.actions(serviceContext).restore != null }) {
            sections.add(restoreWrapper(access, context, language))
        }
        if (services.any { it.actions(serviceContext).backup != null }) {
            sections.add(BackupControlSections.wrapper(access, services, serviceContext, language))
            sections.add(BackupControlSections.passphraseSection(services, serviceContext))
        }
        if (UpdateControlSections.isUsed(services, serviceContext)) {
            sections.add(UpdateControlSections.wrapper(services, serviceContext, language))
        }
        sections.add(AgentBootstrapSections.wrapper(access.sshUser))
        sections.add(UninstallSections.servicesHostWrapper(access, context, includeWireGuard))
        return sections.joinToString("\n\n")
    }

    fun homeSection(access: DashboardAccessInput, context: MailContext): String {
        var section = servicesHostSection(access, context, includeWireGuard = true)
        val tunnelIP = context.server(ServerRole.VPS_RELAY)?.vpnAddress as? NetworkAddress.IPv4
        if (tunnelIP != null) {
            section += "\n\n" + sshdPenaltyExemption(tunnelIP.value, context.language)
        }
        section += "\n\n" + passwordAuthClose(access, context.language)
        return section
    }

    /** Writes an sshd_config drop-in exempting [sourceIP] from per-source penalties */
    fun sshdPenaltyExemption(sourceIP: String, language: AppLanguage): String = """
        if sshd -T 2>/dev/null | grep -qi '^persourcepenalties'; then
          log "${L10nScripts.sshdPenaltyExemptLog(language)}"
          install -d /etc/ssh/sshd_config.d
          printf 'PerSourcePenaltyExemptList %s\n' '$sourceIP' > /etc/ssh/sshd_config.d/60-gryonixnexus-tunnel.conf
          systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
        fi
        """.trimIndent()

    fun singleHostSection(access: DashboardAccessInput, context: MailContext): String =
        servicesHostSection(access, context, includeWireGuard = false) +
            "\n\n" + passwordAuthClose(access, context.language)

    // MARK: - Closing SSH password login

    /** Where the drop-in lives */
    const val PASSWORD_AUTH_DROP_IN_PATH = "/etc/ssh/sshd_config.d/10-gryonixnexus-no-password.conf"

    /** The drop-in's contents */
    val passwordAuthDropIn: String = """
        # Managed by gryonixNexus.
        #
        # Written only after the app key was proven present on the control user of
        # this host. Numbered 10 so it is obtained BEFORE 50-cloud-init.conf: sshd
        # keeps the FIRST value it sees for a keyword, and cloud images ship
        # PasswordAuthentication yes in that file.
        #
        # Remove this file and reload ssh to take passwords again.
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        """.trimIndent()

    /** Takes the drop-in off again and lets sshd accept passwords */
    fun passwordAuthCloseUninstallLines(indent: String): List<String> = listOf(
        "$indent# SSH password login comes back BEFORE the app key is stripped below,",
        "$indent# so this machine is never left with neither way in.",
        "${indent}rm -f $PASSWORD_AUTH_DROP_IN_PATH",
        "${indent}systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true",
    )

    fun passwordAuthClose(access: DashboardAccessInput, language: AppLanguage): String {
        if (!access.createUser) return ":"
        val staged = "$PASSWORD_AUTH_DROP_IN_PATH.staged"
        return """
        log "${L10nScripts.sshdPasswordCloseLog(language)}"
        SSHD_APP_KEY='${access.appPublicKey}'
        SSHD_USER_HOME="${SH}(getent passwd '${access.sshUser}' | cut -d: -f6 || true)"
        SSHD_KEYS="${SH}SSHD_USER_HOME/.ssh/authorized_keys"
        SSHD_CLOSE=0
        if command -v sshd >/dev/null 2>&1 && [ -n "${SH}SSHD_USER_HOME" ] && [ -s "${SH}SSHD_KEYS" ]; then
          if grep -qxF "${SH}SSHD_APP_KEY" "${SH}SSHD_KEYS"; then SSHD_CLOSE=1; fi
        fi
        if [ "${SH}SSHD_CLOSE" -eq 1 ]; then
          # **Every step here is allowed to fail without taking the install
          # with it.** The script runs under `set -e`, and the services are up
          # by the time this runs: a host whose /etc could not be written is a
          # host that keeps password login, not a failed installation — and
          # aborting here would lose the report and the install-key revocation
          # that come after it.
          SSHD_WROTE=1
          install -d -m 755 /etc/ssh/sshd_config.d || SSHD_WROTE=0
          # A single-quoted literal rather than a heredoc: the terminator would
          # have to sit at column 0 inside this indented block, and the body is
          # shared byte-for-byte with the agent, which keeps it free of the one
          # character that could end this literal early.
          printf '%s' '@BODY@
        ' > '$staged' || SSHD_WROTE=0
          chmod 644 '$staged' 2>/dev/null || SSHD_WROTE=0
          mv '$staged' '$PASSWORD_AUTH_DROP_IN_PATH' 2>/dev/null || SSHD_WROTE=0
          if [ "${SH}SSHD_WROTE" -eq 0 ] || [ ! -f '$PASSWORD_AUTH_DROP_IN_PATH' ]; then
            rm -f '$staged'
            echo "${L10nScripts.sshdPasswordCloseNotWritten(language)}"
          elif sshd -t; then
            systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
            # **The only proof that survives contact with a real host.** A file
            # on disk says nothing about the MERGED configuration: sshd keeps
            # the FIRST value it obtains for a keyword, and a cloud image whose
            # own sshd_config.d file says yes would leave every step above
            # successful and the door open. sshd -T prints what it resolved.
            SSHD_EFFECTIVE="${SH}(sshd -T 2>/dev/null | tr 'A-Z' 'a-z' || true)"
            case "${SH}SSHD_EFFECTIVE" in
              *"passwordauthentication no"*)
                case "${SH}SSHD_EFFECTIVE" in
                  *"kbdinteractiveauthentication no"*) ;;
                  *) echo "${L10nScripts.sshdPasswordCloseNotEffective(language)}" ;;
                esac
                ;;
              *) echo "${L10nScripts.sshdPasswordCloseNotEffective(language)}" ;;
            esac
          else
            rm -f '$PASSWORD_AUTH_DROP_IN_PATH'
            echo "${L10nScripts.sshdPasswordCloseRefused(language)}"
          fi
        else
          echo "${L10nScripts.sshdPasswordCloseSkipped(language)}"
        fi
        """.trimIndent().embedding("BODY" to passwordAuthDropIn)
    }
}
