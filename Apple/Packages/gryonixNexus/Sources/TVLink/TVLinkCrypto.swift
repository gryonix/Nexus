import CryptoKit
import Foundation

/// Where the handshake gets its keys and nonces
public protocol TVLinkRandom: Sendable {
    func bytes(_ count: Int) -> Data
    func keyAgreementKey() -> P256.KeyAgreement.PrivateKey
}

public struct SystemTVLinkRandom: TVLinkRandom {
    public init() {}

    public func bytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    public func keyAgreementKey() -> P256.KeyAgreement.PrivateKey {
        P256.KeyAgreement.PrivateKey()
    }
}

/// The six digits a TV shows and a phone types
public struct TVPairingCode: Equatable, Sendable, CustomStringConvertible {
    public static let bitCount = 20
    public static let upperBound = 1_000_000

    public let value: Int

    public init?(value: Int) {
        guard (0..<Self.upperBound).contains(value) else { return nil }
        self.value = value
    }

    /// Digits typed with or without spaces
    public init?(_ text: String) {
        let digits = text.filter { !$0.isWhitespace && $0 != "-" }
        guard digits.count == 6, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
              let value = Int(digits) else { return nil }
        self.init(value: value)
    }

    /// A fresh code, uniformly drawn
    public static func random(_ random: TVLinkRandom) -> TVPairingCode {
        while true {
            let bytes = random.bytes(3)
            let candidate = bytes.reduce(0) { ($0 << 8) | Int($1) } & 0xFFFFF
            if let code = TVPairingCode(value: candidate) { return code }
        }
    }

    public func bit(_ round: Int) -> UInt8 {
        UInt8((value >> round) & 1)
    }

    /// "123 456", the way the TV draws it
    public var description: String {
        let text = String(format: "%06d", value)
        return "\(text.prefix(3)) \(text.suffix(3))"
    }

    public var digits: String { String(format: "%06d", value) }
}

/// The primitives, written once so both sides cannot drift apart
public enum TVLinkCrypto {
    public static let nonceLength = 32
    public static let commitNonceLength = 16

    public static func commitment(round: Int, bit: UInt8, ownKey: Data, peerKey: Data,
                                  nonce: Data) -> Data {
        var message = Data("gx-tv-commit".utf8)
        message.append(UInt8(round))
        message.append(ownKey)
        message.append(peerKey)
        message.append(bit)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: nonce))
        return Data(mac)
    }

    public static func sharedSecret(_ own: P256.KeyAgreement.PrivateKey, peer: Data) throws -> Data {
        let peerKey = try P256.KeyAgreement.PublicKey(x963Representation: peer)
        let secret = try own.sharedSecretFromKeyAgreement(with: peerKey)
        return secret.withUnsafeBytes { Data($0) }
    }

    /// HKDF-SHA256, 32 bytes
    public static func derive(_ material: Data, salt: Data, info: String) -> Data {
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: material), salt: salt,
                                         info: Data(info.utf8), outputByteCount: 32)
        return key.withUnsafeBytes { Data($0) }
    }

    public static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}

public struct TVTranscript: Sendable {
    private var bytes = Data("gryonixnexus-tv-v1".utf8)

    public init() {}

    public mutating func append(_ field: Data) {
        var length = UInt32(field.count).bigEndian
        bytes.append(Data(bytes: &length, count: 4))
        bytes.append(field)
    }

    public mutating func append(_ text: String) {
        append(Data(text.utf8))
    }

    public var hash: Data { TVLinkCrypto.sha256(bytes) }
}

/// AES-256-GCM in both directions, a counter for a nonce
public struct TVSecureChannel: Sendable {
    public enum Failure: Error, Equatable {
        case cannotOpen
    }

    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private var sent: UInt64 = 0
    private var received: UInt64 = 0

    public init(sendKey: Data, receiveKey: Data) {
        self.sendKey = SymmetricKey(data: sendKey)
        self.receiveKey = SymmetricKey(data: receiveKey)
    }

    public mutating func seal(_ plaintext: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: sendKey, nonce: Self.nonce(sent))
        sent += 1
        return box.ciphertext + box.tag
    }

    public mutating func open(_ sealed: Data) throws -> Data {
        guard sealed.count >= 16 else { throw Failure.cannotOpen }
        do {
            let box = try AES.GCM.SealedBox(nonce: Self.nonce(received),
                                            ciphertext: sealed.dropLast(16), tag: sealed.suffix(16))
            let plaintext = try AES.GCM.open(box, using: receiveKey)
            received += 1
            return plaintext
        } catch {
            throw Failure.cannotOpen
        }
    }

    public mutating func seal(_ message: TVMessage) throws -> Data {
        try seal(TVJSON.encode(message))
    }

    public mutating func openMessage(_ sealed: Data) throws -> TVMessage {
        try TVJSON.decode(TVMessage.self, from: open(sealed))
    }

    private static func nonce(_ counter: UInt64) -> AES.GCM.Nonce {
        var big = counter.bigEndian
        var bytes = Data(count: 4)
        bytes.append(Data(bytes: &big, count: 8))
        // Twelve bytes is the one length GCM always accepts.
        return try! AES.GCM.Nonce(data: bytes)
    }
}

/// The keys one finished handshake leaves behind
public struct TVHandshakeKeys: Sendable {
    public let phoneToTV: Data
    public let tvToPhone: Data
    /// Only after pairing: the secret every later session starts from
    public let pairingKey: Data?

    static func derive(material: Data, transcript: Data, pairing: Bool) -> TVHandshakeKeys {
        TVHandshakeKeys(
            phoneToTV: TVLinkCrypto.derive(material, salt: transcript, info: "gx-tv phone->tv"),
            tvToPhone: TVLinkCrypto.derive(material, salt: transcript, info: "gx-tv tv->phone"),
            pairingKey: pairing ? TVLinkCrypto.derive(material, salt: transcript, info: "gx-tv pairing key") : nil)
    }

    public var phoneChannel: TVSecureChannel {
        TVSecureChannel(sendKey: phoneToTV, receiveKey: tvToPhone)
    }

    public var tvChannel: TVSecureChannel {
        TVSecureChannel(sendKey: tvToPhone, receiveKey: phoneToTV)
    }
}
