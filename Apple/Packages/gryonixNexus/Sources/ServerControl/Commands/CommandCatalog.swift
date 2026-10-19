import Foundation
import ServiceCatalog

/// What a removal additionally deletes from disk
public struct PurgeOptions: Sendable, Hashable {
    /// Config directory, bind mounts and compose volumes
    public var data: Bool
    /// The service's backup directories
    public var backups: Bool

    public init(data: Bool = false, backups: Bool = false) {
        self.data = data
        self.backups = backups
    }

    public static let none = PurgeOptions()
    public var isEmpty: Bool { !data && !backups }
}

/// Every remote command the dashboard sends, as exact literals
public enum CommandCatalog {
    public static let ipForwardingCheck = "sudo sysctl net.ipv4.ip_forward"

    public static func pingSelf(vpsHost: String) -> String {
        "ping -c 1 -W 2 \(ShellQuoting.singleQuoted(vpsHost))"
    }

    /// The General rows in one round-trip
    public static let generalProbeSeparator = "___GRYONIXNEXUS_NEXT___"

    public static func generalProbe(vpsHost: String, homeWGAddress: String) -> String {
        [ipForwardingCheck, pingSelf(vpsHost: vpsHost), pingTunnel(homeWGAddress: homeWGAddress)]
            .joined(separator: "; echo '\(generalProbeSeparator)'; ")
    }

    public static func pingTunnel(homeWGAddress: String) -> String {
        "ping -c 1 -W 2 \(ShellQuoting.singleQuoted(homeWGAddress))"
    }

    public static func restartWireGuard(interface: String) -> String {
        "sudo systemctl restart wg-quick@\(interface)"
    }

    public static let restartSSHD = "sudo systemctl restart sshd"

    /// Reboots the host
    public static let rebootHost = "sudo systemctl reboot"
    public static let powerOffHost = "sudo systemctl poweroff"

    public static let wgShow = "sudo wg show"

    public static let defaultRouteMACAddress =
        "cat /sys/class/net/$(ip route show default | awk '{print $5; exit}')/address"

    /// VPN-only access switch for admin web panels
    public enum AdminLockdown {
        public static let on = "sudo /opt/gryonixnexus-admin-lockdown.sh on"
        public static let off = "sudo /opt/gryonixnexus-admin-lockdown.sh off"
        public static let status = "sudo /opt/gryonixnexus-admin-lockdown.sh status"

        public static func only(hosts: [String]) -> String {
            "sudo /opt/gryonixnexus-admin-lockdown.sh only " + hosts.joined(separator: " ")
        }

        /// Client-side mirror of the wrapper's host validation
        public static func isValidHost(_ host: String) -> Bool {
            !host.isEmpty && host.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
        }
    }

    public enum Containers {
        /// Root-owned wrapper the setup scripts install on every docker host
        public static let controlScriptPath = "/opt/gryonixnexus-container-ctl.sh"

        public enum Action: String, Sendable, CaseIterable {
            case start, stop, restart
        }

        /// `sudo <wrapper> <action> <container>`
        public static func control(_ action: Action, container: String) -> String {
            "sudo \(controlScriptPath) \(action.rawValue) \(ShellQuoting.singleQuoted(container))"
        }
    }

    public enum Restore {
        /// Root-owned wrapper the setup scripts install alongside the container one
        public static let scriptPath = "/opt/gryonixnexus-restore.sh"

        /// Last line the wrapper prints on success
        public static let doneMarker = "GRYONIXNEXUS_RESTORE_DONE"

        public static func isValidTarget(_ target: String) -> Bool {
            !target.isEmpty && target.allSatisfy {
                $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-")
            }
        }

        /// `sudo <wrapper> <service> <archive>`
        public static func run(target: String, archivePath: String) -> String {
            "sudo \(scriptPath) \(target) \(ShellQuoting.singleQuoted(archivePath))"
        }

        public static let stagingDirectoryName = "incoming"

