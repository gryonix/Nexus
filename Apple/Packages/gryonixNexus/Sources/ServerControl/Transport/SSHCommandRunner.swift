import Foundation

/// Which machine executes a command
public struct SSHHostID: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case slot(DeploymentNode.LegacySlot)
        /// Any machine added after nodes had identities of their own
        case node(UUID)
    }

    public let kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    public static let vps = SSHHostID(kind: .slot(.vps))
    /// Scenario B's services machine, reached through the entry machine
    public static let home = SSHHostID(kind: .slot(.home))

    public static func node(_ id: UUID) -> SSHHostID {
        SSHHostID(kind: .node(id))
    }

    /// The slot this host occupies, when it has one
    public var slot: DeploymentNode.LegacySlot? {
        if case .slot(let slot) = kind { return slot }
        return nil
    }
}

/// Outcome of a completed remote command
public struct ExecResult: Sendable, Hashable {
    /// nil when the channel closed without delivering an exit status
    public let exitCode: Int32?
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32?, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { exitCode == 0 }
}

/// A piece of live output from a streaming command
public enum ExecChunk: Sendable, Hashable {
    case stdout(String)
    case stderr(String)
}

/// The single seam between dashboard logic and the SSH implementation
public protocol SSHCommandRunner: Sendable {
    /// Runs a command to completion
    func run(_ command: String, on host: SSHHostID, timeout: Duration) async throws -> ExecResult

    func stream(_ command: String, on host: SSHHostID, timeout: Duration) -> AsyncThrowingStream<ExecChunk, Error>

    /// Sends a command without awaiting its exit status
    func fireAndForget(_ command: String, on host: SSHHostID) async throws

    /// Runs a command with `secret` on stdin, never in argv
    func run(_ command: String, feeding secret: String, on host: SSHHostID,
             timeout: Duration) async throws -> ExecResult

    func disconnect() async
}

extension SSHCommandRunner {
    public func run(_ command: String, feeding secret: String, on host: SSHHostID,
                    timeout: Duration) async throws -> ExecResult {
        guard let files = self as? any RemoteFileBrowser else {
            throw ServerControlError.notConfigured("this connection cannot pass a secret privately")
        }
        return try await SecretFeed.run(command, feeding: secret, runner: self, files: files,
                                        on: host, timeout: timeout)
    }
}

/// Hands a secret to a command through a private file
public enum SecretFeed {
    static let stagingCommand = "umask 077 && mktemp -d"

    /// The command reading the staged file, then wiping it
    static func feedCommand(_ command: String, directory: String) -> String {
        let dir = ShellQuoting.singleQuoted(directory)
        return "( \(command) ) < \(dir)/s; rc=$?; rm -rf \(dir); exit $rc"
    }

    public static func run(_ command: String, feeding secret: String,
                           runner: any SSHCommandRunner, files: any RemoteFileBrowser,
                           on host: SSHHostID, timeout: Duration) async throws -> ExecResult {
        let staged = try await runner.run(stagingCommand, on: host, timeout: timeout)
        let directory = staged.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard staged.exitCode == 0, directory.hasPrefix("/"), !directory.contains("\n") else {
            throw ServerControlError.commandFailure(command: "stage secret", exitCode: staged.exitCode,
                                                    stderr: staged.stderr)
        }
        do {
            try await files.uploadFile(Data(secret.utf8), to: directory + "/s", on: host)
            return try await runner.run(feedCommand(command, directory: directory),
                                        on: host, timeout: timeout)
        } catch {
            _ = try? await runner.run("rm -rf \(ShellQuoting.singleQuoted(directory))",
                                      on: host, timeout: .seconds(15))
            throw error
        }
    }
}

/// Injected clock for poll loops so tests run instantly
public protocol SleepProvider: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct ContinuousClockSleeper: SleepProvider {
    public init() {}

    public func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}
