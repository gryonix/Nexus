import Foundation

/// Speaks Connect-RPC over HTTP/1.1 on top of an `AgentByteStream`
public struct ConnectTransport: AgentTransport {
    private let factory: AgentStreamFactory
    private let deviceUID: String

    public init(factory: AgentStreamFactory, deviceUID: String = "") {
        self.factory = factory
        self.deviceUID = deviceUID
    }

    /// How long a unary call may stay silent
    static let unaryDeadline: Duration = .seconds(300)

    public func unary(path: String, request: Data) async throws -> Data {
        let stream = try await factory.open()
        let expired = ExpiryFlag()
        let watchdog = Task {
            try await Task.sleep(for: Self.unaryDeadline)
            expired.fire()
            await stream.close()
        }
        defer { watchdog.cancel() }
        do {
            try await stream.write(HTTPWire.request(path: path, contentType: "application/proto",
                                                    body: request, deviceUID: deviceUID))
            let reader = ByteReader(stream: stream)
            let head = try await HTTPWire.readHead(reader)
            let body = try await HTTPWire.readBody(reader, head)
            await stream.close()
            guard head.status == 200 else {
                throw parseConnectError(from: body, status: head.status)
            }
            return body
        } catch {
            await stream.close()
            if expired.hasFired { throw AgentError.transport("The server did not answer in time.") }
            throw error
        }
    }

    public func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let stream: AgentByteStream
                do {
                    stream = try await factory.open()
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                do {
                    // A server-streaming request is exactly one enveloped message.
                    let enveloped = ConnectEnvelope.encode(request)
                    try await stream.write(HTTPWire.request(
                        path: path, contentType: "application/connect+proto", body: enveloped,
                        deviceUID: deviceUID))
                    let reader = ByteReader(stream: stream)
                    let head = try await HTTPWire.readHead(reader)
                    guard head.status == 200 else {
                        let body = try await HTTPWire.readBody(reader, head)
                        throw parseConnectError(from: body, status: head.status)
                    }
                    var decoder = ConnectEnvelope.Decoder()
                    var ended = false
                    try await HTTPWire.readChunks(reader, head) { chunk in
                        decoder.append(chunk)
                        while let frame = try decoder.next() {
                            if frame.isEndOfStream {
                                if let err = parseConnectTrailer(frame.payload) { throw err }
                                ended = true
                                return false // clean end-of-stream
                            }
                            continuation.yield(frame.payload)
                        }
                        return true
                    }
                    guard ended else { throw AgentError.transport(ConnectEnvelope.cutOffMessage) }
                    await stream.close()
                    continuation.finish()
                } catch {
                    await stream.close()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Set when the watchdog closed a silent stream
final class ExpiryFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func fire() { lock.withLock { fired = true } }
    var hasFired: Bool { lock.withLock { fired } }
}

// MARK: - Connect error decoding

public func parseConnectError(from body: Data, status: Int) -> AgentError {
    if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
       let code = obj["code"] as? String {
        return .rpc(code: code, message: obj["message"] as? String ?? "")
    }
    return .rpc(code: "http_\(status)", message: String(decoding: body, as: UTF8.self))
}

/// An end-of-stream envelope is JSON: `{}` on success, or `{"error": {...}}`
public func parseConnectTrailer(_ payload: Data) -> AgentError? {
    guard !payload.isEmpty,
          let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
          let err = obj["error"] as? [String: Any] else { return nil }
    return .rpc(code: err["code"] as? String ?? "unknown", message: err["message"] as? String ?? "")
}

// MARK: - Buffered reader

/// Buffers an `AgentByteStream` into line/count/chunk reads for HTTP parsing
public final class ByteReader {
    private let stream: AgentByteStream
    private var buffer = Data()
    private var eof = false

    public init(stream: AgentByteStream) { self.stream = stream }

    private func fill() async throws {
        guard !eof else { return }
        let chunk = try await stream.read()
        if chunk.isEmpty { eof = true } else { buffer.append(chunk) }
    }

    public func readLine() async throws -> String {
        let crlf = Data([0x0d, 0x0a])
        while true {
            if let r = buffer.range(of: crlf) {
                let line = buffer.subdata(in: buffer.startIndex ..< r.lowerBound)
                buffer.removeSubrange(buffer.startIndex ..< r.upperBound)
                return String(decoding: line, as: UTF8.self)
            }
            if eof {
                let line = buffer
                buffer.removeAll()
                return String(decoding: line, as: UTF8.self)
            }
            try await fill()
        }
    }

    public func read(_ count: Int) async throws -> Data {
        while buffer.count < count && !eof { try await fill() }
        let n = min(count, buffer.count)
        let out = buffer.subdata(in: buffer.startIndex ..< (buffer.startIndex + n))
        buffer.removeSubrange(buffer.startIndex ..< (buffer.startIndex + n))
        return out
    }

    public func readAll() async throws -> Data {
        while !eof { try await fill() }
        let out = buffer
        buffer.removeAll()
        return out
    }
}

// MARK: - HTTP/1.1 framing

public enum HTTPWire {
    public struct Head {
        public let status: Int
        public let chunked: Bool
        public let contentLength: Int?
    }

    public static func request(path: String, contentType: String, body: Data,
                               deviceUID: String = "") -> Data {
        var head = "POST \(path) HTTP/1.1\r\n"
        head += "Host: localhost\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        if !deviceUID.isEmpty {
            head += "X-Gryonix-Device: \(deviceUID)\r\n"
        }
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        return out
    }

    public static func readHead(_ reader: ByteReader) async throws -> Head {
        let statusLine = try await reader.readLine()
        let parts = statusLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2, let status = Int(parts[1]) else {
            throw AgentError.transport("bad status line: \(statusLine)")
        }
        var chunked = false
        var contentLength: Int?
        while true {
            let line = try await reader.readLine()
            if line.isEmpty { break }
            let lower = line.lowercased()
            if lower.hasPrefix("transfer-encoding:") && lower.contains("chunked") {
                chunked = true
            } else if lower.hasPrefix("content-length:") {
                contentLength = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces))
            }
        }
        return Head(status: status, chunked: chunked, contentLength: contentLength)
    }

    /// The full body of a non-streaming response
    public static func readBody(_ reader: ByteReader, _ head: Head) async throws -> Data {
        if head.chunked {
            var out = Data()
            try await readChunks(reader, head) { out.append($0); return true }
            return out
        }
        if let n = head.contentLength { return try await reader.read(n) }
        return try await reader.readAll()
    }

    /// Feed each body chunk to `onChunk` as it arrives
    public static func readChunks(_ reader: ByteReader, _ head: Head, _ onChunk: (Data) throws -> Bool) async throws {
        guard head.chunked else {
            let body: Data
            if let n = head.contentLength { body = try await reader.read(n) } else { body = try await reader.readAll() }
            _ = try onChunk(body)
            return
        }
        while true {
            let sizeLine = try await reader.readLine()
            let hex = sizeLine.split(separator: ";").first.map(String.init) ?? sizeLine
            guard let size = Int(hex.trimmingCharacters(in: .whitespaces), radix: 16) else {
                throw AgentError.transport("bad chunk size: \(sizeLine)")
            }
            if size == 0 {
                _ = try await reader.readLine() // final CRLF after the terminator
                return
            }
            let chunk = try await reader.read(size)
            _ = try await reader.readLine() // CRLF after each chunk
            if try !onChunk(chunk) { return }
        }
    }
}
