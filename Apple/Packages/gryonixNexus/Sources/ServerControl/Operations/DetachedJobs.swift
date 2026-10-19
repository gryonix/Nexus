import Foundation

public enum DetachedJobs {
    /// What kind of run this is
    public enum Kind: String, Sendable, CaseIterable {
        case update, backup, restore, uninstall, control
    }

    /// One run on the host
    public struct Job: Sendable, Equatable, Identifiable {
        public let id: String
        public let kind: Kind
        public let subject: String
        public let startedUnix: Int
        public let exitCode: Int?
        public var isRunning: Bool { exitCode == nil }
    }

    static let directory = ".gryonixnexus/jobs"

    /// The line the launcher appends when the work is over
    public static let exitMarker = "GRYONIXNEXUS_JOB_EXIT:"

    /// A job's id, which is also its file name
    public static func jobID(kind: Kind, subject: String, at time: Int) -> String {
        let safe = subject.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" }
        return "\(kind.rawValue)-\(String(safe))-\(time)"
    }

    public static func startCommand(_ command: String, jobID: String) -> String {
        let log = ShellQuoting.singleQuoted("\(directory)/\(jobID).log")
        let payload = "\(command) >> \(log) 2>&1; echo \"\(exitMarker)$?\" >> \(log)"
        return reservation(jobID) + ": > \(log) || exit 1; "
            + "command -v setsid >/dev/null 2>&1 && DETACH=setsid || DETACH=; "
            + "$DETACH sh -c \(ShellQuoting.singleQuoted(payload)) </dev/null >/dev/null 2>&1 & "
            + "echo \(ShellQuoting.singleQuoted(jobID))"
    }

    /// Launches a job reading its secret from stdin
    public static func startCommandWithSecret(_ command: String, jobID: String) -> String {
        let log = ShellQuoting.singleQuoted("\(directory)/\(jobID).log")
        let pass = ShellQuoting.singleQuoted("\(directory)/\(jobID).pass")
        let payload = "{ cat \(pass); rm -f \(pass); } | \(command) >> \(log) 2>&1; "
            + "echo \"\(exitMarker)$?\" >> \(log)"
        return reservation(jobID) + ": > \(log) "
            + "&& cat > \(pass) || exit 1; "
            + "command -v setsid >/dev/null 2>&1 && DETACH=setsid || DETACH=; "
            + "$DETACH sh -c \(ShellQuoting.singleQuoted(payload)) </dev/null >/dev/null 2>&1 & "
            + "echo \(ShellQuoting.singleQuoted(jobID))"
    }

    private static func reservation(_ jobID: String) -> String {
        let fields = jobID.split(separator: "-")
        let subject = fields.dropFirst().dropLast().joined(separator: "-")
        let lock = ShellQuoting.singleQuoted("\(directory)/\(subject).lock")
        return "umask 077; mkdir -p \(ShellQuoting.singleQuoted(directory)) || exit 1; "
            + "exec 9> \(lock); flock -n 9 || { echo 'An operation is already running for this service. Wait for it to finish.' >&2; exit 75; }; "
    }

    public static func followCommand(jobID: String, fromLine: Int) -> String {
        let log = ShellQuoting.singleQuoted("\(directory)/\(jobID).log")
        return """
        n=\(fromLine)
        while :; do
          tot=$(wc -l < \(log) 2>/dev/null || echo 0)
          if [ "$tot" -ge "$n" ]; then sed -n "${n},${tot}p" \(log); n=$((tot + 1)); fi
          if [ "$tot" -ge 1 ] && sed -n "${tot}p" \(log) | grep -q "^\(exitMarker)"; then exit 0; fi
          sleep 1
        done
        """
    }

    public static func listCommand() -> String {
        let dir = ShellQuoting.singleQuoted(directory)
        return """
        cd \(dir) 2>/dev/null || exit 0
        for f in *.log; do
          [ -e "$f" ] || continue
          id=${f%.log}
          last=$(tail -n 1 "$f" 2>/dev/null)
          case "$last" in
            \(exitMarker)*) code=${last#\(exitMarker)} ;;
            *) code=- ;;
          esac
          echo "$id $code"
        done
        """
    }

