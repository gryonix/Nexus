import CryptoKit
import Foundation
import Security

public enum SSHKeyGenerationError: Error {
    case rsaFailed
    case unreadableRSAKey
}

/// Makes new user keys
public enum SSHKeyGenerator {
    public static let comment = "gryonixnexus-app"

    public static func generate(kind: SSHKeyKind, name: String) throws -> UserSSHKey {
        let material = try makeMaterial(kind)
        return UserSSHKey(
            name: name, kind: kind,
            publicKey: OpenSSHKeyEncoding.publicLine(material, kind: kind, comment: comment),
            privateKeyPEM: OpenSSHKeyEncoding.privatePEM(material, comment: comment))
    }

    static func makeMaterial(_ kind: SSHKeyKind) throws -> SSHKeyMaterial {
        switch kind {
        case .ed25519:
            let key = Curve25519.Signing.PrivateKey()
            return .ed25519(seed: key.rawRepresentation,
                            publicKey: key.publicKey.rawRepresentation)
        case .ecdsaP256:
            let key = P256.Signing.PrivateKey()
            return .ecdsaP256(publicPoint: key.publicKey.x963Representation,
                              privateScalar: key.rawRepresentation)
        case .rsa3072, .rsa4096:
            return try rsaMaterial(bits: kind.bits)
        }
    }

    private static func rsaMaterial(bits: Int) throws -> SSHKeyMaterial {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: bits,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let der = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
            throw SSHKeyGenerationError.rsaFailed
        }
        return try rsaMaterial(pkcs1: der)
    }

    /// Reads PKCS#1 RSAPrivateKey DER
    static func rsaMaterial(pkcs1 der: Data) throws -> SSHKeyMaterial {
        var reader = DERReader(der)
        guard var sequence = reader.sequence() else { throw SSHKeyGenerationError.unreadableRSAKey }
        let fields = (0..<9).compactMap { _ in sequence.integer() }
        guard fields.count == 9 else { throw SSHKeyGenerationError.unreadableRSAKey }
        return .rsa(modulus: fields[1], exponent: fields[2], privateExponent: fields[3],
                    coefficient: fields[8], prime1: fields[4], prime2: fields[5])
    }
}

private struct DERReader {
    private var bytes: [UInt8]
    private var index = 0

    init(_ data: Data) { bytes = Array(data) }

    private mutating func header(expecting tag: UInt8) -> Int? {
        guard index + 2 <= bytes.count, bytes[index] == tag else { return nil }
        index += 1
        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count > 0, count <= 4, index + count <= bytes.count else { return nil }
            length = bytes[index..<index + count].reduce(0) { $0 << 8 | Int($1) }
            index += count
        }
        return index + length <= bytes.count ? length : nil
    }

    mutating func sequence() -> DERReader? {
        guard let length = header(expecting: 0x30) else { return nil }
        defer { index += length }
        return DERReader(Data(bytes[index..<index + length]))
    }

    mutating func integer() -> Data? {
        guard let length = header(expecting: 0x02) else { return nil }
        defer { index += length }
        return Data(bytes[index..<index + length])
    }
}
