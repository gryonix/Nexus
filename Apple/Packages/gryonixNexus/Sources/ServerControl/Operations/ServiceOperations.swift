import Foundation
import ServiceCatalog

/// Progress of the encrypted vaultwarden backup
public enum VWBackupEvent: Sendable, Hashable {
    case stoppingContainer
    case archiving
    case encrypting
    case startingContainer
    case rotating
    /// Human-readable size of the resulting .gpg file
    case completed(sizeText: String)
}

public struct ServiceOperations: Sendable {
    private let runner: any SSHCommandRunner
    private let deployment: Deployment
    private let service: any ManagedService
    private let language: AppLanguage
    /// Injected for deterministic archive names in tests
    private let now: @Sendable () -> Date

    public init(runner: any SSHCommandRunner, deployment: Deployment,
                service: any ManagedService,
                language: AppLanguage = .en,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.runner = runner
        self.deployment = deployment
        self.service = service
        self.language = language
        self.now = now
    }

    private var context: ServiceContext { deployment.serviceContext }
    /// The machine THIS service runs on
    private var host: SSHHostID { deployment.host(running: service.id) }
    private var actions: ServiceActions { service.actions(context) }

    private func timeout(_ timeoutClass: ServiceCommand.TimeoutClass) -> Duration {
        deployment.timeouts.duration(for: timeoutClass)
    }

    // MARK: - Status

    /// One row per container
    public func status() async throws -> [ContainerStatus] {
        switch actions.statusProbe {
        case .composeProject(_, let command):
            let output = try await runSucceeding(command.command, timeout: timeout(.quick))
            return try DockerComposePSParser.parse(output)

        case .container(let name, let list):
            let output = try await runSucceeding(list.command, timeout: timeout(.quick))
            let all = try DockerPSParser.parse(output)
            guard let container = DockerPSParser.find(container: name, in: all) else {
                return [ContainerStatus(name: name, status: "not running")]
            }
            return [container]
        }
    }

    // MARK: - Power / update

    public var canRestart: Bool { actions.restart != nil }
    public var canStart: Bool { actions.start != nil }
    public var canStop: Bool { actions.stop != nil }
    /// Can the dashboard update this service?
    public var canUpdate: Bool { service.updateSpec(context).flavour == .composePull }

    /// Destructive: the UI confirms first
    public func restart() async throws {
        guard let restart = actions.restart else {
            throw ServerControlError.notConfigured(L10nOperations.restartNotSupported(language, service: service.displayName))
        }
        _ = try await runSucceeding(restart.command, timeout: timeout(restart.timeoutClass))
    }

    /// Brings every container of the service back up
    public func start() async throws {
        guard let start = actions.start else {
            throw ServerControlError.notConfigured(L10nOperations.startNotSupported(language, service: service.displayName))
        }
        _ = try await runSucceeding(start.command, timeout: timeout(start.timeoutClass))
    }

    /// Destructive: the service goes offline until it is started again
    public func stop() async throws {
        guard let stop = actions.stop else {
            throw ServerControlError.notConfigured(L10nOperations.stopNotSupported(language, service: service.displayName))
        }
        _ = try await runSucceeding(stop.command, timeout: timeout(stop.timeoutClass))
    }

    // MARK: - Logs

    public var canReadLogs: Bool { actions.logs != nil }

    /// The tail of this service's container log, as lines
    public func logs() async throws -> [String] {
        guard let logs = actions.logs else {
            throw ServerControlError.notConfigured(
                L10nOperations.logsNotSupported(language, service: service.displayName))
        }
        let result = try await runner.run(logs.command, on: host,
                                          timeout: timeout(logs.timeoutClass))
        let combined = [result.stdout, result.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return ANSIStripper.strip(combined)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            .reversed().drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }.reversed()
            .map { $0 }
    }

    // MARK: - Uninstall

    /// The wrapper's `case` label for this service
    public var uninstallTarget: String {
        if ServiceID.vpnProtocols.contains(service.id) || service.id == .vpnPanel {
            return CommandCatalog.Uninstall.vpnTarget
        }
        if service.id == .tailscaleNode { return ServiceID.headscale.rawValue }
        return service.id.rawValue
    }

    public func uninstall(purge: PurgeOptions,
                          onChunk: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        let command = CommandCatalog.Uninstall.run(target: uninstallTarget, purge: purge)
        let box = OutputBox()
        try await DetachedJobs.run(command, kind: .uninstall, subject: uninstallTarget,
                                   on: host, runner: runner,
                                   quickTimeout: timeout(.quick),
                                   runTimeout: timeout(.long)) { text in
            box.append(text)
            onChunk(text)
        }
        let accumulated = box.text
        let output = ANSIStripper.strip(accumulated)
        guard output.contains(CommandCatalog.Uninstall.doneMarker) else {
            throw ServerControlError.commandFailure(command: command, exitCode: nil,
                                                    stderr: OutputTail.tail(output))
        }
        return OutputTail.tail(output.replacingOccurrences(of: CommandCatalog.Uninstall.doneMarker,
                                                           with: ""))
    }

