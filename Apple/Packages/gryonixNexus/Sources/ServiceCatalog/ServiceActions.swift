/// Declarative management surface of a service: which commands the dashboard
/// runs. Parsing and orchestration live in ServerControl; this layer only
/// names the commands so sudoers generation sees the exact same strings.
public struct ServiceActions: Sendable {
    public let statusProbe: StatusProbe
    /// Destructive — the UI confirms before running
    public let restart: ServiceCommand?
    /// Brings the whole service up again after `stop`
    public let start: ServiceCommand?
    public let stop: ServiceCommand?
    /// Reading this service's container log
    public let logs: ServiceCommand?
    public let backup: BackupSpec?
    public let restore: RestoreSpec?

    public init(statusProbe: StatusProbe, restart: ServiceCommand? = nil,
                start: ServiceCommand? = nil, stop: ServiceCommand? = nil,
                backup: BackupSpec? = nil,
                restore: RestoreSpec? = nil,
                logs: ServiceCommand? = nil) {
        self.statusProbe = statusProbe
        self.restart = restart
        self.start = start
        self.stop = stop
        self.backup = backup
        self.restore = restore
        self.logs = logs ?? ServicePower.containerLogs(from: statusProbe)
    }
}

extension ServicePower {
    public static func containerLogs(from probe: StatusProbe) -> ServiceCommand? {
        let arguments: String
        switch probe {
        case .container(let name, _):
            arguments = "logs --tail 500 --timestamps \(name)"
        case .composeProject(let project, _):
            arguments = "compose -p \(project) logs --tail 500 --timestamps"
        }
        return ServiceCommand(
            PrivilegedCommand(binaryPath: "/usr/bin/docker", arguments: arguments),
            timeoutClass: .quick,
            streamsOutput: true
        )
    }
}

public enum ServicePower {
    public static func compose(project: String, _ verb: String,
                               timeoutClass: ServiceCommand.TimeoutClass = .restart) -> ServiceCommand {
        ServiceCommand(PrivilegedCommand(binaryPath: "/usr/bin/docker",
                                         arguments: "compose -p \(project) \(verb)"),
                       timeoutClass: timeoutClass)
    }

    public static func container(_ name: String, _ verb: String,
                                 timeoutClass: ServiceCommand.TimeoutClass = .restart) -> ServiceCommand {
        ServiceCommand(PrivilegedCommand(binaryPath: "/usr/bin/docker",
                                         arguments: "\(verb) \(name)"),
                       timeoutClass: timeoutClass)
    }
}

/// How a service is put back from a backup
public struct RestoreSpec: Sendable, Hashable {
    /// The one wrapper every restore goes through
    public static let wrapperPath = "/opt/gryonixnexus-restore.sh"

    /// Service label passed to the wrapper as its first argument
    public let wrapperTarget: String
    /// Directory the app lists restorable backups from, and uploads into
    public let backupDir: String
    public let needsPassphrase: Bool
    public let privileged: PrivilegedCommand

    public init(wrapperTarget: String, backupDir: String, needsPassphrase: Bool,
                privileged: PrivilegedCommand) {
        self.wrapperTarget = wrapperTarget
        self.backupDir = backupDir
        self.needsPassphrase = needsPassphrase
        self.privileged = privileged
    }

    /// Suffix the wrapper (and gpg) recognise as an encrypted archive
    public static let encryptedSuffix = ".gpg"

    /// Whether restoring THIS archive needs a passphrase
    public func needsPassphrase(for archivePath: String) -> Bool {
        needsPassphrase || archivePath.hasSuffix(Self.encryptedSuffix)
    }
}

/// How to read the service's health
public enum StatusProbe: Sendable, Hashable {
    /// `sudo docker compose -p <project> ps` — one row per container
    case composeProject(project: String, list: PrivilegedCommand)
    case container(name: String, list: PrivilegedCommand)

    public var privilegedCommands: [PrivilegedCommand] {
        switch self {
        case .composeProject(_, let list): return [list]
        case .container(_, let list): return [list]
        }
    }
}

public struct ServiceCommand: Sendable, Hashable {
    public enum TimeoutClass: Sendable, Hashable { case quick, restart, long }

    public let privileged: PrivilegedCommand
    public let timeoutClass: TimeoutClass
    public let streamsOutput: Bool
    public let workingDirectory: String?

    public init(_ privileged: PrivilegedCommand, timeoutClass: TimeoutClass,
                streamsOutput: Bool = false, workingDirectory: String? = nil) {
        self.privileged = privileged
        self.timeoutClass = timeoutClass
        self.streamsOutput = streamsOutput
        self.workingDirectory = workingDirectory
    }

    public var command: String {
        guard let workingDirectory else { return privileged.command }
        return "cd \(workingDirectory) && \(privileged.command)"
    }
}

/// Backup flavors
public enum BackupSpec: Sendable {
    case wrapperScript(BackupWrapperSpec)
    case encryptedVolume(container: String, dataPath: String, backupDir: String,
                         stopStart: EncryptedVolumeCommands)

    /// Directory the app lists this service's backups from
    public var listDirectory: String {
        switch self {
        case .wrapperScript(let spec): return spec.backupDir
        case .encryptedVolume(_, _, let backupDir, _): return backupDir
        }
    }

    public var wrapper: BackupWrapperSpec? {
        if case .wrapperScript(let spec) = self { return spec }
        return nil
    }

    public var encryptsByDefault: Bool {
        switch self {
        case .wrapperScript(let spec): return spec.encryptsByDefault
        case .encryptedVolume: return true
        }
    }

    public func privilegedCommands(_ context: ServiceContext) -> [PrivilegedCommand] {
        switch self {
        case .wrapperScript(let spec):
            return [spec.run.privileged]
        case .encryptedVolume(let container, let dataPath, let backupDir, let commands):
            let staging = Self.stagingArchivePath(backupDir: backupDir, container: container)
            return [
                commands.stop,
                commands.start,
                PrivilegedCommand(binaryPath: "/bin/tar",
                                  arguments: Self.archiveArguments(dataPath: dataPath,
                                                                   archivePath: staging)),
                PrivilegedCommand(binaryPath: "/bin/chown",
                                  arguments: "\(context.sshUser) \(staging)")
            ]
        }
    }

    public static func stagingArchivePath(backupDir: String, container: String) -> String {
        "\(backupDir)/\(container)-backup.tar.gz"
    }

    /// tar's argument vector, in the order sudo matches it
    public static func archiveArguments(dataPath: String, archivePath: String) -> String {
        "czf \(archivePath) -C / \(archiveRelativePath(dataPath))"
    }

    /// `dataPath` without its leading slash — what tar receives after `-C /`
    public static func archiveRelativePath(_ dataPath: String) -> String {
        dataPath.hasPrefix("/") ? String(dataPath.dropFirst()) : dataPath
    }
}

public struct EncryptedVolumeCommands: Sendable, Hashable {
    public let stop: PrivilegedCommand
    public let start: PrivilegedCommand

    public init(stop: PrivilegedCommand, start: PrivilegedCommand) {
        self.stop = stop
        self.start = start
    }
}
