import Foundation
import Network

public enum TVLinkError: Error, Equatable {
    /// The other side closed, or the network went away
    case closed
    /// Nothing arrived in time
    case timedOut
    case connectionFailed(String)
}

/// One TCP connection speaking frames
public actor TVLinkConnection {
    private let connection: NWConnection
    private var reader = TVFrame.Reader()
    private let queue = DispatchQueue(label: "com.skaymer.gryonixnexus.tvlink")

    public init(_ connection: NWConnection) {
        self.connection = connection
    }

    public init(endpoint: NWEndpoint) {
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 8
        tcp.noDelay = true
        self.connection = NWConnection(to: endpoint, using: NWParameters(tls: nil, tcp: tcp))
    }

    /// The address the connection actually reached, once ready
    public var remoteHostPort: (host: String, port: UInt16)? {
        guard case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint else { return nil }
        let text: String
        switch host {
        case .ipv4(let address): text = "\(address)"
        case .ipv6(let address): text = "\(address)"
        case .name(let name, _): text = name
        @unknown default: return nil
        }
        return (text.split(separator: "%").first.map(String.init) ?? text, port.rawValue)
    }

    /// Waits until the connection is ready
    public func open(timeout: TimeInterval = 10) async throws {
        let once = OnceContinuation<Void>()
        let connection = self.connection
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                once.resume(.success(()))
            case .failed(let error):
                once.resume(.failure(TVLinkError.connectionFailed(error.localizedDescription)))
            case .waiting(let error):
                once.resume(.failure(TVLinkError.connectionFailed(error.localizedDescription)))
            case .cancelled:
                once.resume(.failure(TVLinkError.closed))
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) { once.resume(.failure(TVLinkError.timedOut)) }
        do {
            try await once.value()
        } catch {
            connection.cancel()
            throw error
        }
    }

    /// Starts a connection a listener handed over
    public func accept() {
        connection.start(queue: queue)
    }

    public func send(_ payload: Data) async throws {
        let once = OnceContinuation<Void>()
        connection.send(content: TVFrame.encode(payload), completion: .contentProcessed { error in
            once.resume(error.map { .failure(TVLinkError.connectionFailed($0.localizedDescription)) } ?? .success(()))
        })
        try await once.value()
    }

    public func send(_ message: TVHandshakeMessage) async throws {
        try await send(TVJSON.encode(message))
    }

    /// The next whole frame
    public func receive(timeout: TimeInterval = 20) async throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let frame = try reader.next() { return frame }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw TVLinkError.timedOut }
            reader.append(try await chunk(timeout: remaining))
        }
    }

    public func receiveHandshake(timeout: TimeInterval = 20) async throws -> TVHandshakeMessage {
        try await TVJSON.decode(TVHandshakeMessage.self, from: receive(timeout: timeout))
    }

    public func close() {
        connection.cancel()
    }

    private func chunk(timeout: TimeInterval) async throws -> Data {
        let once = OnceContinuation<Data>()
        let connection = self.connection
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            if let data, !data.isEmpty {
                once.resume(.success(data))
            } else if let error {
                once.resume(.failure(TVLinkError.connectionFailed(error.localizedDescription)))
            } else if isComplete {
                once.resume(.failure(TVLinkError.closed))
            } else {
                once.resume(.failure(TVLinkError.closed))
            }
        }
        queue.asyncAfter(deadline: .now() + timeout) {
            if once.resume(.failure(TVLinkError.timedOut)) { connection.cancel() }
        }
        return try await once.value()
    }
}

/// A continuation resumed by whichever of several callbacks comes first
final class OnceContinuation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var waiter: CheckedContinuation<Value, Error>?

    @discardableResult
    func resume(_ outcome: Result<Value, Error>) -> Bool {
        lock.lock()
        guard result == nil else { lock.unlock(); return false }
        result = outcome
        let pending = waiter
        waiter = nil
        lock.unlock()
        pending?.resume(with: outcome)
        return true
    }

    func value() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }
}
