import CryptoKit
import Foundation

/// Seals transfer frames with the key from the QR code
public struct QuickTransferCipher: Sendable {
    public enum Direction: UInt8, Sendable {
        case toSender = 1
        case toReceiver = 2
    }

    public static let nonceLength = 12
    static let tagLength = 16

    let key: SymmetricKey

    public init(key: Data) {
        self.key = SymmetricKey(data: key)
    }

    public func seal(_ plain: Data, direction: Direction, sequence: UInt64,
                     nonce: Data = TransferSeal.randomBytes(nonceLength)) throws -> Data {
        let box = try AES.GCM.seal(plain, using: key, nonce: AES.GCM.Nonce(data: nonce),
                                   authenticating: Self.header(direction, sequence))
        return nonce + box.ciphertext + box.tag
    }

    public func open(_ sealed: Data, direction: Direction, sequence: UInt64) throws -> Data {
        let bytes = Data(sealed)
        guard bytes.count >= Self.nonceLength + Self.tagLength else { throw QuickTransferError.notOurs }
        let body = Data(bytes.dropFirst(Self.nonceLength))
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: bytes.prefix(Self.nonceLength)),
                                            ciphertext: body.dropLast(Self.tagLength),
                                            tag: body.suffix(Self.tagLength))
            return try AES.GCM.open(box, using: key, authenticating: Self.header(direction, sequence))
        } catch {
            throw QuickTransferError.notOurs
        }
    }

    /// Four digits both screens show for the same hello
    public func code(for nonce: Data) -> String {
        let mac = Data(HMAC<SHA256>.authenticationCode(for: Data("code".utf8) + nonce, using: key))
        let number = mac.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return String(format: "%04u", number % 10_000)
    }

    static func header(_ direction: Direction, _ sequence: UInt64) -> Data {
        var data = Data(QuickTransferTicket.prefix.utf8)
        data.append(direction.rawValue)
        withUnsafeBytes(of: sequence.bigEndian) { data.append(contentsOf: $0) }
        return data
    }
}

public enum QuickTransferError: Error, Equatable, Sendable {
    case notOurs
    case declined
    case unexpected
    case tooLarge
    case closed
    case timedOut
}
