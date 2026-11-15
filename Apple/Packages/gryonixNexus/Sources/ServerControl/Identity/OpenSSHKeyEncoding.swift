import Foundation

/// Key material in the pieces OpenSSH encodes
public enum SSHKeyMaterial: Sendable {
    case ed25519(seed: Data, publicKey: Data)
    case ecdsaP256(publicPoint: Data, privateScalar: Data)
    case rsa(modulus: Data, exponent: Data, privateExponent: Data,
             coefficient: Data, prime1: Data, prime2: Data)
}

/// OpenSSH public and private key text
public enum OpenSSHKeyEncoding {
    public static func publicBlob(_ key: SSHKeyMaterial) -> Data {
        var wire = SSHWireWriter()
        switch key {
        case .ed25519(_, let publicKey):
            wire.string("ssh-ed25519")
            wire.string(publicKey)
        case .ecdsaP256(let point, _):
            wire.string("ecdsa-sha2-nistp256")
            wire.string("nistp256")
            wire.string(point)
        case .rsa(let modulus, let exponent, _, _, _, _):
            wire.string("ssh-rsa")
            wire.mpint(exponent)
            wire.mpint(modulus)
        }
        return wire.data
    }

    public static func publicLine(_ key: SSHKeyMaterial, kind: SSHKeyKind, comment: String) -> String {
        let base64 = publicBlob(key).base64EncodedString()
        return "\(kind.algorithm) \(base64) \(comment)"
    }

    public static func privatePEM(_ key: SSHKeyMaterial, comment: String,
                                  checkInt: UInt32 = .random(in: .min ... .max)) -> String {
        var file = SSHWireWriter()
        file.raw(Data("openssh-key-v1\0".utf8))
        file.string("none")
        file.string("none")
        file.string(Data())
        file.uint32(1)
        file.string(publicBlob(key))
        file.string(privateSection(key, comment: comment, checkInt: checkInt))
        return wrap(file.data.base64EncodedString())
    }

    private static func privateSection(_ key: SSHKeyMaterial, comment: String,
                                       checkInt: UInt32) -> Data {
        var section = SSHWireWriter()
        section.uint32(checkInt)
        section.uint32(checkInt)
        appendPrivateFields(key, to: &section)
        section.string(comment)
        var pad: UInt8 = 1
        while section.data.count % 8 != 0 {
            section.raw(Data([pad]))
            pad += 1
        }
        return section.data
    }

    private static func appendPrivateFields(_ key: SSHKeyMaterial, to wire: inout SSHWireWriter) {
        switch key {
        case .ed25519(let seed, let publicKey):
            wire.string("ssh-ed25519")
            wire.string(publicKey)
            wire.string(seed + publicKey)
        case .ecdsaP256(let point, let scalar):
            wire.string("ecdsa-sha2-nistp256")
            wire.string("nistp256")
            wire.string(point)
            wire.mpint(scalar)
        case .rsa(let n, let e, let d, let iqmp, let p, let q):
            wire.string("ssh-rsa")
            [n, e, d, iqmp, p, q].forEach { wire.mpint($0) }
        }
    }

    private static func wrap(_ base64: String) -> String {
        var lines: [String] = []
        var rest = Substring(base64)
        while !rest.isEmpty {
            lines.append(String(rest.prefix(70)))
            rest = rest.dropFirst(70)
        }
        return (["-----BEGIN OPENSSH PRIVATE KEY-----"] + lines
                + ["-----END OPENSSH PRIVATE KEY-----"]).joined(separator: "\n") + "\n"
    }
}
