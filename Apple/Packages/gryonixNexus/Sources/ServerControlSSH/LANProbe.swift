import Foundation
import Network

/// A quick knock that waits for an SSH greeting
enum LANProbe {
    static let timeout: Duration = .milliseconds(1500)

    static func answers(host: String, port: Int, within limit: Duration = timeout) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let outcome = ProbeOutcome()
        defer { connection.cancel() }
        return await withCheckedContinuation { continuation in
            outcome.set(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: awaitBanner(on: connection, outcome: outcome)
                case .failed, .waiting, .cancelled: outcome.finish(false)
                default: break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            Task {
                try? await Task.sleep(for: limit)
                outcome.finish(false)
            }
        }
    }
}

/// The SSH banner proves the machine, not the tunnel
private func awaitBanner(on connection: NWConnection, outcome: ProbeOutcome) {
    connection.receive(minimumIncompleteLength: 4, maximumLength: 64) { data, _, _, _ in
        outcome.finish(LANProbe.isSSHBanner(data ?? Data()))
    }
}

extension LANProbe {
    /// Bytes that open an SSH greeting
    static func isSSHBanner(_ data: Data) -> Bool {
        data.starts(with: Data("SSH-".utf8))
    }
}

/// Resumes the probe once, whichever answer comes first
private final class ProbeOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    func set(_ continuation: CheckedContinuation<Bool, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    func finish(_ answered: Bool) {
        let pending = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: answered)
    }
}