    /// Parses what [`listCommand`] printed
    public static func parseList(_ output: String) -> [Job] {
        var jobs: [Job] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count == 2 else { continue }
            let id = String(parts[0])
            let fields = id.split(separator: "-")
            guard fields.count >= 3, let kind = Kind(rawValue: String(fields[0])),
                  let started = Int(fields[fields.count - 1]) else { continue }
            let subject = fields[1..<(fields.count - 1)].joined(separator: "-")
            let code = parts[1] == "-" ? nil : Int(parts[1])
            jobs.append(Job(id: id, kind: kind, subject: subject,
                            startedUnix: started, exitCode: parts[1] == "-" ? nil : (code ?? -1)))
        }
        return jobs.sorted { $0.startedUnix > $1.startedUnix }
    }
}

extension DetachedJobs {
    public static func run(_ command: String,
                           kind: Kind,
                           subject: String,
                           on host: SSHHostID,
                           runner: any SSHCommandRunner,
                           quickTimeout: Duration,
                           runTimeout: Duration,
                           now: Int = Int(Date().timeIntervalSince1970),
                           /// Fed to the wrapper on stdin
                           secret: String? = nil,
                           started: (@Sendable (String) -> Void)? = nil,
                           onChunk: @escaping @Sendable (String) -> Void) async throws {
        let id = jobID(kind: kind, subject: subject, at: now)
        if let secret {
            _ = try await runner.run(startCommandWithSecret(command, jobID: id), feeding: secret,
                                     on: host, timeout: quickTimeout)
        } else {
            _ = try await runner.run(startCommand(command, jobID: id), on: host, timeout: quickTimeout)
        }
        started?(id)
        try await follow(jobID: id, from: 1, on: host, runner: runner,
                         runTimeout: runTimeout, onChunk: onChunk)
    }

    /// Reads a job's log to its end, re-attaching after drops
    public static func follow(jobID id: String,
                              from line: Int,
                              on host: SSHHostID,
                              runner: any SSHCommandRunner,
                              runTimeout: Duration,
                              reattaches: Int = 5,
                              retryDelay: Duration = .seconds(3),
                              onChunk: @escaping @Sendable (String) -> Void) async throws {
        var exitCode: Int?
        var tail = ""
        var consumed = line - 1
        var attempt = 0
        while true {
            let before = consumed
            do {
                for try await chunk in runner.stream(followCommand(jobID: id, fromLine: consumed + 1),
                                                     on: host, timeout: runTimeout) {
                    let text: String
                    switch chunk {
                    case .stdout(let value), .stderr(let value): text = value
                    }
                    tail = OutputTail.tail(tail + text)
                    consumed += text.utf8.reduce(0) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
                    for piece in text.split(separator: "\n", omittingEmptySubsequences: false) {
                        if piece.hasPrefix(exitMarker) {
                            exitCode = Int(piece.dropFirst(exitMarker.count)) ?? -1
                            continue
                        }
                        guard !piece.isEmpty else { continue }
                        onChunk(String(piece) + "\n")
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if exitCode == nil, attempt >= reattaches { throw error }
            }
            if exitCode != nil { break }
            if consumed > before { attempt = 0 }
            guard attempt < reattaches, !Task.isCancelled else { break }
            attempt += 1
            try? await Task.sleep(for: retryDelay)
        }
        guard let exitCode else {
            throw ServerControlError.commandFailed(command: id, exitCode: nil, stderr: tail)
        }
        if exitCode != 0 {
            throw ServerControlError.commandFailed(command: id, exitCode: Int32(exitCode), stderr: tail)
        }
    }

    public static func list(on host: SSHHostID,
                            runner: any SSHCommandRunner,
                            timeout: Duration) async throws -> [Job] {
        let result = try await runner.run(listCommand(), on: host, timeout: timeout)
        return parseList(result.stdout)
    }
}

/// A place for a `@Sendable` chunk handler to accumulate into
final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    func append(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        storage += text
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
