import Foundation

/// The two sides of a transfer conversation
public enum QuickTransferFlow {
    public struct Hello: Equatable, Sendable {
        public var device: String
        public var code: String
    }

    // MARK: - Sender

    /// Reads the first message; anything but our hello is refused
    public static func greet(_ channel: QuickTransferChannel) async throws -> Hello {
        let message = try await channel.receive()
        guard message.kind == .hello, let raw = message.nonce,
              let nonce = Base64URL.decode(raw), nonce.count == 16 else { throw QuickTransferError.unexpected }
        let device = String((message.device ?? "").prefix(64))
        return Hello(device: device, code: channel.code(for: nonce))
    }

    public static func accept(_ channel: QuickTransferChannel) async throws {
        try await channel.send(QuickTransferMessage(kind: .accept))
    }

    public static func decline(_ channel: QuickTransferChannel) async {
        try? await channel.send(QuickTransferMessage(kind: .decline))
        channel.close()
    }

    /// Sends the servers and waits for the count imported
    public static func deliver(_ channel: QuickTransferChannel, servers: [String]) async throws -> Int {
        try await channel.send(QuickTransferMessage(kind: .servers, servers: servers))
        let reply = try await channel.receive()
        guard reply.kind == .done else { throw QuickTransferError.unexpected }
        return reply.imported ?? servers.count
    }

    // MARK: - Receiver

    /// Says hello; returns the code to show
    public static func knock(_ channel: QuickTransferChannel, device: String,
                             nonce: Data = TransferSeal.randomBytes(16)) async throws -> String {
        try await channel.send(QuickTransferMessage(kind: .hello, device: device,
                                                    nonce: Base64URL.encode(nonce)))
        return channel.code(for: nonce)
    }

    /// Waits for the sender's answer
    public static func awaitAnswer(_ channel: QuickTransferChannel) async throws {
        switch try await channel.receive().kind {
        case .accept: return
        case .decline: throw QuickTransferError.declined
        default: throw QuickTransferError.unexpected
        }
    }

    /// Receives the servers and confirms them
    public static func collect(_ channel: QuickTransferChannel) async throws -> [String] {
        let message = try await channel.receive()
        guard message.kind == .servers, let servers = message.servers else { throw QuickTransferError.unexpected }
        try await channel.send(QuickTransferMessage(kind: .done, imported: servers.count))
        return servers
    }
}
