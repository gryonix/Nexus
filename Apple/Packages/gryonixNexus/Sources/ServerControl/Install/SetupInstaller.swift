import Foundation

public struct SetupInstaller: Sendable {
    private let runner: any SSHCommandRunner
    private let host: SSHHostID
    private let username: String
    private let runTimeout: Duration
    private let uploadTimeout: Duration
    private let sleeper: any SleepProvider

    public init(
        runner: any SSHCommandRunner,
        host: SSHHostID = .vps,
        username: String = "root",
        runTimeout: Duration = .seconds(3600),
        uploadTimeout: Duration = .seconds(30),
        sleeper: any SleepProvider = ContinuousClockSleeper()
    ) {
        self.runner = runner
        self.host = host
        self.username = username
        self.runTimeout = runTimeout
        self.uploadTimeout = uploadTimeout
        self.sleeper = sleeper
    }

    public func install(script: String, fileName: String,
                        skipDNSCheck: Bool = false,
                        skipServices: Bool = false) -> AsyncThrowingStream<SetupEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var detached = false
                do {
                    try await upload(script: script, to: fileName)
                    try await start(fileName, skipDNSCheck: skipDNSCheck, skipServices: skipServices)
                    detached = true
                    try await follow(fileName, into: continuation)
                    await wipe(fileName)
                    continuation.finish()
                } catch {
                    if !detached || Self.installEnded(error) { await wipe(fileName) }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Whether the script has ended, so its log can go
    private static func installEnded(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if case ServerControlError.installUnfollowable = error { return false }
        return true
    }

    // MARK: - Steps

    /// The script carries keys, so it travels on stdin
    private func upload(script: String, to fileName: String) async throws {
        let file = ShellQuoting.singleQuoted(fileName)
        let command = "umask 077 && rm -f \(file) && cat > \(file)"
        let result = try await runner.run(command, feeding: script, on: host, timeout: uploadTimeout)
        guard result.succeeded else {
            throw ServerControlError.commandFailed(command: command, exitCode: result.exitCode,
                                                   stderr: OutputTail.tail(result.stderr))
        }
    }

    private func start(_ fileName: String, skipDNSCheck: Bool, skipServices: Bool) async throws {
        let file = ShellQuoting.singleQuoted(fileName)
        let log = ShellQuoting.singleQuoted(Self.logName(for: fileName))
        var envAssignments: [String] = []
        if skipDNSCheck { envAssignments.append("GRYONIXNEXUS_SKIP_DNS_CHECK=1") }
        if skipServices { envAssignments.append("GRYONIXNEXUS_SKIP_SERVICES=1") }
        let interpreter = envAssignments.isEmpty
            ? "bash" : "env \(envAssignments.joined(separator: " ")) bash"
        let run = username == "root" ? "\(interpreter) \(file)" : "sudo -n \(interpreter) \(file)"
        let payload = "\(run) >> \(log) 2>&1; echo \"\(SetupProgressParser.exitMarker)$?\" >> \(log)"
        let detach = "command -v setsid >/dev/null 2>&1 && DETACH=setsid || DETACH="
        try await self.run("""
        (umask 077 && rm -f \(log) && : > \(log)) && \(detach); \
        $DETACH sh -c \(ShellQuoting.singleQuoted(payload)) </dev/null >/dev/null 2>&1 &
        """)
    }

    /// Streams the detached run's log, re-attaching across dropped sessions
    private func follow(_ fileName: String,
                        into continuation: AsyncThrowingStream<SetupEvent, Error>.Continuation) async throws {
        var parser = SetupProgressParser()
        var tail = ""
        var linesConsumed = 0
        var attempt = 0

        func emit(_ events: [SetupEvent]) {
            for event in events { continuation.yield(event) }
        }

        while true {
            let command = Self.followCommand(fileName: fileName, fromLine: linesConsumed + 1)
            let deliveredBefore = linesConsumed
            do {
                for try await chunk in runner.stream(command, on: host, timeout: runTimeout) {
                    switch chunk {
                    case .stdout(let text), .stderr(let text):
                        linesConsumed += text.utf8.reduce(0) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
                        tail = OutputTail.tail(tail + text)
                        emit(parser.consume(text))
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
            }

            if parser.exitCode != nil {
                emit(parser.finish())
                break
            }

            if linesConsumed > deliveredBefore { attempt = 0 }

            guard attempt < Self.maxReattaches, !Task.isCancelled else {
                throw ServerControlError.installUnfollowable
            }
            attempt += 1
            parser.discardPartialLine()
            emit([.reconnecting(attempt: attempt)])
            await runner.disconnect()
            try? await sleeper.sleep(for: .seconds(min(5 * attempt, 20)))
        }

        if let code = parser.exitCode, code != 0 {
            throw ServerControlError.commandFailed(command: "install", exitCode: code,
                                                   stderr: OutputTail.tail(tail))
        }
        guard parser.sawDone else {
            throw ServerControlError.commandFailed(command: "install", exitCode: nil,
                                                   stderr: OutputTail.tail(tail))
        }
    }

    static func logName(for fileName: String) -> String { fileName + ".log" }

    static func followCommand(fileName: String, fromLine: Int) -> String {
        let log = ShellQuoting.singleQuoted(Self.logName(for: fileName))
        let script = """
        n=\(fromLine)
        while :; do
          tot=$(wc -l < \(log) 2>/dev/null || echo 0)
          if [ "$tot" -ge "$n" ]; then sed -n "${n},${tot}p" \(log); n=$((tot + 1)); fi
          if [ "$tot" -ge 1 ] && sed -n "${tot}p" \(log) | grep -q "^\(SetupProgressParser.exitMarker)"; then exit 0; fi
          sleep 1
        done
        """
        return "sh -c \(ShellQuoting.singleQuoted(script))"
    }

    private static let maxReattaches = 5

    /// Best-effort cleanup of both the script and any staging leftover
    private func wipe(_ fileName: String) async {
        let file = ShellQuoting.singleQuoted(fileName)
        let staging = ShellQuoting.singleQuoted(fileName + ".b64")
        let log = ShellQuoting.singleQuoted(Self.logName(for: fileName))
        let runner = self.runner
        let host = self.host
        let timeout = self.uploadTimeout
        _ = await Task.detached {
            try? await runner.run("rm -f \(staging) \(file) \(log)", on: host, timeout: timeout)
        }.value
    }

    @discardableResult
    private func run(_ command: String) async throws -> ExecResult {
        let result = try await runner.run(command, on: host, timeout: uploadTimeout)
        guard result.succeeded else {
            throw ServerControlError.commandFailed(command: command, exitCode: result.exitCode,
                                                   stderr: OutputTail.tail(result.stderr))
        }
        return result
    }
}
