import Foundation
import AgentClient
import Citadel
import NIOCore

@available(macOS 15.0, *)
final class ExecByteStream: AgentByteStream, @unchecked Sendable {
    private let outbound: TTYStdinWriter
    private var iterator: TTYOutput.AsyncIterator
    private var pending = Data()
    private var finished = false
    private var stderrLog = Data()
    private static let stderrLimit = 2048

    /// stderr as text, trimmed, empty when the command said nothing
    var stderrText: String {
        String(decoding: stderrLog, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(inbound: TTYOutput, outbound: TTYStdinWriter) {
        self.outbound = outbound
        self.iterator = inbound.makeAsyncIterator()
    }

    func write(_ data: Data) async throws {
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        try await outbound.write(buffer)
    }

    func read() async throws -> Data {
        if !pending.isEmpty {
            defer { pending.removeAll(keepingCapacity: true) }
            return pending
        }
        while !finished {
            guard let output = try await iterator.next() else {
                finished = true
                return Data()
            }
            switch output {
            case .stdout(let buffer):
                if buffer.readableBytes > 0 {
                    return Data(buffer.readableBytesView)
                }
            case .stderr(let buffer):
                if stderrLog.count < Self.stderrLimit {
                    stderrLog.append(contentsOf: buffer.readableBytesView
                        .prefix(Self.stderrLimit - stderrLog.count))
                }
                continue
            }
        }
        return Data()
    }

    func close() async {
    }
}