    // MARK: - Backups

    public enum BackupKind: Sendable, Hashable {
        case none
        /// One-shot wrapper on the server; no client input needed
        case wrapper
        /// Needs a user passphrase; runs the stop→tar→encrypt→start flow
        case encrypted
    }

    public var backupKind: BackupKind {
        switch actions.backup {
        case nil: return .none
        case .wrapperScript: return .wrapper
        case .encryptedVolume: return .encrypted
        }
    }

    private var backupListDir: String? { actions.backup?.listDirectory }

    public var backupWrapperSpec: BackupWrapperSpec? { actions.backup?.wrapper }

    public var backupEncryptsByDefault: Bool {
        switch actions.backup {
        case nil: return false
        case .wrapperScript(let spec): return spec.encryptsByDefault
        // Every vaultwarden archive is encrypted; that is the whole flavour.
        case .encryptedVolume: return true
        }
    }

    public func listBackups() async throws -> [BackupEntry] {
        guard let dir = backupListDir else { return [] }
        let command: String
        switch actions.backup {
        case .encryptedVolume:
            command = CommandCatalog.Backups.listVaultwarden(backupDir: dir)
        default:
            command = CommandCatalog.Backups.listMailcow(backupDir: dir)
        }
        let result = try await runner.run(command, on: host, timeout: timeout(.quick))
        return BackupListParser.parse(result.stdout)
            .filter { $0.displayName != CommandCatalog.Restore.stagingDirectoryName }
    }

