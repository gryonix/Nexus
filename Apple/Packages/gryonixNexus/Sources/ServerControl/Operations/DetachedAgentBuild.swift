import Foundation

public struct DetachedAgentBuild: Sendable {
    public static let exitMarker = "GRYONIXNEXUS_AGENT_BUILD_EXIT="
    public static let runningMarker = "GRYONIXNEXUS_AGENT_BUILD_RUNNING"
    public static let reconnectAttempts = 60
    private static let nothing: @Sendable () -> Void = {}

    public let home: String
    private let retryDelay: Duration

    public init(home: String, retryDelay: Duration = .seconds(5)) {
        self.home = home
        self.retryDelay = retryDelay
    }

    public var logPath: String { "\(home)/.gryonixnexus-agent-build.log" }
    public var pidPath: String { "\(home)/.gryonixnexus-agent-build.pid" }

    public struct Outcome: Sendable, Equatable {
        public let exitCode: Int
        public let transcript: String
    }

    // MARK: Commands

    /// Everything runs under bash, whatever the login shell is
    static func bash(_ script: String) -> String {
        "bash -c \(ShellQuoting.singleQuoted(script))"
    }

    public var runningCheck: String {
        Self.bash("kill -0 \"$(cat \(q(pidPath)) 2>/dev/null)\" 2>/dev/null && echo \(Self.runningMarker) || true")
    }

    /// setsid + nohup: the build survives the SSH session ending
    public func startCommand(fetchScript: String?, wrapper: String) -> String {
        let fetch = fetchScript.map { "bash \(q($0)); R=$?; rm -f \(q($0)); [ \"$R\" = 0 ] && " } ?? ""
        let job = "echo $$ > \(q(pidPath)); \(fetch)sudo -n \(wrapper); echo \(Self.exitMarker)$?"
        return Self.bash("rm -f \(q(pidPath)); : > \(q(logPath)); "
            + "setsid nohup bash -c \(q(job)) >> \(q(logPath)) 2>&1 < /dev/null & "
            + "for i in $(seq 50); do [ -s \(q(pidPath)) ] && break; sleep 0.1; done; echo started")
    }

    public func followCommand(fromLine line: Int) -> String {
        Self.bash("PID=\"$(cat \(q(pidPath)) 2>/dev/null)\"; "
            + "if [ -n \"$PID\" ] && kill -0 \"$PID\" 2>/dev/null; "
            + "then exec tail -n +\(line) --pid=\"$PID\" -F \(q(logPath)) 2>/dev/null; "
            + "else exec tail -n +\(line) \(q(logPath)) 2>/dev/null; fi")
    }

    private func q(_ value: String) -> String { ShellQuoting.singleQuoted(value) }

    // MARK: Watching

    public func isRunning(runner: any SSHCommandRunner, host: SSHHostID) async throws -> Bool {
        try await runner.run(runningCheck, on: host, timeout: .seconds(30)).stdout.contains(Self.runningMarker)
    }

    public func follow(runner: any SSHCommandRunner, host: SSHHostID,
                       onOutput: @escaping @Sendable (String) -> Void,
                       onReconnect: @escaping @Sendable (Error) -> Void,
                       onReconnected: @escaping @Sendable () -> Void = {}) async throws -> Outcome {
        var reader = BuildLogReader()
        var failures = 0
        var dropped = false
        while true {
            try Task.checkCancellation()
            do {
                let back = dropped ? onReconnected : Self.nothing
                dropped = false
                if let done = try await readOnce(&reader, runner: runner, host: host,
                                                 onOutput: onOutput, onFirstLine: back) {
                    return done
                }
                try await Task.sleep(for: .seconds(1))
            } catch let error where !(error is CancellationError) {
                failures += 1
                guard failures <= Self.reconnectAttempts else { throw error }
                dropped = true
                onReconnect(error)
                try await Task.sleep(for: retryDelay)
            }
            reader.dropPartial()
        }
    }

    private func readOnce(_ reader: inout BuildLogReader, runner: any SSHCommandRunner, host: SSHHostID,
                          onOutput: @escaping @Sendable (String) -> Void,
                          onFirstLine: @escaping @Sendable () -> Void) async throws -> Outcome? {
        let stream = runner.stream(followCommand(fromLine: reader.linesSeen + 1), on: host,
                                   timeout: .seconds(3 * 3600))
        var first = true
        for try await chunk in stream {
            guard case .stdout(let text) = chunk else { continue }
            if first { first = false; onFirstLine() }
            reader.feed(text).forEach(onOutput)
            if let code = reader.exitCode { return Outcome(exitCode: code, transcript: reader.transcript) }
        }
        if try await isRunning(runner: runner, host: host) { return nil }
        return Outcome(exitCode: -1, transcript: reader.transcript)
    }
}

/// Splits the log into lines and finds the exit marker
public struct BuildLogReader: Sendable {
    public private(set) var linesSeen = 0
    public private(set) var transcript = ""
    public private(set) var exitCode: Int?
    private var partial = ""

    public init() {}

    public mutating func feed(_ raw: String) -> [String] {
        partial = (partial + raw).replacingOccurrences(of: "\r\n", with: "\n")
        var lines: [String] = []
        while let newline = partial.firstIndex(of: "\n") {
            let line = String(partial[..<newline])
            partial.removeSubrange(...newline)
            linesSeen += 1
            if line.hasPrefix(DetachedAgentBuild.exitMarker) {
                exitCode = Int(line.dropFirst(DetachedAgentBuild.exitMarker.count)
                    .trimmingCharacters(in: .whitespaces)) ?? -1
                continue
            }
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            transcript += text + "\n"
            lines.append(text)
        }
        return lines
    }

    /// A cut line is read again from its start
    public mutating func dropPartial() { partial = "" }
}