        public static func stagingDirectory(backupDir: String) -> String {
            "\(backupDir)/\(stagingDirectoryName)"
        }

        public static func isValidArchivePath(_ path: String, backupDir: String) -> Bool {
            path.hasPrefix(backupDir + "/") && !path.contains("..")
        }
    }

    public enum Uninstall {
        public static let scriptPath = "/opt/gryonixnexus-uninstall.sh"

        public static let doneMarker = "GRYONIXNEXUS_UNINSTALL_DONE"

        public static let vpnTarget = "vpn"

        public static let purgeDataFlag = "--purge-data"
        public static let purgeBackupsFlag = "--purge-backups"

        /// `sudo <wrapper> <target> [--purge-data] [--purge-backups]`
        public static func run(target: String, purge: PurgeOptions) -> String {
            "sudo \(scriptPath) \(target)\(flags(purge))"
        }

        public static func fullCleanup(purge: PurgeOptions) -> String {
            "sudo \(scriptPath) --all\(flags(purge))"
        }

        private static func flags(_ purge: PurgeOptions) -> String {
            (purge.data ? " \(purgeDataFlag)" : "")
                + (purge.backups ? " \(purgeBackupsFlag)" : "")
        }
    }

    public static let disk = "df -B1 --output=target,size,used,pcent -x tmpfs -x devtmpfs -x overlay"

    public static let memory = "free -b"

    public static let hostMetrics = "echo @@STAT@@; cat /proc/stat; "
        + "echo @@MEM@@; cat /proc/meminfo; "
        + "echo @@UPTIME@@; cat /proc/uptime; "
        + "echo @@LOAD@@; cat /proc/loadavg; "
        + "echo @@NET@@; cat /proc/net/dev; "
        + "echo @@DISKSTATS@@; cat /proc/diskstats; "
        + "echo @@DF@@; df -B1 --output=target,size,used,pcent -x tmpfs -x devtmpfs -x overlay 2>/dev/null; "
        + "echo @@OS@@; cat /etc/os-release 2>/dev/null; "
        + "echo @@NPROC@@; nproc 2>/dev/null; "
        + "echo @@TEMP@@; cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null; true"

    public static func metricsHistory(bucket: MetricsHistoryBucket) -> String {
        "cat /var/lib/gryonixnexus/metrics/\(bucket.rawValue).csv 2>/dev/null; "
            + "echo \(MetricsHistoryParser.powerMarker); "
            + "cat /var/lib/gryonixnexus/metrics/power-\(bucket.rawValue).csv 2>/dev/null; true"
    }

    /// Per-filesystem used and total bytes for one bucket
    public static func diskHistory(bucket: MetricsHistoryBucket) -> String {
        "cat /var/lib/gryonixnexus/metrics/disks-\(bucket.rawValue).csv 2>/dev/null; true"
    }

    public static let installReport =
        "cat /var/lib/gryonixnexus/install-report.txt 2>/dev/null; true"

    public enum Mailcow {
        public static let status = "sudo docker compose -p mailcowdockerized ps"

        public static let restart = "sudo docker compose -p mailcowdockerized restart"

        public static func update(mailcowPath: String) -> String {
            "cd \(ShellQuoting.argument(mailcowPath)) && sudo /bin/bash "
                + "\(ShellQuoting.argument(mailcowPath + "/update.sh")) --force"
        }

        public static func backup(mailcowPath: String, backupDir: String) -> String {
            "mkdir -p \(ShellQuoting.singleQuoted(backupDir)) && sudo \(ShellQuoting.argument(mailcowPath + "/bot-backup.sh"))"
        }

        /// Size of the newest backup produced by the wrapper
        public static func latestBackupSize(backupDir: String) -> String {
            "du -sh \"$(ls -1dt \(ShellQuoting.argument(backupDir))/* | head -n 1)\" | tail -n 1"
        }

        /// Root-owned read-only wrapper the mailcow setup installs
        public static let dkimScriptPath = "/opt/gryonixnexus-dkim.sh"

