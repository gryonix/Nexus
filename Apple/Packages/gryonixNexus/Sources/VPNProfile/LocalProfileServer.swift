import Foundation
import Network

public actor LocalProfileServer {
    private let profile: Data
    private let fileName: String
    /// The one path that gets the profile
    public nonisolated let path: String
    private var listener: NWListener?
    private var deadline: Task<Void, Never>?
    private var served: CheckedContinuation<Void, Never>?
    private var didServe = false

    public static let contentType = "application/x-apple-aspen-config"

    /// How long to wait for the browser
    public static let defaultPatience = Duration.seconds(30)

    private let patience: Duration

    public init(profile: Data, fileName: String, patience: Duration = LocalProfileServer.defaultPatience) {
        let safeName = Self.safe(fileName)
        self.profile = profile
        self.fileName = safeName
        self.path = "/\(UUID().uuidString)/\(safeName)"
        self.patience = patience
    }

    /// A name that cannot break a header or a path
    public static func safe(_ name: String) -> String {
        let cleaned = String(name.unicodeScalars.map { scalar in
            "\"\\/\r\n:".unicodeScalars.contains(scalar) || scalar.value < 32 ? "-" : Character(scalar)
        })
        return cleaned.isEmpty ? "profile.mobileconfig" : cleaned
    }

    public func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.serve(connection) }
        }

        let latch = ResumeLatch()
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if latch.claim() { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                case .failed(let error), .waiting(let error):
                    if latch.claim() { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        }

        deadline = Task { [weak self, patience] in
            try? await Task.sleep(for: patience)
            await self?.stop()
        }
        return port
    }

    /// Waits until a request has been answered
    public func waitUntilServed() async {
        if didServe { return }
        await withCheckedContinuation { continuation in
            served = continuation
        }
    }

    public func stop() {
        deadline?.cancel()
        deadline = nil
        listener?.cancel()
        listener = nil
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self, path] data, _, _, _ in
            guard let self else { return connection.cancel() }
            let requested = Self.requestedPath(in: data)
            guard requested == path else {
                let refusal = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
                connection.send(content: refusal, contentContext: .finalMessage, isComplete: true,
                                completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            Task { await self.send(to: connection) }
        }
    }

    /// The target of a GET request line
    static func requestedPath(in data: Data?) -> String? {
        guard let data, let text = String(data: data, encoding: .utf8),
              let line = text.components(separatedBy: "\r\n").first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        return String(parts[1])
    }

    private func send(to connection: NWConnection) {
        stop()
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: \(LocalProfileServer.contentType)\r
        Content-Disposition: attachment; filename="\(fileName)"\r
        Content-Length: \(profile.count)\r
        Connection: close\r
        \r

        """
        connection.send(content: Data(header.utf8) + profile,
                        contentContext: .finalMessage,
                        isComplete: true,
                        completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            Task { await self?.markServed() }
        })
    }

    private func markServed() {
        guard !didServe else { return }
        didServe = true
        served?.resume()
        served = nil
    }
}

private final class ResumeLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
