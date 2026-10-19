import gryonixNexusCore
import ServiceCatalog

public enum DashboardAccessSections {
    /// Root-owned wrapper that starts/stops/restarts a single container
    static let containerControlScriptPath = "/opt/gryonixnexus-container-ctl.sh"

    /// Root-owned wrapper that restores one service from one backup file
    static let restoreScriptPath = "/opt/gryonixnexus-restore.sh"

    // MARK: - Control user + app SSH key

    /// Creates the dedicated control (bot) user if missing
    static func controlUser(_ access: DashboardAccessInput, language: AppLanguage) -> String {
        let user = access.sshUser
        guard access.createUser else {
            return #"""
            log "\#(L10nScripts.dashboardExistingUserLog(language, user: user))"
            id -u '\#(user)' >/dev/null 2>&1 || fail "\#(L10nScripts.existingUserMissing(language, user: user))"
            """#
        }
        return #"""
        log "\#(L10nScripts.dashboardCreateUserLog(language, user: user))"
        if ! id -u '\#(user)' >/dev/null 2>&1; then
          useradd --create-home --shell /bin/bash '\#(user)'
        fi
        passwd -l '\#(user)' >/dev/null 2>&1 || true
        """#
    }

    static func authorizedKey(_ access: DashboardAccessInput, language: AppLanguage) -> String {
        let user = access.sshUser
        return #"""
        log "\#(L10nScripts.dashboardSSHKeyLog(language, user: user))"
        APP_KEY='\#(access.appPublicKey)'
        USER_HOME="$(getent passwd '\#(user)' | cut -d: -f6)"
        [ -n "$USER_HOME" ] || fail "\#(L10nScripts.homeDirectoryFail(language, user: user))"
        install -d -m 700 -o '\#(user)' "$USER_HOME/.ssh"
        touch "$USER_HOME/.ssh/authorized_keys"
        grep -qxF "$APP_KEY" "$USER_HOME/.ssh/authorized_keys" || echo "$APP_KEY" >> "$USER_HOME/.ssh/authorized_keys"
        chmod 600 "$USER_HOME/.ssh/authorized_keys"
        chown '\#(user)' "$USER_HOME/.ssh" "$USER_HOME/.ssh/authorized_keys"
        """#
    }

    public static func revokeInstallKey(_ access: DashboardAccessInput, language: AppLanguage) -> String {
        #"""
        log "\#(L10nScripts.revokeInstallKeyLog(language))"
        APP_KEY='\#(access.appPublicKey)'
        CONTROL_USER='\#(access.sshUser)'
        revoke_key_for() {
          # Explicit ifs rather than `[ … ] && …` chains: this runs under
          # `set -e`, where a chain whose test fails carries that status on.
          if [ "$1" = "$CONTROL_USER" ]; then return 0; fi
          home_dir="$(getent passwd "$1" | cut -d: -f6 || true)"
          if [ -z "$home_dir" ]; then return 0; fi
          keys="$home_dir/.ssh/authorized_keys"
          if [ ! -f "$keys" ]; then return 0; fi
          if ! grep -qxF "$APP_KEY" "$keys"; then return 0; fi
          grep -vxF "$APP_KEY" "$keys" > "$keys.gryonixnexus" || true
          mv "$keys.gryonixnexus" "$keys"
          chmod 600 "$keys"
          # The rewrite runs as root, so the file it leaves behind is
          # root-owned — and sshd opens authorized_keys AS THE ACCOUNT, not as
          # root. A root-owned 0600 file is unreadable to it ("Could not open
          # user 'x' authorized keys … Permission denied"), so revoking the
          # app's key takes EVERY OTHER key on that account with it: the
          # owner's own key stops working at the last step of an install that
          # just reported success, and a `sudo -n` install locks them out of
          # the account they installed from. Ownership has to be put back
          # explicitly — the install path above chowns for the same reason.
          chown "$1" "$keys"
          echo "\#(L10nScripts.revokeInstallKeyDone(language))"
        }
        # SUDO_USER is set when the app reached root through `sudo -n <user>`;
        # a direct root login leaves it empty and only root is cleaned.
        revoke_key_for root
        if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
          revoke_key_for "$SUDO_USER"
        fi
        """#
    }

    // MARK: - sudoers

    static func sudoers(lines: [String], language: AppLanguage) -> String {
        #"""
        log "\#(L10nScripts.dashboardSudoersLog(language))"
        cat > /etc/sudoers.d/gryonixnexus-control.staged <<'EOF_SUDOERS'
        # Managed by gryonixNexus — Server Dashboard command whitelist.
        # sudo matches these commands verbatim; do not add flags client-side.
        \#(lines.joined(separator: "\n"))
        EOF_SUDOERS
        chmod 440 /etc/sudoers.d/gryonixnexus-control.staged
        visudo -cf /etc/sudoers.d/gryonixnexus-control.staged || { rm -f /etc/sudoers.d/gryonixnexus-control.staged; fail "\#(L10nScripts.sudoersRejected(language))"; }
        mv /etc/sudoers.d/gryonixnexus-control.staged /etc/sudoers.d/gryonixnexus-control
        """#
    }

    /// The agent's package updater
    static let systemControlScriptPath = "/opt/gryonixnexus-system-ctl.sh"

    /// VPS whitelist
    static func vpsSudoersLines(user: String, wgInterface: String) -> [String] {
        [
            "\(user) ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart wg-quick@\(wgInterface)",
            "\(user) ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart sshd",
            "\(user) ALL=(ALL) NOPASSWD: /usr/bin/systemctl reboot",
            "\(user) ALL=(ALL) NOPASSWD: /usr/bin/systemctl poweroff",
            "\(user) ALL=(ALL) NOPASSWD: \(systemControlScriptPath)",
            "\(user) ALL=(ALL) NOPASSWD: /sbin/sysctl net.ipv4.ip_forward",
            "\(user) ALL=(ALL) NOPASSWD: /usr/bin/wg show",
            // Full cleanup of the relay — the wrapper validates its target.
            "\(user) ALL=(ALL) NOPASSWD: \(UninstallSections.scriptPath)",
            "\(user) ALL=(ALL) NOPASSWD: \(AgentBootstrapSections.scriptPath)",
            "\(user) ALL=(ALL) NOPASSWD: \(AgentBootstrapSections.bridgeSudoersTarget)",
            "\(user) ALL=(ALL) NOPASSWD: \(AgentBootstrapSections.pairCodeSudoersTarget)"
        ]
    }

    static func servicesHostSudoersLines(_ access: DashboardAccessInput, wgInterface: String,
                                         includeWireGuard: Bool,
                                         services: [any ManagedService],
                                         serviceContext: ServiceContext) -> [String] {
        let user = access.sshUser
        var lines = [
            "\(user) ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart sshd",
            "\(user) ALL=(ALL) NOPASSWD: /usr/bin/systemctl reboot",
            "\(user) ALL=(ALL) NOPASSWD: /usr/bin/systemctl poweroff",
            "\(user) ALL=(ALL) NOPASSWD: \(systemControlScriptPath)"
        ]
        if includeWireGuard {
            lines.insert("\(user) ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart wg-quick@\(wgInterface)", at: 0)
            lines.append("\(user) ALL=(ALL) NOPASSWD: /usr/sbin/sysctl net.ipv4.ip_forward")
            lines.append("\(user) ALL=(ALL) NOPASSWD: /usr/bin/wg show")
        }
        if services.contains(where: { if case .docker = $0.runtime { return true }; return false }) {
            lines.append("\(user) ALL=(ALL) NOPASSWD: /usr/bin/docker ps")
            lines.append("\(user) ALL=(ALL) NOPASSWD: \(containerControlScriptPath)")
        }
        // Service removal / full cleanup — the wrapper validates its targets.
        lines.append("\(user) ALL=(ALL) NOPASSWD: \(UninstallSections.scriptPath)")
        lines.append("\(user) ALL=(ALL) NOPASSWD: \(AgentBootstrapSections.scriptPath)")
        lines.append("\(user) ALL=(ALL) NOPASSWD: \(AgentBootstrapSections.bridgeSudoersTarget)")
        lines.append("\(user) ALL=(ALL) NOPASSWD: \(AgentBootstrapSections.pairCodeSudoersTarget)")
        if services.contains(where: { $0.actions(serviceContext).backup != nil }) {
            lines.append("\(user) ALL=(ALL) NOPASSWD: \(BackupControlSections.scriptPath)")
        }
        if UpdateControlSections.isUsed(services, context: serviceContext) {
            lines.append("\(user) ALL=(ALL) NOPASSWD: \(UpdateControlSections.scriptPath)")
        }
        for service in services {
            for line in service.sudoersLines(serviceContext) where !lines.contains(line) {
                lines.append(line)
            }
        }
        return lines
    }

    /// Installs the per-container control wrapper on a docker host
    static func containerControlWrapper(language: AppLanguage) -> String {
        let script = #"""
        #!/bin/bash
        # Managed by gryonixNexus — per-container control for the Server Dashboard.
        # Usage: gryonixnexus-container-ctl.sh <start|stop|restart> <container>
        # Whitelisted once in sudoers; validates its arguments before docker.
        set -euo pipefail
        ACTION="${1:-}"
        NAME="${2:-}"
        case "$ACTION" in
          start|stop|restart) ;;
          *) echo "unsupported action: ${ACTION}" >&2; exit 2 ;;
        esac
        case "$NAME" in
          [A-Za-z0-9]*) ;;
          *) echo "invalid container name: ${NAME}" >&2; exit 2 ;;
        esac
        case "$NAME" in
          *[!A-Za-z0-9_.-]*) echo "invalid container name: ${NAME}" >&2; exit 2 ;;
        esac
        exec docker "$ACTION" "$NAME"
        """#
        return #"""
        log "\#(L10nScripts.containerControlWrapperLog(language))"
        \#(BashSections.writeFile(path: containerControlScriptPath, contents: script, delimiter: "EOF_CONTAINER_CTL"))
        chmod 750 '\#(containerControlScriptPath)'
        """#
    }

    /// Installs the restore wrapper on a docker host
    static func restoreWrapper(_ access: DashboardAccessInput, context: MailContext,
                               language: AppLanguage) -> String {
        let serviceContext = context.serviceContext
        let restorable = context.allSelectedServices.filter {
            $0.actions(serviceContext).restore != nil
        }
        let services = Set(restorable.map(\.id))
        let archivePlans: [(target: String, plan: ArchiveBackupPlan)] = restorable.compactMap {
            guard let target = $0.actions(serviceContext).restore?.wrapperTarget,
                  let plan = $0.actions(serviceContext).backup?.wrapper?.plan.archive else { return nil }
            return (target, plan)
        }
        let backupDirs = restorable.compactMap { $0.actions(serviceContext).restore?.backupDir }
        let dirPatterns = (["\"$MAILCOW_BACKUPS\"/*", "\"$VW_BACKUPS\"/*"]
            + backupDirs.filter { $0 != access.mailcowBackupDir && $0 != access.vaultwardenBackupDir }
                .map { "\"\($0)\"/*" })
            .joined(separator: "|")
        let generatedHelpers = archivePlans.isEmpty ? "" : "\n" + restoreHelpers + "\n"
        let generatedArms = archivePlans
            .map { restoreArchiveFunction(target: $0.target, plan: $0.plan) }
            .joined(separator: "\n\n")
        let generatedCases = archivePlans
            .map { "  \($0.target)) restore_\($0.target.replacingOccurrences(of: "-", with: "_")) ;;" }
            .joined(separator: "\n")

        let script = #"""
        #!/bin/bash
        # Managed by gryonixNexus — restore a service from a backup.
        # Usage: gryonixnexus-restore.sh <\#(restorable.map { $0.actions(serviceContext).restore?.wrapperTarget ?? "" }.joined(separator: "|"))> <archive>
        #        GPG passphrase (encrypted archives only) on stdin.
        set -euo pipefail

        SERVICE="${1:-}"
        ARCHIVE="${2:-}"

        MAILCOW_PATH='\#(access.mailcowPath)'
        MAILCOW_BACKUPS='\#(access.mailcowBackupDir)'
        VW_CONTAINER='\#(access.vaultwardenContainer)'
        VW_DATA='\#(access.vaultwardenDataPath)'
        VW_BACKUPS='\#(access.vaultwardenBackupDir)'
        STAMP="$(date +%Y%m%d-%H%M%S)"

        # The archive must sit inside a backup directory this deployment owns.
        # Without the check a whitelisted wrapper would happily unpack ANY
        # root-readable file over a service's data directory.
        case "$ARCHIVE" in
          *..*) echo "invalid path: ${ARCHIVE}" >&2; exit 2 ;;
        esac
        case "$ARCHIVE" in
          \#(dirPatterns)) ;;
          *) echo "path outside the backup directories: ${ARCHIVE}" >&2; exit 2 ;;
        esac
        [ -e "$ARCHIVE" ] || { echo "no such backup: ${ARCHIVE}" >&2; exit 2; }
        \#(generatedHelpers)
        restore_mailcow() {
          [ -x "$MAILCOW_PATH/helper-scripts/backup_and_restore.sh" ] \
            || { echo "\#(L10nScripts.mailcowNotFound(language, path: access.mailcowPath))" >&2; exit 1; }
          # mailcow's helper restores from a DIRECTORY inside its backup
          # location and picks it from a numbered menu. Stage the chosen backup
          # alone in a scratch location so that menu has exactly one entry.
          local stage="$MAILCOW_BACKUPS/.restore-$STAMP"
          mkdir -p "$stage"
          chmod 0777 "$stage"
          # shellcheck disable=SC2064
          trap "rm -rf '$stage'" EXIT
          local plain="$ARCHIVE"
          case "$ARCHIVE" in
            *.gpg)
              plain="$stage/.restore.tar.gz"
              gpg --batch --quiet --yes --decrypt --passphrase-fd 0 \
                  --pinentry-mode loopback --output "$plain" "$ARCHIVE" \
                || { echo "could not decrypt the backup (wrong passphrase?)" >&2; exit 1; }
              ;;
          esac
          if [ -d "$ARCHIVE" ]; then
            cp -a "$ARCHIVE" "$stage/"
          else
            tar -xzf "$plain" -C "$stage"
            rm -f "$stage/.restore.tar.gz"
          fi
          export MAILCOW_BACKUP_LOCATION="$stage"
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
            | timeout 3600 "$MAILCOW_PATH/helper-scripts/backup_and_restore.sh" restore
        }

        restore_vaultwarden() {
          local plain="$ARCHIVE" tmp="" stage="" root="" previous="" saved=0
          case "$ARCHIVE" in
            *.gpg)
              tmp="$(mktemp -d)"
              # shellcheck disable=SC2064
              trap "rm -rf '$tmp'" EXIT
              plain="$tmp/restore.tar.gz"
              # --passphrase-fd 0: the secret arrives on stdin, never in argv.
              gpg --batch --quiet --yes --decrypt --passphrase-fd 0 \
                  --pinentry-mode loopback --output "$plain" "$ARCHIVE" \
                || { echo "could not decrypt the backup (wrong passphrase?)" >&2; exit 1; }
              ;;
          esac
          # Verify BEFORE touching live data: a truncated upload must not cost
          # the user the data they still have.
          tar -tzf "$plain" >/dev/null 2>&1 \
            || { echo "the backup archive is not readable" >&2; exit 1; }
          # Unpacked aside; only the archived data directory is moved in.
          root="$(tar -tzf "$plain" | sed -n '1{s|^\./||;s|/*$||;p;}')"
          case "/$root/" in
            //|*/../*|*/./*) echo "the archive carries no vaultwarden data" >&2; exit 1 ;;
          esac
          mkdir -p "$(dirname "$VW_DATA")"
          stage="$(mktemp -d "$(dirname "$VW_DATA")/.restore-XXXXXX")"
          # shellcheck disable=SC2064
          trap "rm -rf '$stage' '$tmp'" EXIT
          tar --numeric-owner -xzf "$plain" -C "$stage" \
            || { echo "the backup archive is not readable" >&2; exit 1; }
          if [ ! -d "$stage/$root" ] || [ -L "$stage/$root" ]; then
            echo "the archive carries no vaultwarden data" >&2
            exit 1
          fi
          docker stop "$VW_CONTAINER" >/dev/null 2>&1 || true
          # The old data is moved aside, never deleted: if the move fails it is
          # the only way back, and the container must come up again either way.
          previous="${VW_DATA}.pre-restore-$STAMP"
          if [ -d "$VW_DATA" ]; then mv "$VW_DATA" "$previous"; saved=1; fi
          if mv "$stage/$root" "$VW_DATA"; then
            if [ "$saved" -eq 1 ]; then echo "previous data kept at ${previous}"; fi
          else
            echo "restore failed, rolling back to the previous data" >&2
            rm -rf "$VW_DATA"
            if [ "$saved" -eq 1 ]; then mv "$previous" "$VW_DATA"; fi
            docker start "$VW_CONTAINER" >/dev/null 2>&1 || true
            exit 1
          fi
          docker start "$VW_CONTAINER" >/dev/null 2>&1 || true
        }

        \#(generatedArms)

        case "$SERVICE" in
          mailcow) restore_mailcow ;;
          vaultwarden) restore_vaultwarden ;;
        \#(generatedCases)
          *) echo "unsupported service: ${SERVICE}" >&2; exit 2 ;;
        esac
        # A streamed command carries no exit status back to the app, so success
        # is announced with a fixed ASCII marker (never the localized line —
        # the app must not have to know which language the script was made in).
        echo "\#(L10nScripts.restoreDone(language))"
        echo 'GRYONIXNEXUS_RESTORE_DONE'
        """#
        var staging: [String] = []
        if services.contains(.mailcow) {
            let dir = uploadStagingDirectory(access.mailcowBackupDir)
            staging.append(#"""
            install -d '\#(dir)'
            chgrp "$(id -gn '\#(access.sshUser)')" '\#(dir)'
            chmod 0770 '\#(dir)'
            """#)
        }
        if services.contains(.vaultwarden) {
            staging.append("install -d -o '\(access.sshUser)' -m 0750 "
                           + "'\(uploadStagingDirectory(access.vaultwardenBackupDir))'")
        }
        for dir in backupDirs where dir != access.mailcowBackupDir && dir != access.vaultwardenBackupDir {
            staging.append("install -d -o '\(access.sshUser)' -m 0750 "
                           + "'\(uploadStagingDirectory(dir))'")
        }
        return #"""
        log "\#(L10nScripts.restoreWrapperLog(language))"
        \#(BashSections.writeFile(path: restoreScriptPath, contents: script, delimiter: "EOF_RESTORE"))
        chmod 750 '\#(restoreScriptPath)'
        \#(staging.joined(separator: "\n"))
        """#
    }

    /// Helpers the generated restore arms share
    private static let restoreHelpers = #"""
        gd_compose_stop() {
          local project="$1"
          shift
          docker compose -p "$project" stop "$@" >/dev/null 2>&1 || true
        }

        gd_compose_start() {
          local project="$1"
          shift
          docker compose -p "$project" start "$@" >/dev/null 2>&1 || true
        }

        # Everything the project has, so the service is up again whatever the
        # restore did — the same guarantee the vaultwarden arm gives.
        gd_compose_start_all() {
          docker compose -p "$1" start >/dev/null 2>&1 || true
        }

        gd_container() {
          docker compose -p "$1" ps -q "$2" 2>/dev/null | head -n 1
        }

        # A container that has just been started reports "up" long before its
        # engine accepts connections, and a dump loaded into it then fails with
        # a connection error that reads exactly like a corrupt backup.
        gd_db_wait() {
          local cid="$1" engine="$2" deadline
          deadline=$(( $(date +%s) + 180 ))
          while [ "$(date +%s)" -lt "$deadline" ]; do
            case "$engine" in
              postgres)
                if docker exec "$cid" sh -c 'exec pg_isready -q -U "$POSTGRES_USER"' >/dev/null 2>&1; then
                  return 0
                fi
                ;;
              mysql)
                if docker exec "$cid" sh -c 'if command -v mariadb-admin >/dev/null 2>&1; then A=mariadb-admin; else A=mysqladmin; fi; MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec "$A" ping -u root' >/dev/null 2>&1; then
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
          cid="$(gd_container "$1" "$2")"
          if [ -z "$cid" ]; then echo "the $1 database container is not running" >&2; return 1; fi
          if ! gd_db_wait "$cid" postgres; then echo "the $1 database never became ready" >&2; return 1; fi
          if [ ! -s "$3" ]; then echo "the archive carries no $1 database dump" >&2; return 1; fi
          # ON_ERROR_STOP: without it psql replays half a dump and still exits
          # 0, i.e. reports a restore that did not happen.
          if ! docker exec -i "$cid" sh -c \
               'PGPASSWORD="$POSTGRES_PASSWORD" exec psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
               < "$3"; then
            echo "the $1 database could not be loaded" >&2
            return 1
          fi
        }

        # The fourth argument mirrors gd_dump_mysql: a service that keeps
        # several databases in one engine names each one, and the load has to
        # put each dump back where it came from.
        gd_load_mysql() {
          local cid
          cid="$(gd_container "$1" "$2")"
          if [ -z "$cid" ]; then echo "the $1 database container is not running" >&2; return 1; fi
          if ! gd_db_wait "$cid" mysql; then echo "the $1 database never became ready" >&2; return 1; fi
          if [ ! -s "$3" ]; then echo "the archive carries no $1 database dump" >&2; return 1; fi
          if ! docker exec -i "$cid" sh -c \
               'if command -v mariadb >/dev/null 2>&1; then C=mariadb; else C=mysql; fi; MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec "$C" -u root "${1:-$MYSQL_DATABASE}"' \
               sh "${4:-}" < "$3"; then
            echo "the $1 database could not be loaded" >&2
            return 1
          fi
        }
        """#

    private static func restoreArchiveFunction(target: String, plan: ArchiveBackupPlan) -> String {
        let name = target.replacingOccurrences(of: "-", with: "_")
        let project = plan.composeProject
        let quiesce = plan.quiesceServices.map { "'\($0)'" }.joined(separator: " ")
        let data = plan.dataPath
        var lines: [String] = [
            "restore_\(name)() {",
            "  local plain=\"$ARCHIVE\" tmp=\"\" stage=\"\" previous=\"\" saved=0 rc=0",
            "  case \"$ARCHIVE\" in",
            "    *.gpg)",
            "      tmp=\"$(mktemp -d \"$(dirname \"$ARCHIVE\")/.gpg-XXXXXX\")\"",
            "      plain=\"$tmp/restore.tar.gz\"",
            "      # --passphrase-fd 0: the secret arrives on stdin, never in argv.",
            "      if ! gpg --batch --quiet --yes --decrypt --passphrase-fd 0 \\",
            "           --pinentry-mode loopback --output \"$plain\" \"$ARCHIVE\"; then",
            "        rm -rf \"$tmp\"",
            "        echo \"could not decrypt the backup (wrong passphrase?)\" >&2",
            "        exit 1",
            "      fi",
            "      ;;",
            "  esac",
            "  # Verified BEFORE anything is stopped: a truncated upload must not",
            "  # cost the user the data they still have.",
            "  if ! tar -tzf \"$plain\" >/dev/null 2>&1; then",
            "    rm -rf \"$tmp\"",
            "    echo \"the backup archive is not readable\" >&2",
            "    exit 1",
            "  fi",
            "  # Staged on the SERVICE's own filesystem, so putting the data back",
            "  # is a rename rather than a second copy of the whole directory.",
            "  stage=\"$(mktemp -d '\(plan.dataParent)/.restore-XXXXXX')\"",
            "  # shellcheck disable=SC2064",
            "  trap \"rm -rf '$stage' '$tmp'\" EXIT",
            "  tar --numeric-owner -xzf \"$plain\" -C \"$stage\"",
            "  if [ ! -d \"$stage/\(plan.dataSlot)\" ]; then",
            "    echo \"the archive carries no \(target) data\" >&2",
            "    exit 1",
            "  fi"
        ]
        if !plan.quiesceServices.isEmpty {
            lines.append("  gd_compose_stop '\(project)' \(quiesce)")
        }
        lines += [
            "  # The old data is moved aside, never deleted: if the move back",
            "  # fails it is the only way home.",
            "  previous='\(data)'\".pre-restore-$STAMP\"",
            "  if [ -d '\(data)' ]; then mv '\(data)' \"$previous\"; saved=1; fi",
            "  if mv \"$stage/\(plan.dataSlot)\" '\(data)'; then",
            "    if [ \"$saved\" -eq 1 ]; then echo \"previous data kept at ${previous}\"; fi",
            "  else",
            "    echo \"restore failed, rolling back to the previous data\" >&2",
            "    rm -rf '\(data)'",
            "    if [ \"$saved\" -eq 1 ]; then mv \"$previous\" '\(data)'; fi",
            "    gd_compose_start_all '\(project)'",
            "    exit 1",
            "  fi"
        ]
        for database in plan.databases {
            let helper = database.engine == .postgres ? "gd_load_postgres" : "gd_load_mysql"
            lines += [
                "  # The database container has to be up to take its dump back;",
                "  # the rest of the project stays down until it is loaded.",
                "  gd_compose_start '\(project)' '\(database.service)'",
                "  \(helper) '\(project)' '\(database.service)' "
                    + "\"$stage/\(ArchiveBackupPlan.dumpDirectoryName)/\(database.fileName)\""
                    + (database.databaseName.map { " '\($0)'" } ?? "") + " || rc=1"
            ]
        }
        lines += [
            "  # Up again on every path, restored or not.",
            "  gd_compose_start_all '\(project)'",
            "  if [ \"$rc\" -ne 0 ]; then",
            "    echo \"the \(target) database could not be restored\" >&2",
            "    exit 1",
            "  fi",
            "}"
        ]
        return lines.joined(separator: "\n")
    }

    static func serviceBackupDirs(_ access: DashboardAccessInput, context: MailContext) -> String? {
        let serviceContext = context.serviceContext
        let dirs = context.allSelectedServices
            .compactMap { $0.actions(serviceContext).backup?.listDirectory }
            .filter { $0 != access.mailcowBackupDir && $0 != access.vaultwardenBackupDir }
        guard !dirs.isEmpty else { return nil }
        var lines = [#"log "\#(L10nScripts.serviceBackupDirLog(context.language))""#]
        for root in Set(dirs.compactMap(enclosingBackupRoot)).sorted() {
            lines.append(#"""
            install -d '\#(root)'
            chgrp "$(id -gn '\#(access.sshUser)')" '\#(root)'
            chmod 0750 '\#(root)'
            """#)
        }
        for dir in dirs {
            lines.append("install -d -o '\(access.sshUser)' -m 0750 '\(dir)'")
        }
        return lines.joined(separator: "\n")
    }

    static func uploadStagingDirectory(_ backupDir: String) -> String { "\(backupDir)/incoming" }

    static func mailcowBackupWrapper(_ access: DashboardAccessInput, language: AppLanguage) -> String {
        let wrapper = #"""
        #!/bin/bash
        # Managed by gryonixNexus — mailcow backup wrapper for the Server Dashboard.
        # sudo strips env vars (env_reset): MAILCOW_BACKUP_LOCATION is set here.
        set -euo pipefail
        [ -x '\#(access.mailcowPath)/helper-scripts/backup_and_restore.sh' ] || { echo "\#(L10nScripts.mailcowNotFound(language, path: access.mailcowPath))" >&2; exit 1; }
        export MAILCOW_BACKUP_LOCATION='\#(access.mailcowBackupDir)'
        mkdir -p "$MAILCOW_BACKUP_LOCATION"
        # mailcow's backup_and_restore.sh requires the location to be writable
        # by others (its containers write as different UIDs); it aborts with
        # "is not write-able for others" otherwise. What keeps the archives out
        # of other accounts' reach is the 0750 on the ENCLOSING directory (see
        # enclosingBackupRoot) — this 0777 cannot be narrowed.
        chmod 0777 "$MAILCOW_BACKUP_LOCATION"
        '\#(access.mailcowPath)/helper-scripts/backup_and_restore.sh' backup all
        # mailcow writes each backup as a DIRECTORY, which the dashboard cannot
        # download and share. Archive the newest one into a single .tar.gz next
        # to it (0644 like everything mailcow itself writes here — the 0777 on
        # this directory makes narrowing the files pointless; the enclosing
        # directory is what blocks other accounts), so "Share backup" has a
        # real file to hand off.
        NEWEST=""
        for d in "$MAILCOW_BACKUP_LOCATION"/mailcow-*/; do
          [ -d "$d" ] || continue
          if [ -z "$NEWEST" ] || [ "$d" -nt "$NEWEST" ]; then NEWEST="$d"; fi
        done
        if [ -n "$NEWEST" ]; then
          base="$(basename "$NEWEST")"
          tar -czf "$MAILCOW_BACKUP_LOCATION/$base.tar.gz" -C "$MAILCOW_BACKUP_LOCATION" "$base"
          chmod 0644 "$MAILCOW_BACKUP_LOCATION/$base.tar.gz"
        fi
        # Rotation (as root — backups are root-owned): keep the newest
        # \#(access.backupRetention) of each kind (directories and archives).
        ls -1dt "$MAILCOW_BACKUP_LOCATION"/mailcow-*/ 2>/dev/null | tail -n +\#(access.backupRetention + 1) | xargs -r rm -rf
        ls -1t "$MAILCOW_BACKUP_LOCATION"/mailcow-*.tar.gz 2>/dev/null | tail -n +\#(access.backupRetention + 1) | xargs -r rm -f
        """#
        return #"""
        log "\#(L10nScripts.mailcowBackupWrapperLog(language, path: access.mailcowPath))"
        install -d '\#(access.mailcowPath)'
        \#(BashSections.writeFile(path: "\(access.mailcowPath)/bot-backup.sh", contents: wrapper, delimiter: "EOF_MC_BACKUP"))
        chmod 750 '\#(access.mailcowPath)/bot-backup.sh'
        """#
    }

    static func mailcowBackupDir(_ access: DashboardAccessInput, language: AppLanguage) -> String {
        var lines = [#"log "\#(L10nScripts.mailcowBackupDirLog(language))""#]
        if let root = enclosingBackupRoot(of: access.mailcowBackupDir) {
            lines.append(#"""
            install -d '\#(root)'
            chgrp "$(id -gn '\#(access.sshUser)')" '\#(root)'
            chmod 0750 '\#(root)'
            """#)
        }
        lines.append(#"""
        install -d '\#(access.mailcowBackupDir)'
        chgrp "$(id -gn '\#(access.sshUser)')" '\#(access.mailcowBackupDir)'
        chmod 750 '\#(access.mailcowBackupDir)'
        """#)
        return lines.joined(separator: "\n")
    }

    static func enclosingBackupRoot(of dir: String) -> String? {
        let path = dir.hasSuffix("/") ? String(dir.dropLast()) : dir
        guard let slash = path.lastIndex(of: "/") else { return nil }
        let parent = String(path[path.startIndex..<slash])
        guard parent.dropFirst().contains("/") else { return nil }
        return parent
    }

    static func vaultwardenBackupDir(_ access: DashboardAccessInput, language: AppLanguage) -> String {
        #"""
        log "\#(L10nScripts.vaultwardenBackupDirLog(language))"
        install -d -o '\#(access.sshUser)' -m 750 '\#(access.vaultwardenBackupDir)'
        """#
    }

    // MARK: - Assembled sections

    /// Everything the VPS needs: app key + minimal sudoers
    static func vpsSection(_ access: DashboardAccessInput, language: AppLanguage) -> String {
        var sections = [controlUser(access, language: language)]
        if access.createUser {
            sections.append(authorizedKey(access, language: language))
        }
        sections.append(sudoers(lines: vpsSudoersLines(user: access.sshUser,
                                                       wgInterface: WireGuardDefaults.interfaceName),
                                language: language))
        sections.append(UninstallSections.vpsWrapper(access, language: language))
        sections.append(AgentBootstrapSections.wrapper(user: access.sshUser))
        sections.append(passwordAuthClose(access, language: language))
        return sections.joined(separator: "\n\n")
    }

    static func servicesHostSection(_ access: DashboardAccessInput, context: MailContext,
                                    includeWireGuard: Bool) -> String {
        var serviceContext = context.serviceContext
        serviceContext.sshUser = access.sshUser
        let services = context.allSelectedServices
        let language = context.language
        var sections = [controlUser(access, language: language)]
        if access.createUser {
            sections.append(authorizedKey(access, language: language))
        }
        sections.append(sudoers(lines: servicesHostSudoersLines(access, wgInterface: WireGuardDefaults.interfaceName,
                                                                includeWireGuard: includeWireGuard,
                                                                services: services, serviceContext: serviceContext),
                                language: language))
        if services.contains(where: { if case .docker = $0.runtime { return true }; return false }) {
            sections.append(containerControlWrapper(language: language))
        }
        if context.input.services.contains(.mailcow) {
            sections.append(mailcowBackupWrapper(access, language: language))
            sections.append(mailcowBackupDir(access, language: language))
        }
        if context.input.services.contains(.vaultwarden) {
            sections.append(vaultwardenBackupDir(access, language: language))
        }
        if let dirs = serviceBackupDirs(access, context: context) {
            sections.append(dirs)
        }
        // Restore wrapper last: it needs every backup directory to exist.
        if services.contains(where: { $0.actions(serviceContext).restore != nil }) {
            sections.append(restoreWrapper(access, context: context, language: language))
        }
        if services.contains(where: { $0.actions(serviceContext).backup != nil }) {
            sections.append(BackupControlSections.wrapper(access, services: services,
                                                          context: serviceContext,
                                                          language: language))
            sections.append(BackupControlSections.passphraseSection(services: services,
                                                                    context: serviceContext))
        }
        if UpdateControlSections.isUsed(services, context: serviceContext) {
            sections.append(UpdateControlSections.wrapper(services: services,
                                                          context: serviceContext,
                                                          language: language))
        }
        sections.append(AgentBootstrapSections.wrapper(user: access.sshUser))
        sections.append(UninstallSections.servicesHostWrapper(access, context: context,
                                                              includeWireGuard: includeWireGuard))
        return sections.joined(separator: "\n\n")
    }

    static func homeSection(_ access: DashboardAccessInput, context: MailContext) -> String {
        var section = servicesHostSection(access, context: context, includeWireGuard: true)
        if case .ipv4(let vpsTunnelIP)? = context.server(.vpsRelay)?.vpnAddress {
            section += "\n\n" + sshdPenaltyExemption(sourceIP: vpsTunnelIP,
                                                     language: context.language)
        }
        section += "\n\n" + passwordAuthClose(access, language: context.language)
        return section
    }

    /// Writes an sshd_config drop-in exempting `sourceIP` from per-source penalties
    static func sshdPenaltyExemption(sourceIP: String, language: AppLanguage) -> String {
        #"""
        if sshd -T 2>/dev/null | grep -qi '^persourcepenalties'; then
          log "\#(L10nScripts.sshdPenaltyExemptLog(language))"
          install -d /etc/ssh/sshd_config.d
          printf 'PerSourcePenaltyExemptList %s\n' '\#(sourceIP)' > /etc/ssh/sshd_config.d/60-gryonixnexus-tunnel.conf
          systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
        fi
        """#
    }

    static func singleHostSection(_ access: DashboardAccessInput, context: MailContext) -> String {
        servicesHostSection(access, context: context, includeWireGuard: false)
            + "\n\n" + passwordAuthClose(access, language: context.language)
    }

    // MARK: - Closing SSH password login

    /// Where the drop-in lives
    static let passwordAuthDropInPath = "/etc/ssh/sshd_config.d/10-gryonixnexus-no-password.conf"

    /// The drop-in's contents
    static let passwordAuthDropIn = """
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
    """

    static func passwordAuthCloseUninstallLines(indent: String) -> [String] {
        [
            "\(indent)# SSH password login comes back BEFORE the app key is stripped below,",
            "\(indent)# so this machine is never left with neither way in.",
            "\(indent)rm -f \(passwordAuthDropInPath)",
            "\(indent)systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true",
        ]
    }

    static func passwordAuthClose(_ access: DashboardAccessInput, language: AppLanguage) -> String {
        guard access.createUser else { return ":" }
        let staged = passwordAuthDropInPath + ".staged"
        return #"""
        log "\#(L10nScripts.sshdPasswordCloseLog(language))"
        SSHD_APP_KEY='\#(access.appPublicKey)'
        SSHD_USER_HOME="$(getent passwd '\#(access.sshUser)' | cut -d: -f6 || true)"
        SSHD_KEYS="$SSHD_USER_HOME/.ssh/authorized_keys"
        SSHD_CLOSE=0
        if command -v sshd >/dev/null 2>&1 && [ -n "$SSHD_USER_HOME" ] && [ -s "$SSHD_KEYS" ]; then
          if grep -qxF "$SSHD_APP_KEY" "$SSHD_KEYS"; then SSHD_CLOSE=1; fi
        fi
        if [ "$SSHD_CLOSE" -eq 1 ]; then
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
          printf '%s' '\#(passwordAuthDropIn)
        ' > '\#(staged)' || SSHD_WROTE=0
          chmod 644 '\#(staged)' 2>/dev/null || SSHD_WROTE=0
          mv '\#(staged)' '\#(passwordAuthDropInPath)' 2>/dev/null || SSHD_WROTE=0
          if [ "$SSHD_WROTE" -eq 0 ] || [ ! -f '\#(passwordAuthDropInPath)' ]; then
            rm -f '\#(staged)'
            echo "\#(L10nScripts.sshdPasswordCloseNotWritten(language))"
          elif sshd -t; then
            systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
            # **The only proof that survives contact with a real host.** A file
            # on disk says nothing about the MERGED configuration: sshd keeps
            # the FIRST value it obtains for a keyword, and a cloud image whose
            # own sshd_config.d file says yes would leave every step above
            # successful and the door open. sshd -T prints what it resolved.
            SSHD_EFFECTIVE="$(sshd -T 2>/dev/null | tr 'A-Z' 'a-z' || true)"
            case "$SSHD_EFFECTIVE" in
              *"passwordauthentication no"*)
                case "$SSHD_EFFECTIVE" in
                  *"kbdinteractiveauthentication no"*) ;;
                  *) echo "\#(L10nScripts.sshdPasswordCloseNotEffective(language))" ;;
                esac
                ;;
              *) echo "\#(L10nScripts.sshdPasswordCloseNotEffective(language))" ;;
            esac
          else
            rm -f '\#(passwordAuthDropInPath)'
            echo "\#(L10nScripts.sshdPasswordCloseRefused(language))"
          fi
        else
          echo "\#(L10nScripts.sshdPasswordCloseSkipped(language))"
        fi
        """#
    }
}