        /// Last line the wrapper prints on success
        public static let dkimDoneMarker = "GRYONIXNEXUS_DKIM_DONE"

        public static let dkimDump = "sudo \(dkimScriptPath)"
    }

    /// Mailbox management for the docker-mailserver engine
    public enum DockerMailserver {
        /// Must match DockerMailserverService.mailboxScriptPath on the ServiceCatalog side
        public static let mailboxScriptPath = "/opt/gryonixnexus-dms-mailbox.sh"

        /// Last line every mutating arm prints: `<marker> <action> <address>`
        public static let mailboxDoneMarker = "GRYONIXNEXUS_MAILBOX_DONE"

        /// Read-only listing of the mailboxes the engine knows about
        public static let listMailboxes = "sudo \(mailboxScriptPath) list"

        /// `sudo <wrapper> add <address>` — the password is NOT here
        public static func addMailbox(address: String) -> String {
            "sudo \(mailboxScriptPath) add \(ShellQuoting.singleQuoted(address))"
        }

        public static func deleteMailbox(address: String) -> String {
            "sudo \(mailboxScriptPath) del \(ShellQuoting.singleQuoted(address))"
        }

        /// `sudo <wrapper> password <address>` — password on stdin, as above
        public static func setMailboxPassword(address: String) -> String {
            "sudo \(mailboxScriptPath) password \(ShellQuoting.singleQuoted(address))"
        }

        public static func isValidAddress(_ address: String) -> Bool {
            guard !address.isEmpty, !address.hasPrefix("-") else { return false }
            let allowed = address.allSatisfy { character in
                character.isASCII
                    && (character.isLetter || character.isNumber || ".@_+-".contains(character))
            }
            guard allowed else { return false }
            let parts = address.split(separator: "@", omittingEmptySubsequences: false)
            return parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty
        }
    }

    public enum Vaultwarden {
        public static let status = "sudo docker ps -a"

        public static func restart(container: String) -> String {
            "sudo docker restart \(ShellQuoting.argument(container))"
        }

        public static let update = "sudo /opt/vaultwarden-update.sh"

        public static func stop(container: String) -> String {
            "sudo docker stop \(ShellQuoting.argument(container))"
        }

        public static func start(container: String) -> String {
            "sudo docker start \(ShellQuoting.argument(container))"
        }

        public static func stagingArchivePath(backupDir: String, container: String) -> String {
            "\(backupDir)/\(container)-backup.tar.gz"
        }

        /// Data is root-owned, hence tar via sudo
        public static func archive(dataPath: String, archivePath: String) -> String {
            let relative = BackupSpec.archiveRelativePath(dataPath)
            return "sudo tar czf \(ShellQuoting.singleQuoted(archivePath)) -C / \(ShellQuoting.singleQuoted(relative))"
        }

        public static func chownArchive(user: String, archivePath: String) -> String {
            "sudo chown \(ShellQuoting.singleQuoted(user)) \(ShellQuoting.singleQuoted(archivePath))"
        }

        /// Symmetric GPG encryption; the passphrase arrives on stdin
        public static func encrypt(archivePath: String, outputPath: String) -> String {
            "gpg --symmetric --cipher-algo AES256 --batch --pinentry-mode loopback --passphrase-fd 0"
                + " --output \(ShellQuoting.singleQuoted(outputPath)) \(ShellQuoting.singleQuoted(archivePath))"
        }

        public static func removePlainArchive(archivePath: String) -> String {
            "rm -f \(ShellQuoting.singleQuoted(archivePath))"
        }

        public static func backupSize(gpgPath: String) -> String {
            "du -sh \(ShellQuoting.singleQuoted(gpgPath)) | cut -f1"
        }

        /// Keeps the newest `retention` archives, at least one
        public static func rotate(backupDir: String, retention: Int) -> String {
            let dir = ShellQuoting.singleQuoted(backupDir)
            return "ls -1t \(dir) 2>/dev/null | grep '\\.gpg$' | tail -n +\(max(retention, 1) + 1)"
                + " | while IFS= read -r f; do rm -f -- \(dir)/\"$f\"; done"
        }
    }

