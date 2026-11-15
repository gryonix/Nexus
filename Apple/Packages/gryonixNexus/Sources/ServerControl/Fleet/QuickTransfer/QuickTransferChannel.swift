import Foundation

/// One message of the transfer conversation
public struct QuickTransferMessage: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case hello, accept, decline, servers, done
    }

    public var kind: Kind
    public var device: String?
    public var nonce: String?
    public var servers: [String]?
    public var imported: Int?

    public init(kind: Kind, device: String? = nil, nonce: String? = nil,
                servers: [String]? = nil, imported: Int? = nil) {
        self.kind = kind
        self.device = device
        self.nonce = nonce
        self.servers = servers
        self.imported = imported
    }
}

/// A byte pipe carrying one payload at a time
public protocol QuickTransferLink: AnyObject, Sendable {
    func send(_ payload: Data) async throws
    func receive() async throws -> Data
    func close()
}

/// Length-prefixed payloads over a byte stream
public struct QuickTransferFrames: Sendable {
    public static let maximum = 8 << 20

    private var buffer = Data()

    public init() {}

    public static func frame(_ payload: Data) -> Data {
        var data = Data()
        withUnsafeBytes(of: UInt32(payload.count).bigEndian) { data.append(contentsOf: $0) }
        return data + payload
    }

    /// Adds received bytes, returns every payload now complete
    public mutating func append(_ bytes: Data) throws -> [Data] {
        buffer.append(bytes)
        var payloads: [Data] = []
        while buffer.count >= 4 {
            let length = Self.length(buffer.prefix(4))
            guard length <= Self.maximum else { throw QuickTransferError.tooLarge }
            guard buffer.count >= 4 + length else { break }
            payloads.append(Data(buffer.dropFirst(4).prefix(length)))
            buffer = Data(buffer.dropFirst(4 + length))
        }
        return payloads
    }

    static func length(_ header: Data) -> Int {
        Int(header.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
    }
}

/// Encrypted, compressed messages over a link
public final class QuickTransferChannel: @unchecked Sendable {
    public enum Role: Sendable { case sender, receiver }

    public let link: any QuickTransferLink
    let cipher: QuickTransferCipher
    let role: Role
    private var sent: UInt64 = 0
    private var received: UInt64 = 0

    public init(link: any QuickTransferLink, key: Data, role: Role) {
        self.link = link
        self.cipher = QuickTransferCipher(key: key)
        self.role = role
    }

    public func send(_ message: QuickTransferMessage) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plain = try QuickTransferDeflate.compress(encoder.encode(message))
        let direction: QuickTransferCipher.Direction = role == .sender ? .toReceiver : .toSender
        let sealed = try cipher.seal(plain, direction: direction, sequence: sent)
        sent += 1
        try await link.send(sealed)
    }

    public func receive() async throws -> QuickTransferMessage {
        let sealed = try await link.receive()
        let direction: QuickTransferCipher.Direction = role == .sender ? .toSender : .toReceiver
        let plain = try cipher.open(sealed, direction: direction, sequence: received)
        received += 1
        guard let message = try? JSONDecoder().decode(QuickTransferMessage.self,
                                                      from: QuickTransferDeflate.decompress(plain)) else {
            throw QuickTransferError.unexpected
        }
        return message
    }

    public func code(for nonce: Data) -> String { cipher.code(for: nonce) }

    public func close() { link.close() }
}

/// Raw DEFLATE, the same bytes zlib writes without a header
enum QuickTransferDeflate {
    static func compress(_ data: Data) throws -> Data {
        try (data as NSData).compressed(using: .zlib) as Data
    }

    static func decompress(_ data: Data) throws -> Data {
        try (data as NSData).decompressed(using: .zlib) as Data
    }
}
