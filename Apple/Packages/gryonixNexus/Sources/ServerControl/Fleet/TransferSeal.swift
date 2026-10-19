import CommonCrypto
import CryptoKit
import Foundation

/// Passphrase encryption for exported server files
public enum TransferSeal {
    public static let type = "gryonixserver-sealed"
    public static let iterations = 600_000

    public enum Failure: Error, Equatable {
        case wrongPassphrase
        case unreadable
    }

    struct Envelope: Codable {
        var type: String
        var version: Int
        var kdf: String
        var iterations: Int
        var salt: Data
        var nonce: Data
        var ciphertext: Data
    }

    /// True when the file is a sealed export
    public static func isSealed(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(Envelope.self, from: data))?.type == type
    }

    public static func seal(_ plain: Data, passphrase: String,
                            salt: Data = randomBytes(16), nonce: Data = randomBytes(12)) throws -> Data {
        let key = try deriveKey(passphrase, salt: salt, iterations: iterations)
        let box = try AES.GCM.seal(plain, using: key, nonce: AES.GCM.Nonce(data: nonce))
        let envelope = Envelope(type: type, version: 1, kdf: "pbkdf2-sha256", iterations: iterations,
                                salt: salt, nonce: nonce, ciphertext: box.ciphertext + box.tag)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(envelope)
    }

    public static func open(_ sealed: Data, passphrase: String) throws -> Data {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: sealed),
              envelope.type == type, envelope.kdf == "pbkdf2-sha256",
              envelope.iterations > 0, envelope.iterations <= 10_000_000,
              envelope.ciphertext.count >= 16 else { throw Failure.unreadable }
        let key = try deriveKey(passphrase, salt: envelope.salt, iterations: envelope.iterations)
        let body = envelope.ciphertext
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: envelope.nonce),
                                            ciphertext: body.prefix(body.count - 16),
                                            tag: body.suffix(16))
            return try AES.GCM.open(box, using: key)
        } catch {
            throw Failure.wrongPassphrase
        }
    }

    public static func randomBytes(_ count: Int) -> Data {
        Data(SymmetricKey(size: SymmetricKeySize(bitCount: count * 8)).withUnsafeBytes { Array($0) })
    }

    static func deriveKey(_ passphrase: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let password = Array(passphrase.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password.map { Int8(bitPattern: $0) }, password.count,
                                 saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                                 &derived, derived.count)
        }
        guard status == kCCSuccess else { throw Failure.unreadable }
        return SymmetricKey(data: derived)
    }
}