    // MARK: Backup listings

    public enum Backups {
        public static func listMailcow(backupDir: String) -> String {
            "ls -lht \(ShellQuoting.singleQuoted(backupDir))"
        }

        public static func listVaultwarden(backupDir: String) -> String {
            "ls -lht \(ShellQuoting.argument(backupDir))/*.gpg"
        }

        public static func makeDir(_ dir: String) -> String {
            "mkdir -p \(ShellQuoting.singleQuoted(dir))"
        }

        public static func latestEntrySize(dir: String) -> String {
            "du -sh \"$(ls -1dt \(ShellQuoting.argument(dir))/* | head -n 1)\" | tail -n 1"
        }

        public static func latestShareableFile(dir: String) -> String {
            "f=\"$(ls -1dt \(ShellQuoting.argument(dir))/* 2>/dev/null | head -n 1)\"; { [ -f \"$f\" ] && [ -r \"$f\" ] && printf '%s\\n' \"$f\"; } || true"
        }

        /// Root-owned wrapper for backup housekeeping
        public static let controlScriptPath = "/opt/gryonixnexus-backup-ctl.sh"

        public static let controlDoneMarker = "GRYONIXNEXUS_BACKUP_CTL_DONE"

        /// Line a finished archive prints: `<marker> <bytes> <path>`
        public static let backupDoneMarker = "GRYONIXNEXUS_BACKUP_DONE"

        /// Line `estimate` prints: `<marker> <data bytes> <free bytes>`
        public static let estimateMarker = "GRYONIXNEXUS_BACKUP_ESTIMATE"

        public static let encryptFlag = "--encrypt"
        public static let noEncryptFlag = "--no-encrypt"

        /// `sudo <wrapper> backup <service> [--encrypt|--no-encrypt]`
        public static func run(target: String, encrypt: Bool) -> String {
            "sudo \(controlScriptPath) backup \(target) \(encrypt ? encryptFlag : noEncryptFlag)"
        }

        public static func estimate(target: String) -> String {
            "sudo \(controlScriptPath) estimate \(target)"
        }

        public static let showDestination = "sudo \(controlScriptPath) show-destination"

        /// `sudo <wrapper> set-destination <kind> <host> <port> <user> <path> <bucket> <keep>`
        public static func setDestination(kind: String, host: String, port: Int,
                                          user: String, path: String, bucket: String,
                                          keep: Int) -> String {
            let quoted = [kind, host, String(port), user, path, bucket, String(keep)]
                .map(ShellQuoting.singleQuoted)
                .joined(separator: " ")
            return "sudo \(controlScriptPath) set-destination \(quoted)"
        }

        public static let testDestination = "sudo \(controlScriptPath) test-destination"

        public static let showDrives = "sudo \(controlScriptPath) show-drives"

        /// `sudo <wrapper> set-drives <mode> <0|1> [uuids...]`
        public static func setDrives(mode: String, encrypt: Bool, uuids: [String]) -> String {
            let quoted = ([mode, encrypt ? "1" : "0"] + uuids).map(ShellQuoting.singleQuoted)
            return "sudo \(controlScriptPath) set-drives \(quoted.joined(separator: " "))"
        }

        /// What `test-destination` prints: `<marker> <0|1> <detail>`
        public static let destinationTestMarker = "GRYONIXNEXUS_DEST_TEST"

        /// `sudo <wrapper> delete <path>`
        public static func delete(path: String) -> String {
            "sudo \(controlScriptPath) delete \(ShellQuoting.singleQuoted(path))"
        }

        public enum Schedule: Sendable, Hashable, Codable {
            case off
            /// Every `count` hours at minute `minute` of the hour
            case hours(count: Int, minute: Int)
            /// Every `count` days at `hour`:`minute`
            case days(count: Int, hour: Int, minute: Int)