    public func latestShareableBackupPath() async throws -> String? {
        guard let dir = backupListDir else { return nil }
        let result = try await runner.run(CommandCatalog.Backups.latestShareableFile(dir: dir),
                                          on: host, timeout: timeout(.quick))
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// Deletes one backup through the root-owned wrapper
    public func deleteBackup(path: String) async throws {
        guard let dir = backupListDir else {
            throw ServerControlError.notConfigured(
                L10nOperations.backupKindNotSupported(language, service: service.displayName))
        }
        guard CommandCatalog.Restore.isValidArchivePath(path, backupDir: dir) else {
            throw ServerControlError.notConfigured(
                L10nOperations.restoreBadPath(language, path: path))
        }
        let output = try await runSucceeding(CommandCatalog.Backups.delete(path: path),
                                             timeout: timeout(.quick))
        guard output.contains(CommandCatalog.Backups.controlDoneMarker) else {
            throw ServerControlError.commandFailure(command: "delete backup", exitCode: nil,
                                                    stderr: OutputTail.tail(output))
        }
    }

    /// Absolute path of a listed backup
    public func backupPath(for entry: BackupEntry) -> String? {
        guard let dir = backupListDir else { return nil }
        return entry.name.hasPrefix("/") ? entry.name : "\(dir)/\(entry.name)"
    }

    public func estimateBackup() async throws -> BackupEstimate? {
        guard let spec = backupWrapperSpec else { return nil }
        let result = try await runner.run(CommandCatalog.Backups.estimate(target: spec.wrapperTarget),
                                          on: host, timeout: timeout(.quick))
        guard result.succeeded else {
            throw ServerControlError.commandFailure(command: "estimate backup",
                                                    exitCode: result.exitCode,
                                                    stderr: result.stderr)
        }
        return BackupEstimate(output: result.stdout)
    }

    @discardableResult
    public func backup(encrypt: Bool? = nil, passphrase: String? = nil,
                       onChunk: @escaping @Sendable (String) -> Void = { _ in }) async throws -> BackupOutcome {
        guard let spec = backupWrapperSpec else {
            return try await encryptedVolumeBackup(passphrase: passphrase, onChunk: onChunk)
        }
        let encrypting = encrypt ?? spec.encryptsByDefault
        let secret = (encrypting && !(passphrase ?? "").isEmpty) ? passphrase : nil
        return try await wrapperBackup(target: spec.wrapperTarget, backupDir: spec.backupDir,
                                       encrypting: encrypting, secret: secret,
                                       timeoutClass: spec.run.timeoutClass, onChunk: onChunk)
    }

    /// A typed password encrypts here; without one, the stored key
    private func encryptedVolumeBackup(passphrase: String?,
                                       onChunk: @escaping @Sendable (String) -> Void) async throws -> BackupOutcome {
        guard case .encryptedVolume(_, _, let backupDir, _)? = actions.backup,
              let target = actions.restore?.wrapperTarget else {
            throw ServerControlError.notConfigured(
                L10nOperations.backupKindNotSupported(language, service: service.displayName))
        }
        guard let passphrase, !passphrase.isEmpty else {
            return try await wrapperBackup(target: target, backupDir: backupDir, encrypting: true,
                                           secret: nil, timeoutClass: .long, onChunk: onChunk)
        }
        var size = ""
        for try await event in encryptedBackup(passphrase: passphrase) {
            if case .completed(let sizeText) = event { size = sizeText }
        }
        return BackupOutcome(sizeBytes: nil, path: nil, log: size)
    }

    private func wrapperBackup(target: String, backupDir: String, encrypting: Bool, secret: String?,
                               timeoutClass: ServiceCommand.TimeoutClass,
                               onChunk: @escaping @Sendable (String) -> Void) async throws -> BackupOutcome {
        _ = try await runner.run(CommandCatalog.Backups.makeDir(backupDir), on: host, timeout: timeout(.quick))
        let command = CommandCatalog.Backups.run(target: target, encrypt: encrypting)
        let box = OutputBox()
        try await DetachedJobs.run(command, kind: .backup, subject: target,
                                   on: host, runner: runner,
                                   quickTimeout: timeout(.quick),
                                   runTimeout: timeout(timeoutClass),
                                   secret: secret) { text in
            box.append(text)
            onChunk(text)
        }
        let output = ANSIStripper.strip(box.text)
        guard output.contains(CommandCatalog.Backups.controlDoneMarker) else {
            throw ServerControlError.commandFailure(command: "backup \(target)", exitCode: nil,
                                                    stderr: OutputTail.tail(output))
        }
        let log = OutputTail.tail(
            output.replacingOccurrences(of: CommandCatalog.Backups.controlDoneMarker, with: ""))
        if let announced = BackupOutcome(output: output, log: log) { return announced }
        let size = try await runner.run(CommandCatalog.Backups.latestEntrySize(dir: backupDir),
                                        on: host, timeout: timeout(.quick))
        return BackupOutcome(sizeBytes: nil, path: nil,
                             log: size.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Wrapper-script backup with the spec's own encryption default
    public func runWrapperBackup() async throws -> String {
        try await backup().log
    }

    public func encryptedBackup(passphrase: String) -> AsyncThrowingStream<VWBackupEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await performEncryptedBackup(passphrase: passphrase) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func performEncryptedBackup(passphrase: String,
                                        yield: @Sendable (VWBackupEvent) -> Void) async throws {
        guard case .encryptedVolume(let container, let dataPath, let backupDir, let commands)? = actions.backup else {
            throw ServerControlError.notConfigured(L10nOperations.encryptedBackupNotSupported(language, service: service.displayName))
        }
        let stagingPath = BackupSpec.stagingArchivePath(backupDir: backupDir, container: container)
        let gpgPath = "\(backupDir)/\(container)-\(Self.timestamp(now())).tar.gz.gpg"

        _ = try await runner.run(CommandCatalog.Backups.makeDir(backupDir), on: host,
                                 timeout: timeout(.quick))

        yield(.stoppingContainer)
        try await step("stop container", commands.stop.command, timeout: timeout(.restart))

        do {
            yield(.archiving)
            try await step("archive data",
                           CommandCatalog.Vaultwarden.archive(dataPath: dataPath, archivePath: stagingPath),
                           timeout: timeout(.long))
            try await step("chown archive",
                           CommandCatalog.Vaultwarden.chownArchive(user: deployment.entry.user,
                                                                   archivePath: stagingPath),
                           timeout: timeout(.quick))

            yield(.encrypting)
            try await step("encrypt archive",
                           CommandCatalog.Vaultwarden.encrypt(archivePath: stagingPath, outputPath: gpgPath),
                           feeding: passphrase,
                           timeout: timeout(.long))
            try await step("remove plain archive",
                           CommandCatalog.Vaultwarden.removePlainArchive(archivePath: stagingPath),
                           timeout: timeout(.quick))
        } catch {
            _ = try? await runner.run(CommandCatalog.Vaultwarden.removePlainArchive(archivePath: stagingPath),
                                      on: host, timeout: timeout(.quick))
            yield(.startingContainer)
            _ = try? await runner.run(commands.start.command, on: host, timeout: timeout(.restart))
            throw error
        }

        yield(.startingContainer)
        try await step("start container", commands.start.command, timeout: timeout(.restart))

        let size = try await runner.run(CommandCatalog.Vaultwarden.backupSize(gpgPath: gpgPath),
                                        on: host, timeout: timeout(.quick))

        yield(.rotating)
        _ = try await runner.run(CommandCatalog.Vaultwarden.rotate(backupDir: backupDir,
                                                                   retention: context.settings.backupRetention),
                                 on: host, timeout: timeout(.quick))

        yield(.completed(sizeText: size.stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    // MARK: - Restore

    public var restoreSpec: RestoreSpec? { actions.restore }

    /// Backups on the server that can be restored, newest first
    public func listRestorableBackups() async throws -> [BackupEntry] {
        guard actions.restore != nil else { return [] }
        return try await listBackups()
    }

    public static let uploadLimitBytes = 512 * 1_048_576

    public func uploadBackup(_ data: Data, fileName: String,
                             using browser: any RemoteFileBrowser,
                             maxBytes: Int = ServiceOperations.uploadLimitBytes) async throws -> String {
        guard let restore = actions.restore else {
            throw ServerControlError.notConfigured(
                L10nOperations.restoreNotSupported(language, service: service.displayName))
        }
        guard data.count <= maxBytes else {
            throw ServerControlError.fileTooLarge(path: fileName,
                                                  size: UInt64(data.count),
                                                  limit: UInt64(maxBytes))
        }
        let safeName = Self.sanitizedUploadName(fileName)
        let directory = CommandCatalog.Restore.stagingDirectory(backupDir: restore.backupDir)
        _ = try await runner.run(CommandCatalog.Backups.makeDir(directory), on: host,
                                 timeout: timeout(.quick))
        let path = "\(directory)/\(safeName)"
        try await browser.uploadFile(data, to: path, on: host)
        return path
    }

    static func sanitizedUploadName(_ name: String) -> String {
        let base = name.split(separator: "/").last.map(String.init) ?? name
        let allowed = base.filter { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
        let cleaned = allowed.replacingOccurrences(of: "..", with: ".")
        return cleaned.isEmpty ? "upload.tar.gz" : cleaned
    }

    /// Restores this service from `archivePath` on the server
    public func restore(archivePath: String, passphrase: String? = nil,
                        onChunk: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        guard let restore = actions.restore else {
            throw ServerControlError.notConfigured(
                L10nOperations.restoreNotSupported(language, service: service.displayName))
        }
        guard CommandCatalog.Restore.isValidArchivePath(archivePath, backupDir: restore.backupDir) else {
            throw ServerControlError.notConfigured(
                L10nOperations.restoreBadPath(language, path: archivePath))
        }
        let target = restore.wrapperTarget
        guard CommandCatalog.Restore.isValidTarget(target) else {
            throw ServerControlError.notConfigured(
                L10nOperations.restoreNotSupported(language, service: service.displayName))
        }
        let command = CommandCatalog.Restore.run(target: target, archivePath: archivePath)
        var secret: String?
        if restore.needsPassphrase(for: archivePath) {
            guard let passphrase, !passphrase.isEmpty else {
                throw ServerControlError.notConfigured(
                    L10nOperations.restoreNeedsPassphrase(language, service: service.displayName))
            }
            secret = passphrase
        }

        let box = OutputBox()
        try await DetachedJobs.run(command, kind: .restore, subject: target,
                                   on: host, runner: runner,
                                   quickTimeout: timeout(.quick),
                                   runTimeout: timeout(.long),
                                   secret: secret) { text in
            box.append(text)
            onChunk(text)
        }
        let output = ANSIStripper.strip(box.text)
        guard output.contains(CommandCatalog.Restore.doneMarker) else {
            throw ServerControlError.commandFailure(command: "restore \(target)",
                                                    exitCode: nil,
                                                    stderr: OutputTail.tail(output))
        }
        return OutputTail.tail(output.replacingOccurrences(of: CommandCatalog.Restore.doneMarker,
                                                          with: ""))
    }

    // MARK: - Helpers

    private func runSucceeding(_ command: String, timeout: Duration) async throws -> String {
        let result = try await runner.run(command, on: host, timeout: timeout)
        guard result.succeeded else {
            throw ServerControlError.commandFailure(command: command,
                                                    exitCode: result.exitCode,
                                                    stderr: result.stderr)
        }
        return result.stdout
    }

    /// A step fed a secret on stdin; output stays hidden
    private func step(_ label: String, _ command: String, feeding secret: String,
                      timeout: Duration) async throws {
        let result = try await runner.run(command, feeding: secret, on: host, timeout: timeout)
        try check(result, label: label, command: command, sensitive: true)
    }

    private func step(_ label: String, _ command: String, timeout: Duration,
                      sensitive: Bool = false) async throws {
        let result = try await runner.run(command, on: host, timeout: timeout)
        try check(result, label: label, command: command, sensitive: sensitive)
    }

    private func check(_ result: ExecResult, label: String, command: String,
                       sensitive: Bool) throws {
        guard result.succeeded else {
            if ServerControlError.stderrAsksForASudoPassword(result.stderr) {
                throw ServerControlError.sudoPasswordRequired(command: sensitive ? label : command)
            }
            throw ServerControlError.commandFailed(command: sensitive ? label : command,
                                                   exitCode: result.exitCode,
                                                   stderr: sensitive ? "" : result.stderr)
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
