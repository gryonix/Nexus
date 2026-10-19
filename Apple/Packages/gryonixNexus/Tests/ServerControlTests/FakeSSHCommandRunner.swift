import Foundation
@testable import ServerControl

class FakeSSHCommandRunner: SSHCommandRunner, @unchecked Sendable {
    enum CallKind: Equatable {
        case run, stream, fireAndForget
    }

    struct Call: Equatable {
        let kind: CallKind
        let command: String
        let host: SSHHostID
    }

    struct Stub {
        /// Substring the incoming command must contain; "" matches anything
        let match: String
        let result: Result<ExecResult, Error>
    }

    private let lock = NSLock()
    private var stubs: [Stub] = []
    private(set) var calls: [Call] = []
    /// Fallback when the stub queue is exhausted
    var defaultResult = ExecResult(exitCode: 0, stdout: "", stderr: "")

    func stub(_ match: String, stdout: String = "", exitCode: Int32 = 0, stderr: String = "") {
        lock.lock(); defer { lock.unlock() }
        stubs.append(Stub(match: match,
                          result: .success(ExecResult(exitCode: exitCode, stdout: stdout, stderr: stderr))))
    }

    func stubFailure(_ match: String, error: Error) {
        lock.lock(); defer { lock.unlock() }
        stubs.append(Stub(match: match, result: .failure(error)))
    }

    private func noteLaunch(_ command: String, result: ExecResult) {
        guard command.contains(DetachedJobs.exitMarker), command.contains("$DETACH") else { return }
        lock.lock(); defer { lock.unlock() }
        detached = (id: command, output: result)
    }

    private func takeDetached(matching command: String) -> ExecResult? {
        lock.lock(); defer { lock.unlock() }
        guard detached != nil, command.contains(DetachedJobs.exitMarker) else { return nil }
        let pending = detached?.output
        detached = nil
        return pending
    }

    private func record(_ kind: CallKind, _ command: String, _ host: SSHHostID) {
        lock.lock(); defer { lock.unlock() }
        calls.append(Call(kind: kind, command: command, host: host))
    }

    private func nextResult(for command: String) throws -> ExecResult {
        lock.lock(); defer { lock.unlock() }
        guard !stubs.isEmpty else { return defaultResult }
        let stub = stubs.removeFirst()
        precondition(stub.match.isEmpty || command.contains(stub.match),
                     "expected command containing '\(stub.match)', got '\(command)'")
        return try stub.result.get()
    }

    /// Secrets handed over on stdin, in order
    private(set) var fed: [String] = []

    func run(_ command: String, feeding secret: String, on host: SSHHostID,
             timeout: Duration) async throws -> ExecResult {
        noteFed(secret)
        return try await run(command, on: host, timeout: timeout)
    }

    private func noteFed(_ secret: String) {
        lock.lock(); defer { lock.unlock() }
        fed.append(secret)
    }

    func run(_ command: String, on host: SSHHostID, timeout: Duration) async throws -> ExecResult {
        record(.run, command, host)
        let result = try nextResult(for: command)
        noteLaunch(command, result: result)
        return command.contains("$DETACH") ? ExecResult(exitCode: 0, stdout: "", stderr: "") : result
    }

    private var detached: (id: String, output: ExecResult)?

    func stream(_ command: String, on host: SSHHostID, timeout: Duration) -> AsyncThrowingStream<ExecChunk, Error> {
        record(.stream, command, host)
        if let pending = takeDetached(matching: command) {
            return AsyncThrowingStream { continuation in
                if !pending.stdout.isEmpty { continuation.yield(.stdout(pending.stdout)) }
                if !pending.stderr.isEmpty { continuation.yield(.stderr(pending.stderr)) }
                continuation.yield(.stdout("\n\(DetachedJobs.exitMarker)\(pending.exitCode ?? 0)\n"))
                continuation.finish()
            }
        }
        return AsyncThrowingStream { continuation in
            do {
                let result = try nextResult(for: command)
                if !result.stdout.isEmpty { continuation.yield(.stdout(result.stdout)) }
                if !result.stderr.isEmpty { continuation.yield(.stderr(result.stderr)) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    func fireAndForget(_ command: String, on host: SSHHostID) async throws {
        record(.fireAndForget, command, host)
        _ = try nextResult(for: command)
    }

    private(set) var disconnects = 0

    func disconnect() async {
        lock.lock(); defer { lock.unlock() }
        disconnects += 1
    }
}

/// Counts sleeps instead of sleeping so poll loops run instantly
final class FakeSleeper: SleepProvider, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var sleeps: [Duration] = []

    func sleep(for duration: Duration) async throws {
        lock.lock(); defer { lock.unlock() }
        sleeps.append(duration)
    }
}