            public var isOn: Bool { self != .off }

            /// The wrapper's argument
            public var wrapperArgument: String {
                switch self {
                case .off:
                    return "off"
                case .hours(let count, let minute):
                    let n = min(max(count, 1), 23)
                    return String(format: "every:%dh@00:%02d", n, min(max(minute, 0), 59))
                case .days(let count, let hour, let minute):
                    let n = min(max(count, 1), 28)
                    return String(format: "every:%dd@%02d:%02d", n,
                                  min(max(hour, 0), 23), min(max(minute, 0), 59))
                }
            }

            /// Parses what `wrapperArgument` writes into the config
            public init(wrapperArgument: String) {
                guard wrapperArgument.hasPrefix("every:"),
                      let atIndex = wrapperArgument.firstIndex(of: "@") else {
                    self = .off
                    return
                }
                let every = wrapperArgument[wrapperArgument.index(wrapperArgument.startIndex,
                                                                 offsetBy: 6)..<atIndex]
                let time = wrapperArgument[wrapperArgument.index(after: atIndex)...]
                let parts = time.split(separator: ":")
                guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
                      let unit = every.last, let count = Int(every.dropLast()) else {
                    self = .off
                    return
                }
                switch unit {
                case "h": self = .hours(count: count, minute: minute)
                case "d": self = .days(count: count, hour: hour, minute: minute)
                default: self = .off
                }
            }
        }

        /// `sudo <wrapper> set-schedule <schedule> <retention> [services...]`
        public static func setSchedule(_ schedule: Schedule, retention: Int,
                                       services: [String]) -> String {
            ("sudo \(controlScriptPath) set-schedule \(schedule.wrapperArgument) \(retention) "
                + services.joined(separator: " ")).trimmingCharacters(in: .whitespaces)
        }

        /// Reads the schedule config
        public static let readSchedule =
            "cat /etc/gryonixnexus/autobackup.conf 2>/dev/null || true"

        /// Stores the passphrase unattended encrypted backups are made with
        public static let setPassphrase = "sudo \(controlScriptPath) set-passphrase"
    }

    // MARK: Updates

    /// The update wrapper's surface
    public enum Updates {
        public static let controlScriptPath = "/opt/gryonixnexus-update-ctl.sh"
        public static let doneMarker = "GRYONIXNEXUS_UPDATE_CTL_DONE"

        /// One line per image that moved: `<marker> <service> <image>`
        public static let availableMarker = "GRYONIXNEXUS_UPDATE_AVAILABLE"
        public static let currentMarker = "GRYONIXNEXUS_UPDATE_CURRENT"
        /// `<marker> <service> <reason>`
        public static let unknownMarker = "GRYONIXNEXUS_UPDATE_UNKNOWN"
        public static let updatedMarker = "GRYONIXNEXUS_UPDATE_DONE"
        public static let rolledBackMarker = "GRYONIXNEXUS_UPDATE_ROLLED_BACK"
        public static let failedMarker = "GRYONIXNEXUS_UPDATE_FAILED"

        /// Ask what has moved
        public static func check(_ service: String?) -> String {
            "sudo \(controlScriptPath) check \(service ?? "--all")"
        }

        /// Apply one service's update
        public static func run(_ service: String) -> String {
            "sudo \(controlScriptPath) run \(ShellQuoting.singleQuoted(service))"
        }

        /// `sudo <wrapper> set-schedule <schedule> [services...]`
        public static func setSchedule(_ schedule: Backups.Schedule,
                                       services: [String]) -> String {
            ("sudo \(controlScriptPath) set-schedule \(schedule.wrapperArgument) "
                + services.joined(separator: " ")).trimmingCharacters(in: .whitespaces)
        }

        public static let readSchedule =
            "cat /etc/gryonixnexus/autoupdate.conf 2>/dev/null || true"

        public static let readStatus = "sudo \(controlScriptPath) status"
    }
}
