import Foundation
import Network

/// A transfer link over one TCP connection
public final class QuickTransferTCPLink: QuickTransferLink, @unchecked Sendable {
    let connection: NWConnection
    private let queue = DispatchQueue(label: "quicktransfer.tcp")

    init(connection: NWConnection) {
        self.connection = connection
    }

    /// Connects to the first address that answers
    public static func connectFirst(to addresses: [String], port: UInt16,
                                    timeout: TimeInterval = 4) async throws -> QuickTransferTCPLink {
        try await withThrowingTaskGroup(of: QuickTransferTCPLink?.self) { group in
            for address in addresses {
                group.addTask { try? await connect(host: address, port: port, timeout: timeout) }
            }
            for try await link in group {
                if let link {
                    group.cancelAll()
                    return link
                }
            }
            throw QuickTransferError.closed
        }
    }

    public static func connect(host: String, port: UInt16,
                               timeout: TimeInterval) async throws -> QuickTransferTCPLink {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw QuickTransferError.closed }
        let link = QuickTransferTCPLink(connection: NWConnection(host: NWEndpoint.Host(host),
                                                                 port: endpointPort, using: .tcp))
        try await withTaskCancellationHandler {
            try await link.start(timeout: timeout)
        } onCancel: {
            link.close()
        }
        return link
    }

    /// Starts the connection and waits until it is ready
    func start(timeout: TimeInterval) async throws {
        let once = QuickTransferOnce()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [connection] state in
                switch state {
                case .ready: once.run { continuation.resume() }
                case .failed, .cancelled:
                    once.run { continuation.resume(throwing: QuickTransferError.closed) }
                case .waiting:
                    connection.cancel()
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout) { [connection] in
                once.run {
                    connection.cancel()
                    continuation.resume(throwing: QuickTransferError.timedOut)
                }
            }
            connection.start(queue: queue)
        }
    }

    public func send(_ payload: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: QuickTransferFrames.frame(payload), completion: .contentProcessed { error in
                if error != nil {
                    continuation.resume(throwing: QuickTransferError.closed)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public func receive() async throws -> Data {
        let length = QuickTransferFrames.length(try await read(4))
        guard length <= QuickTransferFrames.maximum else { throw QuickTransferError.tooLarge }
        return try await read(length)
    }

    private func read(_ count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let data, data.count == count, error == nil {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: QuickTransferError.closed)
                }
            }
        }
    }

    public func close() { connection.cancel() }
}

/// Waits for receivers on a free TCP port
public final class QuickTransferTCPListener: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "quicktransfer.listener")

    public init() throws {
        listener = try NWListener(using: .tcp, on: .any)
    }

    /// Starts listening; returns the port chosen
    public func start(onLink: @escaping @Sendable (QuickTransferTCPLink) -> Void) async throws -> UInt16 {
        listener.newConnectionHandler = { connection in
            let link = QuickTransferTCPLink(connection: connection)
            Task {
                guard (try? await link.start(timeout: 10)) != nil else { return }
                onLink(link)
            }
        }
        let once = QuickTransferOnce()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    once.run { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed, .cancelled:
                    once.run { continuation.resume(throwing: QuickTransferError.closed) }
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    public func stop() { listener.cancel() }
}

/// Runs a block at most once, from any thread
final class QuickTransferOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ block: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { block() }
    }
}
